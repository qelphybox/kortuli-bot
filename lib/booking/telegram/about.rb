require "telegram/bot"

module Booking
  module Telegram
    # What Telegram says about the bot before anybody opens it: the
    # description in the empty chat, the short one on its profile, and the
    # command menu. The texts live in Messages, so they change with the code.
    #
    # Set on boot, like the menu button, but only where Telegram's copy
    # differs: the bot restarts on every deploy, and an unchanged text is one
    # call to read it rather than a write. Each part is set on its own, so one
    # refusal leaves the others in place.
    class About
      def initialize(api:, logger: nil)
        @api = api
        @logger = logger || Booking.default_logger
      end

      def install
        sync("description", Messages.bot_description, read: -> { @api.get_my_description.description }) do |text|
          @api.set_my_description(description: text)
        end
        sync("short description", Messages.bot_short_description,
             read: -> { @api.get_my_short_description.short_description }) do |text|
          @api.set_my_short_description(short_description: text)
        end
        sync("commands", commands, read: -> { @api.get_my_commands.map { [_1.command, _1.description] } }) do |list|
          @api.set_my_commands(commands: list.map { ::Telegram::Bot::Types::BotCommand.new(command: _1, description: _2) })
        end
      end

      private

      def commands = Messages.bot_commands.to_a

      def sync(what, wanted, read:)
        if read.call == wanted
          @logger.call("telegram: #{what} unchanged")
        else
          yield wanted
          @logger.call("telegram: #{what} set")
        end
      rescue StandardError => e
        # A bot with yesterday's description still answers; one that refuses
        # to start because Telegram was briefly unreachable does not.
        @logger.call("telegram: could not set the #{what} — #{e.class}: #{e.message}")
      end
    end
  end
end
