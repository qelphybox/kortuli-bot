module Booking
  module Telegram
    # Decides what the bot should say — which, now that a Watch is made in the
    # app, is one thing. Deliberately returns a Reply instead of calling the
    # API: the whole conversation is then exercisable without a network, a
    # token, or a stub of Telegram's client.
    class Handlers
      # A Reply carries a URL where the wizard's buttons carried callback data.
      # The one button left opens the mini app, so nothing comes back here to be
      # routed and there is no callback layer under this any more.
      Reply = Data.define(:text, :app_url)

      def initialize(app_url:)
        @app_url = app_url
      end

      # Every message gets the same answer, whatever it said and whoever sent
      # it. The bot stopped being a form: there is nothing left to ask it that
      # the app does not answer better, so a command surface would only be a
      # way to get it wrong. The runner passes `user_id:` in from the update;
      # kept on the signature so a single-user gate could come back one day
      # without changing the caller.
      def on_message(user_id:)
        _ = user_id
        Reply.new(text: Messages.welcome, app_url: @app_url)
      end
    end
  end
end
