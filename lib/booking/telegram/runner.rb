require "telegram/bot"

module Booking
  module Telegram
    # Translates one Telegram update into Handlers' vocabulary and the reply
    # back into API calls. The routing choices it makes on its own — is the
    # chat private, is this a fresh message or an edit — are all about *what
    # Handlers gets asked*; the answer, and everything downstream of it, comes
    # from Handlers.
    class Runner
      # Telegram allows exactly one long-poller per token and answers the
      # second one with 409.
      CONFLICT = 409
      RETRY_DELAY = 5

      def initialize(token:, handlers:, owner_id:, logger: nil, client: ::Telegram::Bot::Client, retry_delay: RETRY_DELAY)
        @token = token
        @handlers = handlers
        @owner_id = owner_id
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
        when ::Telegram::Bot::Types::Message then on_message(bot, update)
        when ::Telegram::Bot::Types::CallbackQuery then bury(bot, update)
        end
      rescue StandardError => e
        # One malformed update must not take down a long-running process.
        @logger.call("telegram: update failed — #{e.class}: #{e.message}")
      end

      # Private chats only. Telegram refuses a `web_app` button in a group, so
      # even a plain welcome could only be a dead end there — and a forwarded
      # feedback message would leak the ack back into the same room, which
      # nobody wanted. Groups are not a supported surface.
      def on_message(bot, message)
        return if message.chat.type != PRIVATE

        reply = message.edit_date ? @handlers.on_edit(text: message.text, user_id: message.from.id) \
                                  : @handlers.on_message(text: message.text, user_id: message.from.id)

        deliver(bot, message, reply)
      end

      def deliver(bot, message, reply)
        case reply
        when Handlers::Welcome then say_with_app_button(bot, message.chat.id, reply)
        when Handlers::Prompt then say(bot, message.chat.id, reply.text)
        when Handlers::Feedback then forward_and_ack(bot, message, reply)
        when Handlers::Silence then nil
        end
      end

      def say_with_app_button(bot, chat_id, welcome)
        bot.api.send_message(
          chat_id:,
          text: welcome.text,
          parse_mode: "HTML",
          reply_markup: app_button_markup(welcome.app_url)
        )
      end

      def say(bot, chat_id, text)
        bot.api.send_message(chat_id:, text:, parse_mode: "HTML")
      end

      # Announces the edit before the forward lands, so the owner reads the
      # two as one thing. The forward itself is the payload — the marker is
      # just the label above it.
      def forward_and_ack(bot, message, feedback)
        say(bot, @owner_id, Messages.feedback_edited) if feedback.edited
        forward_to_owner(bot, message)
        say(bot, message.chat.id, feedback.ack_text) if feedback.ack_text
      end

      # Fire-and-forget by design (ADR-0002): a broken forward is logged and
      # the ack still goes out. Rescuing here rather than letting `dispatch`
      # log a generic "update failed" is deliberate — this is not a broken
      # update, it is a known partial delivery mode, and the wording says so.
      def forward_to_owner(bot, message)
        bot.api.forward_message(
          chat_id: @owner_id,
          from_chat_id: message.chat.id,
          message_id: message.message_id
        )
      rescue StandardError => e
        @logger.call("telegram: forward failed — #{e.class}: #{e.message}")
      end

      # Nothing reports back to the bot any more, but the wizard's keyboards are
      # still on screen in chats that predate this. Answering with nothing stops
      # the button spinning forever; it routes nothing, and nothing routes it.
      def bury(bot, query)
        bot.api.answer_callback_query(callback_query_id: query.id)
      end

      # One button, and `web_app` rather than `url` because that opens the app
      # inside Telegram. A plain link would hand the person to a browser, where
      # the signed payload the app authenticates on does not exist.
      def app_button_markup(app_url)
        button = ::Telegram::Bot::Types::InlineKeyboardButton.new(
          text: Messages.open_app,
          web_app: ::Telegram::Bot::Types::WebAppInfo.new(url: app_url)
        )
        ::Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [[button]])
      end
    end
  end
end
