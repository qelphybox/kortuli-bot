require "time"

module Booking
  module Adapters
    # PROTOTYPE — throwaway. Drive it with `rake prototype:kustba`.
    #
    # THE QUESTION
    # ------------
    # Kus Tba Padel runs WordPress with the `turtle-booking` plugin, which
    # publishes an unauthenticated REST API. Two things are unsettled:
    #
    #   1. Can a snapshot be pulled without a session, a nonce or a browser?
    #   2. At what granularity should a Slot exist here — one per *court-hour*
    #      (matching Reservio, but costing one request per hour of every date)
    #      or one per *hour* (one request per date, court unknown until the
    #      user opens the link)?
    #
    # (2) is the real question. The hour feed already says `available` / `full`
    # / `inactive` per hour, so the cheap answer may be good enough — but it
    # collapses "court 3 freed up while 1 and 2 were already free" into no
    # event at all. Whether that matters is what pressing [g] here is for.
    #
    # THE ANSWER (2026-07-26)
    # -----------------------
    # (1) Yes — plain GET, no auth of any kind.
    # (2) Per hour. Measured over the club's own 7-day window: 84 slots in 7
    #     requests and 4s, against 773 slots in 110 requests and 54s. Hammering
    #     somebody's shared WordPress 110 times every four minutes is not worth
    #     court names, and the event that matters — a sold-out hour reopening —
    #     survives the collapse. Shipped in adapters/kustba.rb.
    #
    # Everything above `snapshot` is pure and lifts into the real adapter; the
    # TUI in bin/prototype-kustba does not.
    class KustbaPrototype
      BASE_URL = "https://kustbapadel.ge/wp-json/turtle-booking/v1".freeze
      BOOKING_URL = "https://kustbapadel.ge/book/".freeze
      # The widget's own `max_days`. The API answers happily past it, but every
      # hour out there reads `available` because nobody can book it yet — a
      # wall of slots that never transitions. Honour the club's horizon.
      HORIZON_DAYS = 7
      # `full` = every court booked, `inactive` = past or closed. Only the
      # third value means a court is actually free.
      AVAILABLE = "available".freeze

      Cost = Struct.new(:requests, :seconds)

      def initialize(http:, club_slug: "kus-tba-padel")
        @http = http
        @club_slug = club_slug
        @requests = 0
      end

      attr_reader :requests

      def dates(from: Date.today, days: HORIZON_DAYS) = (from...(from + days)).to_a

      # granularity: :hour (1 request per date) or :court (1 + one per open hour)
      def snapshot(dates, granularity:)
        started = Time.now
        before = @requests
        slots = dates.flat_map { day_slots(_1, granularity) }.uniq(&:key)

        [slots, Cost.new(@requests - before, Time.now - started)]
      end

      def hours(date)
        @requests += 1
        @http.get_json("#{BASE_URL}/available-slots", { "date" => date.to_s })
      end

      def courts(date, time)
        @requests += 1
        @http.get_json(
          "#{BASE_URL}/available-courts",
          # Without this the titles come back in Georgian; the bot speaks English.
          { "date" => date.to_s, "time" => time, "wpml_language" => "en" }
        )
      end

      # --- pure below this line -------------------------------------------

      # The hour feed runs 08:00 … 23:00, 00:00, 01:00 and the last two belong
      # to the *next* calendar day — the backend adds the day itself and wants
      # the logical date back. Detect the rollover by the clock going
      # backwards rather than by hardcoding an opening hour, so a club that
      # changes its schedule does not silently file slots on the wrong day.
      def self.starts_at(date, times)
        day = 0
        previous = nil

        times.map do |time|
          hour = time.split(":").first.to_i
          day += 1 if previous && hour < previous
          previous = hour
          Clock.local_to_utc("#{date + day} #{time}")
        end
      end

      def self.free_hours(payload) = payload.select { _1["status"] == AVAILABLE }.map { _1["time"] }

      def self.free_courts(payload) = payload.select { _1["status"] == "active" }

      private

      def day_slots(date, granularity)
        payload = hours(date)
        times = payload.map { _1["time"] }
        starts = self.class.starts_at(date, times).each_with_index.to_h { [times[_2], _1] }
        open_times = self.class.free_hours(payload)

        return open_times.map { hour_slot(_1, starts.fetch(_1)) } if granularity == :hour

        open_times.flat_map do |time|
          self.class.free_courts(courts(date, time)).map { court_slot(_1, starts.fetch(time)) }
        end
      end

      def hour_slot(time, starts_at)
        # One synthetic slot standing in for "somewhere in this hour there is a
        # court". The key must still be stable, hence a fixed court_ref.
        Slot.new(
          club_slug: @club_slug,
          court_ref: "any",
          court_label: "Any court",
          starts_at:,
          ends_at: starts_at + 3600,
          price: nil,
          deeplink: BOOKING_URL
        )
      end

      def court_slot(court, starts_at)
        Slot.new(
          club_slug: @club_slug,
          # Numeric post ids, stable across the feed — no name synthesis needed.
          court_ref: court.fetch("id").to_s,
          court_label: court.fetch("title"),
          starts_at:,
          ends_at: starts_at + 3600,
          price: "#{court["price"]} GEL",
          deeplink: BOOKING_URL
        )
      end
    end
  end
end
