require "time"

module Booking
  module Adapters
    # Reservio exposes a public JSON:API that needs no authentication, and its
    # availability endpoint returns *only* free slots — which is exactly the
    # contract every adapter owes the differ. Courts carry stable uuids, so no
    # name synthesis is needed here.
    #
    # A business models its courts one of two ways, and the adapter takes both
    # through one setting, `service_ids`. Some sell one service ("Padel, 60
    # min") over N resources, one per court. Padel Port Batumi sells one
    # service *per court* — six services, each over a single resource — and
    # splits them across two locations, so the club is whichever services are
    # that location's courts. Either way a slot names its resource, and the
    # resource is the court.
    #
    # `filter[serviceId]` takes exactly one uuid: a comma-separated pair is a
    # 400 ("Invalid UUID string"), `filter[serviceId][]` a 500, and leaving it
    # out a 404. So it is one request per service — four a tick for Padel
    # Port, which is still one per court rather than one per court per date.
    class Reservio
      BASE_URL = "https://api.reservio.com/v2".freeze
      PAGE_LIMIT = 200
      MAX_PAGES = 20

      def initialize(club, http:)
        @club = club
        @http = http
        @business_id = club.settings.fetch("business_id")
        # `service_id` is the single-service spelling from before a club could
        # be more than one service; still read, so an old config keeps working.
        @service_ids = Array(club.settings.fetch("service_ids") { club.settings.fetch("service_id") })
        raise Error, "#{club.slug}: service_ids is empty" if @service_ids.empty?

        @max_days = club.settings["max_days"]&.then { Integer(_1) }
      end

      def fetch(date_range)
        courts = fetch_courts
        date_range = clamp(date_range)
        records = @service_ids.flat_map { fetch_time_slots(date_range, _1) }
        # A snapshot must hold each slot once: the differ compares by key, and
        # the slots table has a unique index on it.
        records.filter_map { to_slot(_1, courts) }.uniq(&:key)
      end

      private

      # Reservio enforces a business's own window server-side — Padel Port's
      # `reservationsLaterThan` is 604800 s, and dates past D+7 answer
      # `total: 0` rather than phantom free slots — so this only trims the
      # request. It is read so that `max_days` in config means what it means
      # for every other adapter.
      def clamp(date_range)
        return date_range unless @max_days

        date_range.first..[date_range.last, date_range.first + @max_days - 1].min
      end

      def fetch_courts
        url = "#{BASE_URL}/businesses/#{@business_id}/resources"
        data(url, @http.get_json(url)).to_h { [_1["id"], _1.dig("attributes", "name")] }
      end

      def fetch_time_slots(date_range, service_id)
        url = "#{BASE_URL}/businesses/#{@business_id}/availability/booking-slots"
        params = {
          "filter[from]" => date_range.first.iso8601,
          "filter[to]" => date_range.last.iso8601,
          "filter[serviceId]" => service_id,
          # Sent because it is the documented contract, not because it works —
          # see the stop condition below for what this endpoint actually does.
          "page[limit]" => PAGE_LIMIT
        }
        records = []

        MAX_PAGES.times do
          body = @http.get_json(url, params)
          records.concat(data(url, body))

          # `links.next` alone is not a reliable stop condition: this endpoint
          # ignores page[limit]/page[offset], returns the entire result set, and
          # advertises a next link regardless. Following it downloads the same
          # slots again. The declared total is the trustworthy signal. Still
          # true in October 2026: page[limit]=5 on Padel Port's Court 1 handed
          # back all 88 slots with `total: 88` and a next link at offset 5.
          total = body.dig("meta", "total")
          break if total && records.size >= total

          # Next links come back fully formed, filters included; rebuilding the
          # query by hand is how off-by-one paging bugs get written.
          url = body.dig("links", "next")
          break if url.nil? || url.empty?

          params = {}
        end

        records
      end

      # An empty list is an answer — a court can sell out. No list at all is
      # not, and reading it as one would empty the club and make the next good
      # poll look like every court freeing at once.
      def data(url, body)
        list = body["data"] if body.is_a?(Hash)
        raise SourceUnavailable, "#{url}: no data in #{body.inspect[0, 200]}" unless list.is_a?(Array)

        list
      end

      def to_slot(record, courts)
        attributes = record["attributes"] or return nil
        court_id = record.dig("relationships", "resource", "data", "id") or return nil
        # Reservio timestamps carry their offset, so no zone guessing here —
        # and no rollover either. A date's 00:00 and 01:00 are listed *after*
        # its 23:00, which looks like Kus Tba's late hours, but they are dated
        # correctly: at 23:05 on 13 Oct, `filter[to]=2026-10-14` offered
        # 2026-10-14T00:00 and nothing at all on the 13th.
        starts_at = Time.iso8601(attributes.fetch("start"))
        # Every business seen so far sells on the hour (`reservationsSlotSize`
        # 3600). One that sold half hours would hand the Grid starts it cannot
        # place in a Cell.
        return nil unless starts_at.min.zero?

        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(court_id),
          # A court added since the last resources call still deserves a
          # notification; an ugly label beats a dropped slot.
          court_label: courts[court_id] || court_id,
          starts_at:,
          ends_at: Time.iso8601(attributes.fetch("end")),
          price: @club.settings["price"],
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
