require "telegram/bot"

module Booking
  module Telegram
    # Translates Handlers' replies into Telegram API calls, and nothing else.
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

      def dispatch(bot, update)
        case update
        when ::Telegram::Bot::Types::Message then handle_message(bot, update)
        when ::Telegram::Bot::Types::CallbackQuery then handle_callback(bot, update)
        end
      rescue StandardError => e
        # One malformed update must not take down a long-running process.
        @logger.call("telegram: update failed — #{e.class}: #{e.message}")
      end

      def handle_message(bot, message)
        return if message.text.nil?

        perform(bot, message.chat.id, @handlers.on_message(user_id: message.from.id, text: message.text))
      end

      def handle_callback(bot, query)
        replies = @handlers.on_callback(
          user_id: query.from.id,
          data: query.data,
          message_id: query.message&.message_id
        )
        alert = replies.find { _1.kind == :alert }
        # Always answer, even with nothing to say: otherwise the button keeps
        # spinning on the user's screen.
        bot.api.answer_callback_query(callback_query_id: query.id, text: alert&.text, show_alert: !alert.nil?)
        perform(bot, query.message&.chat&.id, replies.reject { _1.kind == :alert })
      end

      def perform(bot, chat_id, replies)
        return if chat_id.nil?

        replies.each do |reply|
          case reply.kind
          when :send
            bot.api.send_message(chat_id:, text: reply.text, parse_mode: "HTML", reply_markup: markup(reply.keyboard))
          when :edit
            bot.api.edit_message_text(
              chat_id:, message_id: reply.message_id, text: reply.text,
              parse_mode: "HTML", reply_markup: markup(reply.keyboard)
            )
          end
        end
      end

      def markup(keyboard)
        return nil if keyboard.nil? || keyboard.empty?

        rows = keyboard.map do |row|
          row.map { ::Telegram::Bot::Types::InlineKeyboardButton.new(text: _1.text, callback_data: _1.data) }
        end
        ::Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: rows)
      end
    end
  end
end
