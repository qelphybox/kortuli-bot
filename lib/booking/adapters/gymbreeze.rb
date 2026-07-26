require "time"

module Booking
  module Adapters
    # GymBreeze runs its own Django backend behind a Next.js site, and its
    # availability endpoint needs no authentication — plain GET, no nonce, no
    # cookie. It answers the adapter contract almost exactly: only free slots,
    # each with a full ISO8601 start and end carrying the club's offset, so
    # nothing here has to guess a timezone or roll a day over at midnight the
    # way `Kustba` does.
    #
    # A slot stands for an hour rather than a court, because the API no longer
    # offers the choice — passing `court_id` answers "no longer supported, use
    # location_id". So an hour is free while *any* court is, and a cancellation
    # raises an event only when the last booked court of a sold-out hour frees
    # up. At Ninoshvili, with eight courts, that is a rare and therefore
    # informative event.
    #
    # One club per location: these are two different parts of Tbilisi, and a
    # watcher who wants Radio City is not served by hearing about Ninoshvili.
    class Gymbreeze
      BASE_URL = "https://backend.whiteriver-4e0c4713.germanywestcentral.azurecontainerapps.io/api/v1".freeze
      # Dates the club's own booking widget offers, counting today. The API
      # answers well past this; see `fetch`.
      DEFAULT_MAX_DAYS = 8
      # There is no court to name at this granularity. A constant ref keeps the
      # slot key stable; the label is what the notification prints.
      COURT_REF = "any".freeze
      COURT_LABEL = "A court".freeze

      def initialize(club, http:)
        @club = club
        @http = http
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @location_id = club.settings.fetch("location_id")
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range)
        # Past the club's booking window the API keeps answering, and every hour
        # out there comes back free because nobody can reserve it yet. Those
        # slots would never transition, so never ask for them.
        date_range.to_a.first(@max_days).flat_map { day_slots(_1) }.uniq(&:key)
      end

      private

      def day_slots(date)
        url = "#{@base_url}/bookings/availability/"
        payload = @http.get_json(url, { "location_id" => @location_id, "date" => date.to_s })
        slots = payload["available_slots"] if payload.is_a?(Hash)
        # The endpoint reports its own refusals as a 200 with an `error` key —
        # a renamed parameter reads that way. Parsed literally it would look
        # like every court in the club being booked at once.
        raise SourceUnavailable, "#{url}: no available_slots in #{payload.inspect[0, 200]}" unless slots.is_a?(Array)

        slots.map { to_slot(_1) }
      end

      def to_slot(entry)
        Slot.new(
          club_slug: @club.slug,
          court_ref: COURT_REF,
          court_label: COURT_LABEL,
          # Timestamps arrive with their offset, and the hours after midnight
          # are already dated to the day they belong to.
          starts_at: Time.iso8601(entry.fetch("start")),
          ends_at: Time.iso8601(entry.fetch("end")),
          price: @club.settings["price"],
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
