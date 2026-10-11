require "date"
require "time"

module Booking
  module Adapters
    # Lemans Padel books through a hand-rolled PHP API on its own subdomain,
    # read by a vanilla-JS widget on the WordPress site. No login, no nonce,
    # no cookie — every call below works cold.
    #
    # `/availability` reports every start of a day with an explicit
    # `available` flag, so there is nothing to invert. Asked without a court it
    # says how many of the four are free; asked with `court_id` it answers for
    # that court alone and echoes the id back. This adapter asks per court:
    # four requests a date instead of one, and in return the club is
    # court-level and a cancellation on court 3 is an event even while court 2
    # stood empty.
    #
    # Courts are read per tick rather than pinned, the way PadelHub's are — one
    # request, and a fifth court would show up without a config change.
    class Lemans
      BASE_URL = "https://booking.lemanspadel.ge/api".freeze
      # Nothing on the server bounds the window: a date a year out, or one
      # already gone, answers with every hour free. The widget's picker has no
      # `maxDate` either. This caps what we ask for; the horizon does the rest.
      DEFAULT_MAX_DAYS = 14
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
        courts = self.courts

        date_range.to_a.first(@max_days)
                  .flat_map { |date| courts.flat_map { court_slots(_1, date, now) } }
                  .uniq(&:key)
      end

      private

      def courts
        url = "#{@base_url}/courts"
        payload = @http.get_json(url)
        courts = payload["courts"] if payload.is_a?(Hash)
        # No courts means nothing to ask about, and an empty fetch after a full
        # one reads as the whole club booking up at once.
        raise SourceUnavailable, "#{url}: no courts in #{payload.inspect[0, 200]}" unless courts.is_a?(Array) && courts.any?

        courts
      end

      def court_slots(court, date, now)
        day(court, date).filter_map do |entry|
          next unless entry["available"] == true && on_the_hour?(entry["start"])

          # `start_datetime` already files 00:00 and 01:00 under the calendar
          # date they fall on, so no rollover heuristic is needed here.
          starts_at = Clock.local_to_utc(entry.fetch("start_datetime"))
          slot(court, starts_at) if starts_at > now
        end
      end

      def day(court, date)
        url = "#{@base_url}/availability"
        id = court.fetch("id")
        payload = @http.get_json(url, { "date" => date.to_s, "duration" => DURATION_MINUTES, "court_id" => id })
        slots = payload["slots"] if payload.is_a?(Hash)
        raise SourceUnavailable, "#{url}: no slots in #{payload.inspect[0, 200]}" unless slots.is_a?(Array)
        # Without the filter the same route answers for the whole club, and
        # `available` then means *some* court — read as this one, every court
        # would look free whenever any was.
        raise SourceUnavailable, "#{url}: asked for court #{id}, answered for #{payload["court_id"].inspect}" unless payload["court_id"].to_s == id.to_s

        slots
      end

      # Half-hour starts are dropped for the same reason Book & Go's are: the
      # Grid matches a Cell on an exact hourly `starts_at`.
      def on_the_hour?(start) = start.to_s.split(":")[1] == "00"

      def slot(court, starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(court.fetch("id")),
          # `name` is Georgian ("კორტი #1"); everything else we print is English.
          court_label: "Court #{court["court_number"] || court.fetch("id")}",
          starts_at:,
          ends_at: starts_at + (DURATION_MINUTES * 60),
          price: @club.settings["price"],
          # The widget can prefill a court and an hour, but only from a
          # server-rendered attribute, never from the URL.
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
