require "time"

module Booking
  module Adapters
    # Lemans Padel books through a hand-rolled PHP API on its own subdomain,
    # behind a vanilla-JS widget on the WordPress site. Reads are open: no
    # cookie, no nonce, plain GET.
    #
    # `/api/availability` reports a whole day in one request — every start
    # with an explicit `available` flag and how many of the four courts are
    # free. It does not say *which*: that is `/api/availability/courts`, one
    # request per start. Asking it for every partly booked hour would be dozens
    # of requests every tick against a small PHP host, so this adapter reads
    # the count and nothing else.
    #
    # A count is still enough to be a court-level club. Each free court
    # becomes a Slot of its own, numbered by how many are free rather than by
    # which court it is: with two free, the Slots are "1 of the free" and
    # "2 of the free". A cancellation that takes the count from one to two
    # makes the second appear, which is exactly the event worth sending — the
    # one Kus Tba, watched by the hour, cannot see. What it costs is a name:
    # the Slot says "a court", because the number is not a court's.
    #
    # Starts come every half hour, and the half-hour ones are dropped, for the
    # same reason Book & Go's are: the Grid matches a Cell on an exact hourly
    # `starts_at`.
    class Lemans
      BASE_URL = "https://booking.lemanspadel.ge".freeze
      # The widget's date picker has no upper bound and neither has the API:
      # it answers for any date, a past one included, and far enough out every
      # hour reads free because nobody can have booked it yet. This caps what
      # we ask for; the horizon does the rest.
      DEFAULT_MAX_DAYS = 14
      # A Slot is one bookable hour, so the other durations on offer (90 and
      # 120 minutes) are never asked for.
      DURATION_MINUTES = 60
      COURT_LABEL = "A court".freeze

      def initialize(club, http:, clock: Clock)
        @club = club
        @http = http
        @clock = clock
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range)
        now = @clock.now

        date_range.to_a.first(@max_days).flat_map { day_slots(_1, now) }.uniq(&:key)
      end

      private

      def day_slots(date, now)
        starts(date).flat_map do |start|
          # `start_datetime` carries the calendar date the hour actually falls
          # on, so the 00:00 and 01:00 listed under a date are already filed on
          # the next one. Local wall-clock, no offset in the string.
          starts_at = Clock.local_to_utc(start.fetch("start_datetime"))
          next [] unless start["available"] && on_the_hour?(starts_at) && starts_at > now

          start["available_courts"].to_i.times.map { slot(_1 + 1, starts_at) }
        end
      end

      def starts(date)
        url = "#{@base_url}/api/availability"
        payload = @http.get_json(url, { "date" => date.to_s, "duration" => DURATION_MINUTES })
        starts = payload["slots"] if payload.is_a?(Hash)
        # A refused request answers 200 with `{"error": …}`. Read literally,
        # that is a day with no free court in it — every hour sold out at once.
        raise SourceUnavailable, "#{url}: no slots in #{payload.inspect[0, 200]}" unless starts.is_a?(Array)

        starts
      end

      def on_the_hour?(starts_at) = Clock.to_local(starts_at).min.zero?

      def slot(nth_free, starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref: "free-#{nth_free}",
          court_label: COURT_LABEL,
          starts_at:,
          ends_at: starts_at + (DURATION_MINUTES * 60),
          price: @club.settings["price"],
          # The widget can be prefilled, but only from an attribute the server
          # renders, never from the query string — so the page itself is the
          # most a link can do.
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
