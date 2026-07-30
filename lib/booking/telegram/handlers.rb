module Booking
  module Telegram
    # Decides what the bot should say and do about one incoming update.
    # Deliberately returns a value object instead of calling the API: the whole
    # conversation is then exercisable without a network, a token, or a stub of
    # Telegram's client. The Runner translates the value into API calls.
    #
    # The bot has two surfaces (see ADR-0002):
    #
    #   * commands — `/start` (welcome), `/start feedback` and `/feedback`
    #     (feedback prompt). These answer everyone, including the owner.
    #   * everything else — forwarded to the owner as feedback with a canned
    #     ack. Skipped when the sender *is* the owner, so a self-forward does
    #     not clutter their own chat with the bot.
    class Handlers
      # A greeting on `/start`. Carries the app URL so the Runner can attach an
      # inline button that opens the mini app inside Telegram.
      Welcome = Data.define(:text, :app_url)

      # The bot's reply to `/feedback` and `/start feedback`. Plain text — the
      # next thing the user sends is the feedback itself.
      Prompt = Data.define(:text)

      # The Runner is asked to `forwardMessage` this update to the owner and,
      # unless it is an edit, send the ack back to the sender.
      Feedback = Data.define(:ack_text, :edited)

      # The bot has nothing to say and nothing to forward. Owner's own
      # non-command chatter, mostly.
      Silence = Data.define

      # Matches `/start` optionally followed by any payload. Telegram delivers
      # the button's `start=feedback` as `/start feedback`.
      START = %r{\A/start(?:@\w+)?(?:\s+(?<payload>\S+))?\s*\z}
      FEEDBACK_COMMAND = %r{\A/feedback(?:@\w+)?\s*\z}
      FEEDBACK_PAYLOAD = "feedback".freeze

      def initialize(app_url:, owner_id:)
        @app_url = app_url
        @owner_id = owner_id
      end

      def on_message(text:, user_id:)
        command = classify(text)

        case command
        when :welcome then Welcome.new(text: Messages.welcome, app_url: @app_url)
        when :prompt then Prompt.new(text: Messages.feedback_prompt)
        else forward_or_silence(user_id, edited: false)
        end
      end

      # Edited messages get re-forwarded with a marker prefix but no fresh ack:
      # the sender already heard "got it" on the original, and a second one
      # after fixing a typo reads as "you weren't heard, say it again". A
      # command being edited (`/start` corrected to `/start`) is not feedback
      # — silence rather than forwarding the edit.
      def on_edit(text:, user_id:)
        return Silence.new if classify(text) != :feedback

        forward_or_silence(user_id, edited: true)
      end

      private

      def classify(text)
        return :feedback unless text.is_a?(String)

        if (m = START.match(text))
          m[:payload] == FEEDBACK_PAYLOAD ? :prompt : :welcome
        elsif FEEDBACK_COMMAND.match?(text)
          :prompt
        else
          :feedback
        end
      end

      def forward_or_silence(user_id, edited:)
        return Silence.new if user_id == @owner_id

        Feedback.new(ack_text: edited ? nil : Messages.feedback_ack, edited:)
      end
    end
  end
end
