module Booking
  module Adapters
    # Raised for anything that makes a club's data unreadable this tick: a
    # timeout, a 5xx, a redesigned page. The poller treats them all the same —
    # skip the tick, keep the snapshot, say so in the log.
    SourceUnavailable = Class.new(Error)

    REGISTRY = { "reservio" => "Reservio", "kustba" => "Kustba", "gymbreeze" => "Gymbreeze", "bookandgo" => "Bookandgo" }.freeze

    def self.build(club, http:)
      name = REGISTRY[club.adapter] or raise Error, "no adapter registered for #{club.adapter.inspect}"

      const_get(name).new(club, http:)
    end
  end
end

require_relative "adapters/reservio"
require_relative "adapters/kustba"
require_relative "adapters/gymbreeze"
require_relative "adapters/bookandgo"
