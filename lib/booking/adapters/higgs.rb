require "date"
require "time"

module Booking
  module Adapters
    # Higgs in Rustavi books through its own ASP.NET app, read by a React
    # client at higgs.ge/booking. The two routes that client reads before
    # anyone logs in — the court list and a court's day — are plain GETs with
    # no token, no cookie and no nonce. Everything under /api/admin wants a
    # login and is never touched.
    #
    # `/bookings/available-slots` answers for one court at a time, so this is a
    # court-level club at the price of three requests a date. A taken hour is
    # absent from the answer rather than flagged: on 2026-10-13 court 1 listed
    # thirteen of its sixteen hours, and the missing three were the booked ones.
    #
    # Courts are read per tick rather than pinned, the way Lemans's are — one
    # request, and a fourth court would show up without a config change.
    class Higgs
      BASE_URL = "https://higgs.ge/api".freeze
      # The server answers for any date, a year out or already gone, with every
      # hour free. The club's own picker pages through four dates at a time and
      # stops three pages in: today and the six after it.
      DEFAULT_MAX_DAYS = 7
      # The server takes 60 or 120 and refuses anything else. A Slot is one
      # bookable hour.
      DURATION_MINUTES = 60
      # The court list carries a "Club" entry beside the real courts: 08:00 to
      # 16:00 at 250 GEL an hour, a booking for the whole venue. The club's own
      # client hides it by this exact id, so this adapter does too.
      WHOLE_CLUB = "ce5f18a4-2ac9-4972-ab6f-3c609e2544dc".freeze
      # The client paints Pending yellow and Confirmed red, so the server can
      # send either. Only Available is free: Pending is somebody at checkout.
      AVAILABLE = 0

      def initialize(club, http:, clock: Clock)
        @club = club
        @http = http
        @clock = clock
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range)
        now = @clock.now
        courts = self.courts

        date_range.to_a.first(@max_days)
                  .flat_map { |date| courts.flat_map { court_slots(_1, date, now) } }
                  .uniq(&:key)
      end

      private

      def courts
        url = "#{@base_url}/courts"
        payload = @http.get_json(url)
        courts = payload.select { _1.is_a?(Hash) && _1["isActive"] == true && _1["id"] != WHOLE_CLUB } if payload.is_a?(Array)
        # No courts means nothing to ask about, and an empty fetch after a full
        # one reads as the whole club booking up at once.
        raise SourceUnavailable, "#{url}: no courts in #{payload.inspect[0, 200]}" unless courts&.any?

        courts
      end

      def court_slots(court, date, now)
        day(court, date).filter_map do |entry|
          next unless entry["status"] == AVAILABLE && on_the_hour?(entry["startTime"])

          # `startTime` is the club's wall clock with no offset, and a full
          # date-time — an hour after midnight would carry tomorrow's date
          # itself, so nothing here rolls the day over.
          starts_at = Clock.local_to_utc(entry.fetch("startTime"))
          # Verified live: at 23:03 local the server still offered 08:00 that
          # same day. Nothing downstream drops a past slot.
          slot(court, starts_at) if starts_at > now
        end
      end

      def day(court, date)
        url = "#{@base_url}/bookings/available-slots"
        params = { "courtId" => court.fetch("id"), "date" => date.to_s, "durationMinutes" => DURATION_MINUTES }
        payload = @http.get_json(url, params)
        slots = payload["timeSlots"] if payload.is_a?(Hash)
        # A refusal arrives as a bare JSON array of messages ("Court not
        # found"), which has no `timeSlots` to read as an empty day.
        raise SourceUnavailable, "#{url}: no timeSlots in #{payload.inspect[0, 200]}" unless slots.is_a?(Array)

        slots
      end

      # Every hour-long start is on the hour today; the client drops any that
      # is not, and so does this, for the same reason Book & Go's half hours go.
      def on_the_hour?(start_time) = start_time.to_s[/T\d{2}:(\d{2})/, 1] == "00"

      def slot(court, starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(court.fetch("id")),
          court_label: court["name"] || court.fetch("id"),
          starts_at:,
          ends_at: starts_at + (DURATION_MINUTES * 60),
          price: @club.settings["price"],
          # The client's one per-slot route is its checkout, which takes the
          # price as a query parameter. A notification lands on the picker
          # instead of on a checkout we filled in.
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
