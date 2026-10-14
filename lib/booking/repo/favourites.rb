require "set"

module Booking
  module Repo
    # The clubs each person has starred. Slugs rather than ids, like everywhere
    # else a club is named, so a club switched off and back on keeps its stars.
    class Favourites
      def initialize(db) = @db = db

      def for_user(user_id) = @db[:favourites].where(user_id:).select_map(:club_slug).to_set

      # The same stars in the order they were given, first first: the order a
      # day's list leads with them, and the one its hint goes down looking for
      # a free court.
      def ordered(user_id) = @db[:favourites].where(user_id:).order(:created_at, :id).select_map(:club_slug)

      # Starring twice is starring once: the unique pair absorbs the second
      # tap, so a double-tap on a slow connection is not an error page.
      def add(user_id, club_slug)
        @db[:favourites].insert_conflict.insert(user_id:, club_slug: club_slug.to_s, created_at: Clock.now)
      end

      def remove(user_id, club_slug) = @db[:favourites].where(user_id:, club_slug: club_slug.to_s).delete
    end
  end
end
