module Booking
  module Repo
    # A date's list of clubs, opened: when, for which day, and whether it
    # ended at a club's Book or a shared Game. Written now so the question
    # "which day do people actually play on?" has an answer once it is asked.
    class DayOpens
      def initialize(db) = @db = db

      def record(user_id, date:, at: Clock.now)
        local = Clock.to_local(at)

        @db[:day_opens].insert(
          user_id:, date:, weekday: date.wday, days_ahead: (date - local.to_date).to_i,
          hour: local.hour, opened_at: at
        )
      end

      # A Book tapped, or a Game shared: credited to this person's latest
      # opening of that date, once. Nothing to credit when they never opened
      # it — a Game reached from a link, say.
      def booked(user_id, date:, at: Clock.now) = mark(user_id, date, :booked_at, at)

      def shared(user_id, date:, at: Clock.now) = mark(user_id, date, :shared_at, at)

      private

      def mark(user_id, date, column, at)
        latest = @db[:day_opens].where(user_id:, date:).max(:id) or return

        @db[:day_opens].where(id: latest, column => nil).update(column => at)
      end
    end
  end
end
