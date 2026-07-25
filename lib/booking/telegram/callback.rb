module Booking
  module Telegram
    # Telegram gives a button 64 bytes of state and nothing else, so every
    # button packs "who owns this, what it does, what it does it to" into one
    # string. Reading and writing that convention in a single place is what
    # keeps a new button from inventing a second one — the routing in Handlers
    # and the step machine in Wizard both take these apart, and before this type
    # they took them apart differently.
    Callback = Data.define(:prefix, :action, :value) do
      SEPARATOR = ":".freeze

      def self.parse(data)
        prefix, action, value = data.to_s.split(SEPARATOR, 3)
        new(prefix:, action:, value:)
      end

      def self.build(prefix, action, value = nil) = new(prefix:, action:, value:).to_s

      # A valueless button ("next", "cancel") must not trail a separator, or it
      # would not survive a parse/build round trip.
      def to_s = [prefix, action, value].compact.join(SEPARATOR)
    end
  end
end
