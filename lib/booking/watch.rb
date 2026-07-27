require "date"
require "set"

module Booking
  # A request: "tell me when something opens up at these clubs, on these days,
  # between these hours". Days and hours are always local — a user thinks in
  # Tbilisi wall-clock, so the comparison happens there.
  #
  # A Dated watch is this same record with `date` set: the weekdays are that
  # date's weekday and the hours are one hour. Everything downstream treats the
  # two alike, which is the point of storing them alike.
  Watch = Data.define(:id, :user_id, :club_slugs, :weekdays, :from_minute, :to_minute, :active, :date) do
    def self.minute_of_day(value)
      hours, minutes = value.to_s.split(":").map(&:to_i)
      (hours * 60) + minutes.to_i
    end

    def initialize(id:, user_id:, club_slugs:, weekdays:, from_minute:, to_minute:, active: true, date: nil)
      super(
        id:,
        user_id:,
        club_slugs: club_slugs.map(&:to_s).to_set,
        weekdays: weekdays.map(&:to_i).to_set,
        from_minute:,
        to_minute:,
        active:,
        date: date && Date.iso8601(date.to_s)
      )
    end

    def active? = !!active

    def dated? = !date.nil?

    # Nothing reaps an expired Dated watch: the Matcher already discards slots
    # that have started, so it stops matching on its own. This is for the
    # screen, which should not carry a request that can no longer come true.
    #
    # Measured from the *start* of the hour rather than its end, for exactly
    # that reason — a Dated watch covers a single hour, and once that hour has
    # begun the only slot it could ever match has already started.
    #
    # Counted from midnight rather than by formatting the minute as a time,
    # because a watch on the last hour of the day runs to 24:00 and nothing
    # will parse that.
    def expired?(now = Clock.now)
      return false unless dated?

      (Clock.local_to_utc("#{date} 00:00") + (from_minute * 60)) <= now
    end

    def covers?(slot)
      return false unless club_slugs.include?(slot.club_slug)

      local = slot.local_starts_at
      return false unless weekdays.include?(local.wday)

      starts = (local.hour * 60) + local.min
      # Measuring the end from the duration rather than from the local clock
      # keeps a slot that crosses midnight out of an early-morning window.
      starts >= from_minute && (starts + slot.duration_minutes) <= to_minute
    end
  end
end
