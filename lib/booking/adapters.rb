module Booking
  module Adapters
    # Raised for anything that makes a club's data unreadable this tick: a
    # timeout, a 5xx, a redesigned page. The poller treats them all the same —
    # skip the tick, keep the snapshot, say so in the log.
    SourceUnavailable = Class.new(Error)
    # A source that wants a login and did not like ours. Only an adapter that
    # holds a session cares about the difference; the poller does not.
    Unauthorized = Class.new(SourceUnavailable)

    REGISTRY = {
      "reservio" => "Reservio",
      "kustba" => "Kustba",
      "gymbreeze" => "Gymbreeze",
      "bookandgo" => "Bookandgo",
      "padelhub" => "Padelhub",
      "padelacademy" => "Padelacademy",
      "lemans" => "Lemans",
      "bookingpress" => "Bookingpress",
      "aiapadel" => "Aiapadel",
      "higgs" => "Higgs",
      "padelgldani" => "Padelgldani",
      "matchpoint" => "Matchpoint"
    }.freeze

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
require_relative "adapters/padelhub"
require_relative "adapters/padelacademy"
require_relative "adapters/lemans"
require_relative "adapters/bookingpress"
require_relative "adapters/aiapadel"
require_relative "adapters/higgs"
require_relative "adapters/padelgldani"
require_relative "adapters/matchpoint"
