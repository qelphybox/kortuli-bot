require "date"
require "time"

module Booking
  module Adapters
    # Padelbade runs on Book & Go, a white-label platform whose Flutter client
    # reads availability with a plain unauthenticated GET — no token, no cookie,
    # no nonce. Its endpoint table marks this route `authRequired = false`, and
    # only mutations carry a bearer.
    #
    # One request returns the *whole tenant*: every Georgian Padelbade club in
    # one payload, keyed by location. Each is its own Club here — Krtsanisi and
    # Dighomi are opposite ends of town — so each filters the shared response
    # down to its own location. That costs one identical request per club per
    # date; the alternative is a cache shared between adapter instances, which
    # is a lot of machinery to save one request every four minutes.
    #
    # Another operator is another tenant on the same API, so a club outside
    # Padelbade names its own `base_url` — Love Padel in Kutaisi is apps/126.
    #
    # Courts are named, with stable integer ids, so this is a court-level club.
    #
    # The source offers each court-hour once per bookable duration — 60, 90 and
    # 120 minutes are separate entries over the same courts. A Slot is one
    # bookable hour, so only the hour-long one is read; taking all three would
    # hand the differ three overlapping slots for one hour.
    #
    # It also offers starts every half hour. Those are dropped, which is a
    # decision rather than an oversight: the Grid matches a Cell to a Slot on an
    # exact hourly `starts_at`, so an 08:30 Slot would match no Cell and vanish
    # from the app while still raising notifications. Watching half-hour starts
    # means teaching the Grid about them first.
    class Bookandgo
      BASE_URL = "https://api.bookandgo.app/api/v1/apps/58".freeze
      # Past a club's own window the API returns an empty list rather than
      # phantom free slots, so this cap only saves pointless requests. The
      # longest window on offer is Krtsanisi's, whose best courts reach 30.
      DEFAULT_MAX_DAYS = 30
      # A Slot is one bookable hour, which is the whole reason the other
      # durations are ignored — so this is a constant, not a setting.
      DURATION_MINUTES = 60

      # The clock is a dependency because this source, unlike the others, keeps
      # offering hours that have already gone; see `fresh?`.
      def initialize(club, http:, clock: Clock)
        @club = club
        @http = http
        @clock = clock
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @location_id = club.settings.fetch("location_id")
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range)
        now = @clock.now

        date_range.to_a.first(@max_days)
                  .flat_map { day_slots(_1, now) }
                  .uniq(&:key)
      end

      private

      def day_slots(date, now)
        ours(date).flat_map { variant_slots(_1, now) }
      end

      # One entry of `data.bookings` is one location at one duration, so the
      # club's hour-long courts are a single entry among the tenant's many.
      def ours(date)
        url = "#{@base_url}/court-bookings"
        payload = @http.get_json(url, { "date" => date.to_s })
        variants = payload.dig("data", "bookings") if payload.is_a?(Hash)
        # A refusal here wears a 200 with a `status: error` body. Parsed
        # literally that reads as every court in the club being booked at once.
        raise SourceUnavailable, "#{url}: no data.bookings in #{payload.inspect[0, 200]}" unless variants.is_a?(Array)

        variants.select do |variant|
          variant.dig("location", "id").to_s == @location_id.to_s &&
            variant["duration"] == DURATION_MINUTES &&
            padel?(variant)
        end
      end

      # A location can rent more than padel. Love Padel's lists two pickleball
      # courts as variants of their own under the same location id and the same
      # durations, told apart only by `sport` — without this they would count
      # as two more padel courts, free nearly all day.
      def padel?(variant) = variant.dig("sport", "sport_name").to_s.casecmp?("padel")

      def variant_slots(variant, now)
        variant.dig("location", "courts").to_a.flat_map do |court|
          court["timings"].to_a.flat_map { |timing| timing_slots(court, timing, now) }
        end
      end

      def timing_slots(court, timing, now)
        date = timing.fetch("date")

        timing["available_time_slots"].to_a.filter_map do |time|
          starts_at = Clock.local_to_utc("#{date} #{time}")

          slot(court, starts_at) if on_the_hour?(time) && fresh?(starts_at, now)
        end
      end

      def on_the_hour?(time) = time.to_s.split(":")[1] == "00"

      # Verified live: at 02:09 local the feed still offered 00:00 that same
      # day. Nothing downstream drops a past slot, so it would sit in the
      # snapshot until the day rolled over.
      def fresh?(starts_at, now) = starts_at > now

      def slot(court, starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(court.fetch("id")),
          court_label: court["court_name"] || court.fetch("id").to_s,
          starts_at:,
          ends_at: starts_at + (DURATION_MINUTES * 60),
          price: @club.settings["price"],
          # The Flutter router addresses only bookings that already exist, so
          # there is nothing per-court to link to; the configured club URL is
          # the best a notification can offer, as with GymBreeze.
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
