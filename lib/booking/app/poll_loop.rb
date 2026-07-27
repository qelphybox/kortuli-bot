require "rufus-scheduler"
require "telegram/bot"

module Booking
  module App
    # Mirrors club configuration into the database, then walks every Club on a
    # schedule and sends what the walk turned up. The only process that writes
    # Slots, and the only one that speaks first.
    class PollLoop
      def self.run = new.run

      def initialize(logger: nil)
        @logger = logger || Booking.default_logger
        @repos = App.repos
      end

      def run
        # This process owns club configuration because it owns club state. The
        # other two only read what it wrote.
        clubs = ClubRegistry.sync_from_config!(@repos.clubs)
        @logger.call("boot: #{clubs.count(&:enabled?)} club(s) enabled, horizon #{Config.horizon_days}d, every #{Config.poll_interval}")

        scheduler = Rufus::Scheduler.new
        schedule(scheduler)
        # Nothing else holds this process open now that Telegram's loop lives
        # elsewhere.
        scheduler.join
      end

      private

      def schedule(scheduler)
        poller = Poller.new(repos: @repos, notifier: build_notifier, http: Http.new, logger: @logger)

        # overlap: false keeps a slow tick from stacking on top of itself, which
        # is the fastest route to hammering a club that has started timing out.
        scheduler.every(Config.poll_interval, first: :now, overlap: false) do
          # rufus has no jitter of its own, and firing on the exact same second
          # every time is the pattern a rate limiter notices first.
          sleep(rand(Config.poll_jitter)) if Config.poll_jitter.positive?
          poller.tick
        rescue StandardError => e
          @logger.call("poll: tick crashed — #{e.class}: #{e.message}")
        end
      end

      def build_notifier
        Notifier.new(
          notifications: @repos.notifications,
          transport: Telegram::Transport.new(::Telegram::Bot::Api.new(Config.telegram_token)),
          clubs: @repos.clubs.all.to_h { [_1.slug, _1.name] },
          logger: @logger
        )
      end
    end
  end
end
