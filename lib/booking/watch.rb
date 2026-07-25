require "set"

module Booking
  # A standing request: "tell me when something opens up at these clubs, on
  # these days, between these hours". Days and hours are always local — a user
  # thinks in Tbilisi wall-clock, so the comparison happens there.
  Watch = Data.define(:id, :user_id, :club_slugs, :weekdays, :from_minute, :to_minute, :active) do
    def self.minute_of_day(value)
      hours, minutes = value.to_s.split(":").map(&:to_i)
      (hours * 60) + minutes.to_i
    end

    def initialize(id:, user_id:, club_slugs:, weekdays:, from_minute:, to_minute:, active: true)
      super(
        id:,
        user_id:,
        club_slugs: club_slugs.map(&:to_s).to_set,
        weekdays: weekdays.map(&:to_i).to_set,
        from_minute:,
        to_minute:,
        active:
      )
    end

    def active? = !!active

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
