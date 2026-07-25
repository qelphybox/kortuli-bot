require "rufus-scheduler"
require "telegram/bot"

module Booking
  # Boots the single process the whole product runs in: the Telegram loop on the
  # main thread, the poll loop on a scheduler thread, one SQLite file between
  # them.
  class App
    def self.run = new.run

    def initialize(logger: nil)
      @logger = logger || Booking.default_logger
      @repos = Repos.for(DB.connection)
    end

    def run
      clubs = ClubRegistry.sync_from_config!(@repos.clubs)
      @logger.call("boot: #{clubs.count(&:enabled?)} club(s) enabled, horizon #{Config.horizon_days}d, every #{Config.poll_interval}")

      start_polling
      start_telegram
    end

    private

    def start_polling
      poller = Poller.new(repos: @repos, notifier: build_notifier, http: Http.new, logger: @logger)
      scheduler = Rufus::Scheduler.new

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

    def start_telegram
      Telegram::Runner.new(
        token: Config.telegram_token,
        handlers: Telegram::Handlers.new(repos: @repos),
        logger: @logger
      ).run
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
