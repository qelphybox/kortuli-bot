module Booking
  # Fans freed slots out across the watches that asked for them. Deliberately
  # thin: the judgement lives in Watch#covers?, this only decides who hears.
  class Matcher
    Candidate = Data.define(:watch, :slot)

    def match(events:, watches:, now: Clock.now)
      live = watches.select(&:active?)

      # A slot that has already started cannot be played, however free it is.
      events.reject { _1.starts_at <= now }.flat_map do |freed|
        live.select { _1.covers?(freed) }.map { Candidate.new(watch: _1, slot: freed) }
      end
    end
  end
end
