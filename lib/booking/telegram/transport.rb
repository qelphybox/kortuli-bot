module Booking
  module Telegram
    # The notifier's way out to Telegram. Built on its own Api instance rather
    # than the listening client's, so the poll thread and the bot thread never
    # share an object.
    class Transport
      def initialize(api) = @api = api

      def send_message(chat_id:, text:)
        @api.send_message(chat_id:, text:, parse_mode: "HTML")
      end
    end
  end
end
