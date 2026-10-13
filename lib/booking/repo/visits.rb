module Booking
  module Repo
    # A Visit per person per local date: enough to say how many people open the
    # app, how many are new and how many come back, and nothing about what they
    # looked at.
    class Visits
      def initialize(db) = @db = db

      # Called on every signed-in screen, so it reads before it writes: twenty
      # screens in an evening cost one insert, not twenty write locks taken
      # against the poller. Two requests that both read "not yet" meet at the
      # primary key, which absorbs the second.
      def record(user_id, on:)
        visits = @db[:visits]
        return unless visits.where(user_id:, date: on).empty?

        visits.insert_conflict.insert(user_id:, date: on)
      end
    end
  end
end
