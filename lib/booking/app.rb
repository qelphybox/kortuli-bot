module Booking
  # The product runs as three processes built from one image: the Telegram
  # long-poller, the poll loop, and the mini app. They share one SQLite file
  # and nothing else.
  #
  # Splitting them buys independent restarts — deploying a screen no longer
  # interrupts polling — without buying a job queue. ADR-0001 records why the
  # poll loop stays a scheduler rather than becoming queue work.
  module App
    # Each process opens its own connection to the same file. WAL and the busy
    # timeout in DB make that safe across processes as well as threads, because
    # the containers share a kernel and a filesystem.
    def self.repos = Repos.for(DB.connection)
  end
end

require_relative "app/bot"
require_relative "app/poll_loop"
