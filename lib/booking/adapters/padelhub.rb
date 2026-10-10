require "date"
require "time"

module Booking
  module Adapters
    # PadelHub is a Vite/React site over Supabase. Its booking page makes two
    # reads, both with the project's publishable anon key — the key the site
    # ships to every browser, not a credential — and so do we: the active court
    # list, then one RPC per court and date. The `bookings` table itself is
    # closed by row-level security; the RPC is the door the club built.
    #
    # The RPC reports what is *taken*, so the free hours are the club's day
    # minus those. The day is the declared opening hours — the site hard-codes
    # the same grid client-side, 08:00 to 00:00, and files that midnight under
    # the date before it, which is exactly how `OpeningHours` rolls a day over.
    #
    # Courts are read per tick rather than pinned in config, because the club
    # has already opened one more since it was first looked at. Pickleball
    # shares the table and is left out.
    class Padelhub
      BASE_URL = "https://gpypwkyuangjzgabagyi.supabase.co/rest/v1".freeze
      # Publishable: it sits in the site's entry bundle, role `anon`, and opens
      # nothing the booking page does not already show anyone.
      ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdweXB3a3l1YW5nanpnYWJhZ3lpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg3MDczMTMsImV4cCI6MjA5NDI4MzMxM30.s_s7BS2fS_qir43c-m8URuT-3cZnlZ8xdBHG6a7Jazs".freeze
      # The site's date picker has no upper bound, and a day nobody can see
      # yet reads as entirely free. This only caps what we ask for; the
      # horizon does the rest.
      DEFAULT_MAX_DAYS = 14
      SPORT = "padel".freeze
      # The site's own predicate: an hour is taken while a `confirmed` row
      # holds it, whether paid or a checkout still in progress. Anything else —
      # a `cancelled` row included — leaves it free.
      TAKEN = "confirmed".freeze
      HOUR = 3600

      def initialize(club, http:, clock: Clock)
        @club = club
        @http = http
        @clock = clock
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @headers = { "apikey" => ANON_KEY, "Authorization" => "Bearer #{ANON_KEY}" }
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
        @labels = club.settings.fetch("court_labels", {})
      end

      def fetch(date_range)
        now = @clock.now
        courts = padel_courts

        date_range.to_a.first(@max_days)
                  .flat_map { |date| courts.flat_map { court_slots(_1, date, now) } }
                  .uniq(&:key)
      end

      private

      def padel_courts
        url = "#{@base_url}/courts"
        rows = @http.get_json(url, { "select" => "id,name,sport_type", "is_active" => "eq.true" }, headers: @headers)
        courts = rows.select { _1["sport_type"] == SPORT } if rows.is_a?(Array)
        # No courts would mean no grid to subtract from, and an empty fetch
        # after a full one reads as the whole club booking up at once.
        raise SourceUnavailable, "#{url}: no #{SPORT} courts in #{rows.inspect[0, 200]}" if courts.nil? || courts.empty?

        courts
      end

      def court_slots(court, date, now)
        taken = taken_labels(court, date)

        @club.opening_hours.starts_by_label(date).filter_map do |label, starts_at|
          # Inverting a booked list hands back the hours already gone too; the
          # site greys them out, and so must we.
          slot(court, starts_at) unless taken.include?(label) || starts_at <= now
        end
      end

      def taken_labels(court, date)
        url = "#{@base_url}/rpc/get_booking_availability"
        rows = @http.post_json(url, { "p_booking_date" => date.to_s, "p_court_id" => court.fetch("id") }, headers: @headers)
        # Inverted, an error body would read as a court with nothing booked —
        # a whole day freeing up at once.
        raise SourceUnavailable, "#{url}: expected a list of bookings, got #{rows.inspect[0, 200]}" unless rows.is_a?(Array)

        rows.select { _1["status"] == TAKEN }.map { _1["time_slot"].to_s }
      end

      def slot(court, starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(court.fetch("id")),
          # `name` is an i18n key ("court_padel_closed"), not something to print.
          court_label: @labels.fetch(court["name"].to_s, court["name"]),
          starts_at:,
          ends_at: starts_at + HOUR,
          price: @club.settings["price"],
          # The booking page reads no court, date or hour from its URL.
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
