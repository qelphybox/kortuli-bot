require "time"

module Booking
  module Adapters
    # Reservio exposes a public JSON:API that needs no authentication, and its
    # availability endpoint returns *only* free slots — which is exactly the
    # contract every adapter owes the differ. Courts carry stable uuids, so no
    # name synthesis is needed here.
    class Reservio
      BASE_URL = "https://api.reservio.com/v2".freeze
      PAGE_LIMIT = 200
      MAX_PAGES = 20

      def initialize(club, http:)
        @club = club
        @http = http
        @business_id = club.settings.fetch("business_id")
        @service_id = club.settings.fetch("service_id")
      end

      def fetch(date_range)
        courts = fetch_courts
        # A snapshot must hold each slot once: the differ compares by key, and
        # the slots table has a unique index on it.
        fetch_time_slots(date_range).filter_map { to_slot(_1, courts) }.uniq(&:key)
      end

      private

      def fetch_courts
        body = @http.get_json("#{BASE_URL}/businesses/#{@business_id}/resources")
        body.fetch("data", []).to_h { [_1["id"], _1.dig("attributes", "name")] }
      end

      def fetch_time_slots(date_range)
        url = "#{BASE_URL}/businesses/#{@business_id}/availability/booking-slots"
        params = {
          "filter[from]" => date_range.first.iso8601,
          "filter[to]" => date_range.last.iso8601,
          "filter[serviceId]" => @service_id,
          # Sent because it is the documented contract, not because it works —
          # see the stop condition below for what this endpoint actually does.
          "page[limit]" => PAGE_LIMIT
        }
        records = []

        MAX_PAGES.times do
          body = @http.get_json(url, params)
          records.concat(body.fetch("data", []))

          # `links.next` alone is not a reliable stop condition: this endpoint
          # ignores page[limit]/page[offset], returns the entire result set, and
          # advertises a next link regardless. Following it downloads the same
          # slots again. The declared total is the trustworthy signal.
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

      def to_slot(record, courts)
        attributes = record["attributes"] or return nil
        court_id = record.dig("relationships", "resource", "data", "id") or return nil

        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(court_id),
          # A court added since the last resources call still deserves a
          # notification; an ugly label beats a dropped slot.
          court_label: courts[court_id] || court_id,
          # Reservio timestamps carry their offset, so no zone guessing here.
          starts_at: Time.iso8601(attributes.fetch("start")),
          ends_at: Time.iso8601(attributes.fetch("end")),
          price: @club.settings["price"],
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
