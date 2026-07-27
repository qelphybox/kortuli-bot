require "telegram/bot"

module Booking
  module Telegram
    # Points Telegram's menu button at the mini app.
    #
    # Set on every boot rather than once by hand: the call is idempotent, and
    # the alternative is an operator step nobody remembers after a token move.
    # Registering the app's URL with @BotFather stays manual — that one cannot
    # be done over the API.
    class Menu
      def initialize(api:, logger: nil)
        @api = api
        @logger = logger || Booking.default_logger
      end

      # No chat_id, so this is the default for every private chat: the button is
      # there before anybody has said a word to the bot, which is the whole
      # reason for setting it from here rather than answering /start with a link.
      def install(url)
        @api.set_chat_menu_button(
          menu_button: ::Telegram::Bot::Types::MenuButtonWebApp.new(
            text: Messages.open_app,
            web_app: ::Telegram::Bot::Types::WebAppInfo.new(url:)
          )
        )
        @logger.call("telegram: menu button -> #{url}")
      rescue StandardError => e
        # A bot that answers messages without a menu button is worth more than
        # one that refuses to start because Telegram was briefly unreachable.
        # The greeting still carries a button of its own.
        @logger.call("telegram: could not set the menu button — #{e.class}: #{e.message}")
      end
    end
  end
end
