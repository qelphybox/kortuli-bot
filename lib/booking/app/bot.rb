require "telegram/bot"

module Booking
  module App
    # Answers messages over Telegram's long poll, and points the menu button at
    # the mini app. Sends nothing on its own: notifications belong to the poll
    # loop, which is the process that knows when a Slot was Freed.
    #
    # The only one of the three that never touches the database — everything it
    # used to read from there is now read by the app.
    class Bot
      def self.run = new.run

      def initialize(logger: nil)
        @logger = logger || Booking.default_logger
      end

      def run
        @logger.call("boot: telegram")

        # Its own Api instance rather than the listening client's, the way the
        # notifier has one: this happens before the long poll starts and must
        # not wait on it.
        Telegram::Menu.new(api: ::Telegram::Bot::Api.new(Config.telegram_token), logger: @logger)
                      .install(Config.app_url)

        Telegram::Runner.new(
          token: Config.telegram_token,
          handlers: Telegram::Handlers.new(app_url: Config.app_url, owner_id: Config.owner_id),
          owner_id: Config.owner_id,
          logger: @logger
        ).run
      end
    end
  end
end
