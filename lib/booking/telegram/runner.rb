require "telegram/bot"

module Booking
  module Telegram
    # Translates Handlers' reply into a Telegram API call, and nothing else.
    # All the decisions happened before this class was asked to speak.
    class Runner
      # Telegram allows exactly one long-poller per token and answers the
      # second one with 409.
      CONFLICT = 409
      RETRY_DELAY = 5

      def initialize(token:, handlers:, logger: nil, client: ::Telegram::Bot::Client, retry_delay: RETRY_DELAY)
        @token = token
        @handlers = handlers
        @logger = logger || Booking.default_logger
        @client = client
        @retry_delay = retry_delay
      end

      # A deploy runs two containers at once for a few seconds — the new one is
      # started, and only stopped being waited on once it looks healthy, at
      # which point the old one is told to go. Dying of the resulting 409 would
      # mean the replacement never becomes healthy and the old one is never
      # stopped, so the deploy would wait for something that cannot happen.
      # Waiting the conflict out is what makes the handover terminate.
      def run
        loop do
          begin
            return @client.run(@token) do |bot|
              @logger.call("telegram: listening")
              bot.listen { |update| dispatch(bot, update) }
            end
          rescue ::Telegram::Bot::Exceptions::ResponseError => e
            raise unless e.error_code == CONFLICT

            @logger.call("telegram: token held by another instance (409), retrying in #{@retry_delay}s")
          end

          sleep @retry_delay
        end
      end

      private

      PRIVATE = "private".freeze

      def dispatch(bot, update)
        case update
        when ::Telegram::Bot::Types::Message then greet(bot, update)
        when ::Telegram::Bot::Types::CallbackQuery then bury(bot, update)
        end
      rescue StandardError => e
        # One malformed update must not take down a long-running process.
        @logger.call("telegram: update failed — #{e.class}: #{e.message}")
      end

      # Private chats only. The one button the bot has opens the mini app, and
      # Telegram refuses a web_app button anywhere else — so in a group the
      # greeting could only be a dead end, and saying nothing is the honest
      # version of that. Notifications go to a person, not a room, regardless.
      def greet(bot, message)
        return if message.text.nil? || message.chat.type != PRIVATE

        say(bot, message.chat.id, @handlers.on_message(user_id: message.from.id))
      end

      # Nothing reports back to the bot any more, but the wizard's keyboards are
      # still on screen in chats that predate this. Answering with nothing stops
      # the button spinning forever; it routes nothing, and nothing routes it.
      def bury(bot, query)
        bot.api.answer_callback_query(callback_query_id: query.id)
      end

      def say(bot, chat_id, reply)
        bot.api.send_message(chat_id:, text: reply.text, parse_mode: "HTML", reply_markup: markup(reply.app_url))
      end

      # One button, and `web_app` rather than `url` because that opens the app
      # inside Telegram. A plain link would hand the person to a browser, where
      # the signed payload the app authenticates on does not exist.
      def markup(app_url)
        return nil if app_url.nil?

        button = ::Telegram::Bot::Types::InlineKeyboardButton.new(
          text: Messages.open_app,
          web_app: ::Telegram::Bot::Types::WebAppInfo.new(url: app_url)
        )
        ::Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [[button]])
      end
    end
  end
end
