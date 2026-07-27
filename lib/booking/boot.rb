# Shared preamble for the three entrypoints. Kept out of lib/booking.rb so
# that requiring the library never has opinions about environment files or
# stdout buffering — only a process being started does.
begin
  require "dotenv/load" # honours a local .env; deployment gets its environment from Kamal
rescue LoadError
  # Not installed in production, where the gem would have nothing to read.
end

require_relative "../booking"

module Booking
  module Boot
    def self.call(required = Config::REQUIRED)
      missing = Config.missing_environment(required)
      unless missing.empty?
        warn "missing environment: #{missing.join(", ")}"
        warn "see .env.example"
        exit 1
      end

      # The log is the health check, so each line has to reach the journal when
      # it happens rather than when a buffer fills.
      $stdout.sync = true
    end
  end
end
