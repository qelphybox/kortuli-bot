require "date"
require "json"
require "time"

module Booking
  module Adapters
    # Tbilisi Padel runs BookingPress (1.6.7 as of 2026-10-13) on WordPress, with
    # the plugin's Vue 3 form reading through its own REST namespace. No login
    # and no cookie, but every read carries three tokens the page hands to each
    # visitor: a `wp_rest` nonce in the `X-WP-Nonce` header, a form nonce, and
    # a per-render `instanceId`/`instanceToken` pair the server checks as a
    # matched pair — so they are scraped from a real render, never made up.
    #
    # `month-details` answers a whole month per request, and it answers with
    # *free* hours only: a booked hour is simply missing. 2310 rows read in
    # July and 1556 on 2026-10-13, `is_available` 1 on every one; where one of
    # several courts is booked, the row stays and `remaining_capacity` drops.
    # So nothing is inverted.
    #
    # One site, one form, several locations: each location is a BookingPress
    # *service* on the same form, and each is its own Club here, told apart by
    # `service_id` — the same shape as GymBreeze's `location_id`.
    #
    # A service with several courts says how many are free in
    # `remaining_capacity`, never which. A court-level club therefore gets one
    # Slot per free court under a counting ref ("1".."n"): the Grid counts them,
    # and a cancellation shows up as the count going up. Which court it was is
    # unknowable, so the label does not pretend.
    class Bookingpress
      BASE_URL = "https://tbilisipadel.ge".freeze
      # The English render; the Georgian one at "/" carries the same ids and
      # the same nonces.
      FORM_PATH = "/en/".freeze
      ROUTE = "/wp-json/bookingpress-app/v1/form-v3/month-details".freeze
      # Anchored on the island's id: the page carries a second, unrelated
      # `"nonces"` object (Elementor's), so a bare regex for one finds the
      # wrong tokens. The island is plain JSON, not HTML-escaped.
      ISLAND = %r{<script id="wp-script-module-data-bookingpress-form-v3-loader" type="application/json">(.*?)</script>}m
      # The form offers a year ahead and the server answers for all of it —
      # 2027-06 read entirely empty. Nothing that far out ever transitions;
      # bookings seen on 2026-10-13 reached five days ahead. This caps what we
      # ask for; the horizon does the rest.
      DEFAULT_MAX_DAYS = 14
      HOUR = 3600
      # There is no court to name at hour level. A constant ref keeps the slot
      # key stable; the label is what the notification prints.
      COURT_REF = "any".freeze
      COURT_LABEL = "A court".freeze
      # What a refused token comes back as — 403 for either nonce, 400 for an
      # instance the server no longer knows. `Http` reports only the status, so
      # that is what is matched. A 401 is never one of these.
      STALE = /returned 40[03]\z/

      Session = Data.define(:instance_id, :rest_nonce, :form_nonce, :instance_token, :service_ids) do
        def headers = { "X-WP-Nonce" => rest_nonce }

        def body = { "bp_v3_nonce" => form_nonce, "bp_v3_instance_token" => instance_token, "instanceId" => instance_id }
      end

      # Three locations share one form, and the poller builds a fresh adapter
      # every tick — scraping per adapter would fetch the same 95 KB page three
      # times every four minutes. Kept per site, for the life of the process,
      # and thrown away the first time the server refuses it. A pair scraped
      # on 2026-07-30 still answered 20 minutes later; WordPress nonces last
      # 12–24 h by default, so this should re-scrape about daily — inferred,
      # not measured.
      def self.sessions = @sessions ||= {}

      def initialize(club, http:, clock: Clock, sessions: self.class.sessions)
        @club = club
        @http = http
        @clock = clock
        @sessions = sessions
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @service_id = Integer(club.settings.fetch("service_id"))
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range)
        now = @clock.now

        date_range.to_a.first(@max_days)
                  .group_by { [_1.year, _1.month] }
                  .flat_map { |(year, month), dates| month_slots(year, month, dates, now) }
                  .uniq(&:key)
      end

      private

      def month_slots(year, month, dates, now)
        days = month(year, month)

        dates.flat_map do |date|
          Array(days[date.to_s]).flat_map { row_slots(date, _1, now) }
        end
      end

      def month(year, month)
        url = "#{@base_url}#{ROUTE}"
        # `selected_month` is 1–12, not zero-padded — the site's own body.
        body = { "service_id" => @service_id, "from_date" => format("%04d-%02d-01", year, month), "selected_year" => year, "selected_month" => month }
        payload = signed { |session| @http.post_json(url, body.merge(session.body), headers: session.headers) }

        days = payload.dig("data", "working_details") if payload.is_a?(Hash) && payload["ok"] == true
        # PHP's empty array: a month with nothing left in it comes back as `[]`
        # rather than `{}`.
        days = {} if days == []
        raise SourceUnavailable, "#{url}: no working_details in #{payload.inspect[0, 200]}" unless days.is_a?(Hash)

        days
      end

      # A business day can run past midnight — Didi Dighomi sells 00:00 and
      # 01:00 under the date before — and the source says which calendar date
      # such an hour really falls on in `store_service_date`. The single-court
      # services, which shut at midnight, leave the field out.
      def row_slots(date, row, now)
        start = row.fetch("start_time")
        free = Integer(row.fetch("remaining_capacity", 1))
        # Never seen false, but it is the field's whole meaning.
        return [] unless row["is_available"] == 1 && free.positive? && on_the_hour?(start)

        starts_at = Clock.local_to_utc("#{row["store_service_date"] || date} #{start}")
        # The server already holds back what is too close to start (30–60
        # minutes per service); checking again keeps a stale answer out.
        return [] unless starts_at > now

        refs(free).map { slot(_1, starts_at) }
      end

      def refs(free)
        return [COURT_REF] unless @club.court_level?

        # Capped at the declared count, so a Cell never reads "5 of 4".
        (1..[free, Integer(@club.court_count)].min).map { @club.canonical_court(_1.to_s) }
      end

      # Every start seen so far is on the hour; this is here so that a
      # half-hour grid, if the club ever adopts one, is dropped the way Book &
      # Go's is rather than drawn nowhere — the Grid matches on an hourly start.
      def on_the_hour?(start) = start.to_s.split(":")[1] == "00"

      # One fresh scrape per refusal; a second refusal is an ordinary failure
      # for the tick.
      def signed
        yield session
      rescue SourceUnavailable => e
        raise unless e.message.match?(STALE)

        @sessions.delete(@base_url)
        yield session
      end

      def session
        session = @sessions[@base_url] ||= scrape
        # An unknown service is answered `ok` with an empty month, which would
        # read as a location fully booked. Asking about one the form does not
        # offer is a broken config or a renumbered site, not data.
        unless session.service_ids.include?(@service_id)
          raise SourceUnavailable, "#{@base_url}: service #{@service_id} is not on the booking form (it offers #{session.service_ids.join(", ")})"
        end

        session
      end

      def scrape
        url = "#{@base_url}#{FORM_PATH}"
        island = @http.get_body(url).dup.force_encoding(Encoding::UTF_8)[ISLAND, 1]
        raise SourceUnavailable, "#{url}: no BookingPress form on the page" unless island

        # Exactly one form on the page; its key is the instance id.
        instance = Hash(JSON.parse(island).fetch("instances")).values.first || {}
        nonces = instance.fetch("nonces")
        Session.new(
          instance_id: instance.fetch("instanceId"),
          rest_nonce: nonces.fetch("wpRestNonce"),
          form_nonce: nonces.fetch("formNonce"),
          instance_token: nonces.fetch("instanceToken"),
          service_ids: instance.fetch("services").map { Integer(_1.fetch("serviceId")) }
        )
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError => e
        raise SourceUnavailable, "#{url}: unreadable BookingPress form — #{e.class} #{e.message}"
      end

      def slot(court_ref, starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref:,
          # Even at court level the source says how many, never which — so
          # "Court 3" would be a guess.
          court_label: COURT_LABEL,
          starts_at:,
          ends_at: starts_at + HOUR,
          price: @club.settings["price"],
          # Five guesses at a preselecting parameter all came back with
          # `is_from_url: 0`; the form is all there is.
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
