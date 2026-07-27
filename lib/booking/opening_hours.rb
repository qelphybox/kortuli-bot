require "date"

module Booking
  # The hours a club offers at all — declared per club rather than observed,
  # because no source reports them reliably: one would report true per-hour
  # statuses, one publishes a weekly schedule, one offers neither. Declaring
  # them uniformly is what lets the Grid draw a row for a club that has nothing
  # free without asking any adapter for anything new.
  #
  # `to` is when the club shuts, so it is not itself bookable: 08:00–24:00
  # means the last hour anyone can start is 23:00.
  OpeningHours = Data.define(:from_hour, :to_hour) do
    DEFAULT = { "from" => "08:00", "to" => "24:00" }.freeze

    def self.parse(config)
      config = DEFAULT if config.nil? || config.empty?

      new(from_hour: hour(config["from"]), to_hour: hour(config["to"]))
    end

    # 24:00 and 00:00 are the same instant and both get written; normalising
    # here means the wrap arithmetic below never has to care which was meant.
    def self.hour(value) = value.to_s.split(":").first.to_i % 24
    private_class_method :hour

    # Hour-of-day numbers in the order the club runs them, which for a club
    # open past midnight climbs to 23 and then starts again at 0.
    def hours
      span = (to_hour - from_hour) % 24
      # from == to is a club that never shuts rather than one open for no time.
      span = 24 if span.zero?

      span.times.map { (from_hour + _1) % 24 }
    end

    # The same sequence as absolute instants for one business day. The day rolls
    # over exactly when the clock does, so a club shutting at 02:00 files its
    # 00:00 and 01:00 on tomorrow — which is where a person looking for them
    # would expect them to be.
    def starts_on(date)
      day = 0
      previous = nil

      hours.map do |hour|
        day += 1 if previous && hour < previous
        previous = hour
        Clock.local_to_utc(format("%s %02d:00", date + day, hour))
      end
    end
  end
end
