require "set"

module Booking
  # Turns two snapshots of a club's free slots into the events worth acting on.
  #
  # The naive version of this class — plain set difference — floods users three
  # ways: every night when the club opens a new day, every time the club's site
  # returns a 500, and every time it recovers from having returned a partial
  # answer. Each guard below exists for one of those.
  class Differ
    # No plausible run of cancellations frees more than a handful of slots on a
    # single day inside one tick. A day that gains more than this was opened by
    # the club, or the source is coming back from a bad answer — either way
    # nobody gave anything up, and messaging about it is how a bot gets blocked.
    MAX_FREED_PER_DAY = 8

    Result = Data.define(:became_available, :became_taken, :reason, :suppressed_days) do
      def ok? = reason.nil?
    end

    BAD_POLL = Result.new(became_available: [], became_taken: [], reason: :empty_response, suppressed_days: [])

    def initialize(max_freed_per_day: MAX_FREED_PER_DAY)
      @max_freed_per_day = max_freed_per_day
    end

    # `known_through` is the last local date this club has actually been polled
    # for. It is deliberately not derived from `previous`: the snapshot holds
    # only free slots, so a sold-out day looks identical to a day we never
    # fetched. Callers without that bookkeeping fall back to the snapshot.
    def diff(previous:, current:, known_through: nil)
      # A club never sells out to the last slot in one tick. An empty response
      # after a healthy one is a timeout, a 5xx, or a layout change — not news.
      return BAD_POLL if current.empty? && previous.any?

      previous_keys = previous.map(&:key).to_set
      current_keys = current.map(&:key).to_set
      horizon = known_through || previous.map(&:local_date).max
      days_now = current.map(&:local_date).to_set

      appeared = current.reject { previous_keys.include?(_1.key) }
      vanished = previous.reject { current_keys.include?(_1.key) }

      # A slot beyond the polled horizon is the booking window sliding forward,
      # not a cancellation.
      within_horizon = appeared.select { horizon && _1.local_date <= horizon }
      flooded, genuine = within_horizon.group_by(&:local_date).partition { |_day, slots| slots.size > @max_freed_per_day }

      Result.new(
        became_available: genuine.flat_map(&:last),
        # The mirror image of the horizon rule: a whole day dropping off the
        # back of the window is time passing, not a rush of bookings.
        became_taken: vanished.select { days_now.include?(_1.local_date) },
        reason: nil,
        suppressed_days: flooded.map(&:first).sort
      )
    end
  end
end
