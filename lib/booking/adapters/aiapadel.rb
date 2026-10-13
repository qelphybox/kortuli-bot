require "date"
require "time"

module Booking
  module Adapters
    # AIA Padel (Kutaisi) is a Next.js site over its own JSON API. Its client
    # has a sign-in, a bearer and a payment flow, but sends none of that for
    # the three reads its booking page opens with: the bookable dates, the
    # court list, and one court's starts for one date at one duration. Those go
    # out with `auth: "none"`; `/me` and `/bookings` answer 401 without a
    # token. So we read what the page shows anyone before they sign in, and
    # stop there.
    #
    # The API does insist on two headers its client always sends — `X-Client`
    # and `Accept-Language` — and answers 400 `missing_header` without them.
    # Neither is a credential: both are constants in the bundle.
    #
    # Every start of the day comes back with an explicit `isAvailable`, so
    # there is nothing to invert. Courts are named and asked one by one, which
    # makes this a court-level club.
    class Aiapadel
      BASE_URL = "https://api.aiapadel.ge/v1".freeze
      HEADERS = { "X-Client" => "consumer", "Accept-Language" => "en" }.freeze
      # The `/days` list is the club's own window — ten dates, counting today.
      # The slots route answers past it (and for dates already gone) with every
      # hour free, so the list is what bounds us; this only caps it.
      DEFAULT_MAX_DAYS = 10
      # The source offers 60, 90 and 120 minutes over the same courts. A Slot
      # is one bookable hour, so only that one is read.
      DURATION_MINUTES = 60

      def initialize(club, http:, clock: Clock)
        @club = club
        @http = http
        @clock = clock
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range)
        now = @clock.now
        dates = bookable_dates & date_range.to_a.first(@max_days)
        courts = self.courts

        dates.flat_map { |date| courts.flat_map { court_slots(_1, date, now) } }.uniq(&:key)
      end

      private

      def bookable_dates
        url = "#{@base_url}/bookings/availability/days"
        days = @http.get_json(url, {}, headers: HEADERS)
        raise SourceUnavailable, "#{url}: expected a list of days, got #{days.inspect[0, 200]}" unless days.is_a?(Array)

        # A date the club has shut is listed with `isAvailable: false` and
        # greyed out in the picker; asking it for starts would be wasted.
        days.select { _1["isAvailable"] == true }.map { Date.iso8601(_1.fetch("date")) }
      end

      def courts
        url = "#{@base_url}/catalog/courts"
        courts = @http.get_json(url, {}, headers: HEADERS)
        active = courts.select { _1["isActive"] == true } if courts.is_a?(Array)
        # No courts means nothing to ask about, and an empty fetch after a full
        # one reads as the whole club booking up at once.
        raise SourceUnavailable, "#{url}: no active courts in #{courts.inspect[0, 200]}" if active.nil? || active.empty?

        # An inactive court (Court 4, in October 2026) is refused by the slots
        # route with a 400, which would fail the whole tick.
        active
      end

      def court_slots(court, date, now)
        # The source files tonight's 00:00 under today, after 23:30 — a bare
        # wall-clock label for a business day, which is what `starts_by_label`
        # reads. A label outside the declared hours has no Cell to land in,
        # and neither has a half-hour start: the Grid matches a Cell on an
        # exact hourly `starts_at`, so "23:30" finds no key and drops out.
        starts = @club.opening_hours.starts_by_label(date)

        day(court, date).filter_map do |entry|
          starts_at = starts[entry["startTime"].to_s]
          next unless entry["isAvailable"] == true && starts_at

          # Today's gone hours already read as taken, but only today's: a date
          # in the past answers entirely free. Checked here rather than trusted.
          slot(court, starts_at) if starts_at > now
        end
      end

      def day(court, date)
        url = "#{@base_url}/bookings/availability/slots"
        payload = @http.get_json(url, { "date" => date.to_s, "courtId" => court.fetch("id"), "durationMinutes" => DURATION_MINUTES },
                                 headers: HEADERS)
        slots = payload["slots"] if payload.is_a?(Hash) && payload["date"] == date.to_s
        raise SourceUnavailable, "#{url}: no slots for #{date} in #{payload.inspect[0, 200]}" unless slots.is_a?(Array)

        slots
      end

      def slot(court, starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(court.fetch("id")),
          court_label: court["name"] || court.fetch("id"),
          starts_at:,
          ends_at: starts_at + (DURATION_MINUTES * 60),
          price: @club.settings["price"],
          # The booking page restores a draft from session storage, never from
          # its URL, so there is nothing to prefill.
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
