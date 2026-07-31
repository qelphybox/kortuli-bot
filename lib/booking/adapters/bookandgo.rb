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
    # down to its own `location_id`. That costs one identical request per club
    # per date, which is three where one would do; polling is four minutes
    # apart and the alternative is a cache shared between adapter instances,
    # which is a lot of machinery to save two requests.
    #
    # Courts are named, with stable integer ids, so this is a court-level club.
    #
    # Two things the source does not do for us, both verified live:
    #
    # 1. It does not drop hours that have already gone — at 02:09 local it
    #    still offered 00:00 that same day. Nothing downstream filters them, so
    #    a past slot would sit in the snapshot until the day rolled over.
    # 2. It offers the same court and hour once per bookable duration (60, 90
    #    and 120 minutes are separate rows). Taking all of them would hand the
    #    differ three overlapping slots for one hour.
    class Bookandgo
      BASE_URL = "https://api.bookandgo.app/api/v1/apps/58".freeze
      # Krtsanisi's own window is the longest of the three at 22–30 days. Past
      # it the API returns an empty booking list rather than phantom free
      # slots, so this cap is about not making pointless requests.
      DEFAULT_MAX_DAYS = 30
      # A Slot is one bookable hour, so the hour-long row is the one to read.
      DEFAULT_DURATION_MINUTES = 60

      def initialize(club, http:)
        @club = club
        @http = http
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @location_id = club.settings.fetch("location_id")
        @duration = Integer(club.settings.fetch("duration_minutes", DEFAULT_DURATION_MINUTES))
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range, now: Clock.now)
        date_range.to_a.first(@max_days)
                  .flat_map { day_slots(_1, now) }
                  .uniq(&:key)
      end

      private

      def day_slots(date, now)
        rows(date).flat_map { |row| row_slots(row, now) }
      end

      def rows(date)
        url = "#{@base_url}/court-bookings"
        payload = @http.get_json(url, { "date" => date.to_s })
        bookings = payload.dig("data", "bookings") if payload.is_a?(Hash)
        # A refusal here wears a 200 with a `status: error` body. Parsed
        # literally that reads as every court in the club being booked at once.
        raise SourceUnavailable, "#{url}: no data.bookings in #{payload.inspect[0, 200]}" unless bookings.is_a?(Array)

        bookings.select { mine?(_1) }
      end

      # The payload carries every club of the tenant and every duration on
      # offer; this club wants one location at one duration.
      def mine?(row)
        row.dig("location", "id").to_s == @location_id.to_s && row["duration"] == @duration
      end

      def row_slots(row, now)
        row.dig("location", "courts").to_a.flat_map do |court|
          court["timings"].to_a.flat_map { |timing| timing_slots(row, court, timing, now) }
        end
      end

      def timing_slots(row, court, timing, now)
        date = timing.fetch("date")

        timing["available_time_slots"].to_a.filter_map do |time|
          next unless on_the_hour?(time)

          starts_at = Clock.local_to_utc("#{date} #{time}")
          # Hours already gone are still offered; see the class comment.
          next if starts_at <= now

          slot(row, court, starts_at)
        end
      end

      # The source offers :00 and :30 starts, but a Slot is one bookable hour
      # and the Grid draws one column per hour — a slot at 08:30 would match no
      # cell and disappear from the app. Dropping them here is a decision, not
      # an oversight: watching half-hour starts means teaching the Grid about
      # them first.
      def on_the_hour?(time) = time.to_s.split(":")[1] == "00"

      def slot(row, court, starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(court.fetch("id")),
          court_label: court["court_name"] || court.fetch("id").to_s,
          starts_at:,
          ends_at: starts_at + (@duration * 60),
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
