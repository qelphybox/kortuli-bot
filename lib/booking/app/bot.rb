module Booking
  module App
    # Answers commands over Telegram's long poll. Sends nothing on its own:
    # notifications belong to the poll loop, which is the process that knows
    # when a Slot was Freed.
    class Bot
      def self.run = new.run

      def initialize(logger: nil)
        @logger = logger || Booking.default_logger
        @repos = App.repos
      end

      def run
        @logger.call("boot: telegram")

        Telegram::Runner.new(
          token: Config.telegram_token,
          handlers: Telegram::Handlers.new(repos: @repos),
          logger: @logger
        ).run
      end
    end
  end
end
