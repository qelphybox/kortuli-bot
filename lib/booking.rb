module Booking
  Error = Class.new(StandardError)

  # There is no alerting, so this log *is* the health check — which makes one
  # timestamp format across every line the difference between grepping journald
  # and squinting at it. Injectable everywhere so tests can read what was said.
  def self.default_logger = ->(line) { $stdout.puts("#{Clock.now.iso8601} #{line}") }
end

require_relative "booking/config"
require_relative "booking/clock"
require_relative "booking/court_name"
require_relative "booking/slot"
require_relative "booking/watch"
require_relative "booking/opening_hours"
require_relative "booking/club"
require_relative "booking/grid"
require_relative "booking/rundown"
require_relative "booking/differ"
require_relative "booking/matcher"
require_relative "booking/schema"
require_relative "booking/db"
require_relative "booking/repo/clubs"
require_relative "booking/repo/slots"
require_relative "booking/repo/watches"
require_relative "booking/repo/notifications"
require_relative "booking/repo/events"
require_relative "booking/adapters"
require_relative "booking/http"
require_relative "booking/repos"
require_relative "booking/messages"
require_relative "booking/notifier"
require_relative "booking/poller"
require_relative "booking/telegram/handlers"
require_relative "booking/telegram/menu"
require_relative "booking/telegram/transport"
require_relative "booking/telegram/runner"
require_relative "booking/club_registry"
require_relative "booking/web/init_data"
require_relative "booking/web/session"
require_relative "booking/web/submission"
require_relative "booking/web/tapped_hour"
require_relative "booking/web/hour_span"
require_relative "booking/web/app"
require_relative "booking/app"
