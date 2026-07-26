require "date"
require "time"

module Booking
  module Adapters
    # Kus Tba Padel runs WordPress with the `turtle-booking` plugin, which
    # publishes an unauthenticated REST API — no nonce, no cookie, plain GET.
    #
    # It answers two ways. `/available-courts` names the individual court but
    # costs one request per open hour: 110 per poll across the club's window,
    # against 7 for `/available-slots`, which reports a whole day at once but
    # only says whether *some* court is free that hour. This adapter takes the
    # cheap one, so a Slot here stands for an hour rather than a court.
    #
    # What that trades away: an hour turns available only when its last booked
    # court frees up, so a cancellation on court 3 while 1 and 2 already stood
    # empty raises no event. That is the hour a watcher wanted to hear about
    # anyway — they get told when a full hour reopens, which is the whole
    # product — and it keeps a shared-hosting WordPress install from taking a
    # hundred requests every four minutes.
    class Kustba
      BASE_URL = "https://kustbapadel.ge/wp-json/turtle-booking/v1".freeze
      # The booking widget's own `max_days`. Overridable per club, because this
      # is the one number the club can change without redesigning anything.
      DEFAULT_MAX_DAYS = 7
      # `full` means every court is taken, `inactive` means past or closed.
      AVAILABLE = "available".freeze
      # There is no court to name at this granularity. A constant ref keeps the
      # slot key stable; the label is what the notification prints.
      COURT_REF = "any".freeze
      COURT_LABEL = "A court".freeze

      def initialize(club, http:)
        @club = club
        @http = http
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range)
        # The API answers for any date, including ones past the club's own
        # window — where every hour reads `available` because nobody can book
        # it yet. Slots out there would never transition, so never ask.
        date_range.to_a.first(@max_days).flat_map { day_slots(_1) }.uniq(&:key)
      end

      private

      def day_slots(date)
        hours = fetch_hours(date)
        starts = self.class.starts_at(date, hours.map { _1["time"] })

        hours.each_with_index.filter_map do |hour, index|
          slot(starts[index]) if hour["status"] == AVAILABLE
        end
      end

      def fetch_hours(date)
        payload = @http.get_json("#{@base_url}/available-slots", { "date" => date.to_s })
        # A renamed route answers 200 with a JSON error body. That parses
        # cleanly and would otherwise read as "no slots" — which is to say, as
        # every court in the club being booked at once.
        raise SourceUnavailable, "#{@base_url}/available-slots: expected a list of hours, got #{payload.class}" unless payload.is_a?(Array)

        payload
      end

      # The club's day runs past midnight — the feed lists 08:00 … 23:00, then
      # 00:00 and 01:00, and those last two belong to the next calendar day
      # even though the API files them under the requested date. Roll the day
      # over when the clock goes backwards rather than hardcoding an opening
      # hour, so a change of schedule cannot quietly misfile a night slot.
      def self.starts_at(date, times)
        day = 0
        previous = nil

        times.map do |time|
          hour = time.to_s.split(":").first.to_i
          day += 1 if previous && hour < previous
          previous = hour
          Clock.local_to_utc("#{date + day} #{time}")
        end
      end

      def slot(starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref: COURT_REF,
          court_label: COURT_LABEL,
          starts_at:,
          ends_at: starts_at + 3600,
          price: @club.settings["price"],
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
