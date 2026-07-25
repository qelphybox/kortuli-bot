require "date"
require "time"
require "tzinfo"

module Booking
  # Every timestamp inside the system is UTC. Local time exists only at the two
  # boundaries: adapters parsing a club's wall-clock strings on the way in, and
  # message rendering on the way out. Keeping the conversion here stops it
  # leaking into the middle of the pipeline.
  module Clock
    ZONE_NAME = "Asia/Tbilisi".freeze

    def self.zone = @zone ||= TZInfo::Timezone.get(ZONE_NAME)

    # Accepts "2026-08-01 19:00", "2026-08-01T19:00:00" or a Time whose fields
    # are already local wall-clock, and returns the equivalent UTC Time.
    def self.local_to_utc(value)
      parts = value.is_a?(String) ? value.scan(/\d+/).first(6).map(&:to_i) : time_parts(value)
      zone.local_to_utc(Time.utc(*parts))
    end

    def self.to_local(utc_time) = zone.to_local(utc_time.getutc)

    def self.local_date(utc_time) = to_local(utc_time).to_date

    def self.now = Time.now.utc

    def self.time_parts(time)
      [time.year, time.month, time.day, time.hour, time.min, time.sec]
    end
    private_class_method :time_parts
  end
end
