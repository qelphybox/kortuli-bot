require "json"

module Booking
  module Repo
    class Watches
      def initialize(db) = @db = db

      # `date` is what makes the watch Dated; leaving it out makes a Standing
      # one. One path, because two ways to write this table is how a chat
      # wizard and a web form drift apart.
      def create(user_id:, club_slugs:, weekdays:, from_minute:, to_minute:, date: nil)
        id = @db[:watches].insert(
          user_id:,
          club_slugs: JSON.generate(club_slugs.to_a.map(&:to_s)),
          weekdays: JSON.generate(weekdays.to_a.map(&:to_i).sort),
          from_minute:,
          to_minute:,
          active: true,
          date:,
          created_at: Clock.now
        )
        find(id)
      end

      def find(id) = (row = @db[:watches][id:]) && to_watch(row)

      def for_user(user_id) = @db[:watches].where(user_id:).order(:id).map { to_watch(_1) }

      def active = @db[:watches].where(active: true).order(:id).map { to_watch(_1) }

      def set_active(id, active) = @db[:watches].where(id:).update(active:)

      def delete(id) = @db[:watches].where(id:).delete

      def to_watch(row)
        Watch.new(
          id: row[:id],
          user_id: row[:user_id],
          club_slugs: JSON.parse(row[:club_slugs]),
          weekdays: JSON.parse(row[:weekdays]),
          from_minute: row[:from_minute],
          to_minute: row[:to_minute],
          active: row[:active],
          date: row[:date]
        )
      end
      private :to_watch
    end
  end
end
