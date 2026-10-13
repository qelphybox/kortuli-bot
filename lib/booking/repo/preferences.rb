module Booking
  module Repo
    # What each person picked and wants kept between visits — so far only the
    # City they are looking at. Per person rather than per device, like the
    # Favourites: the same Telegram id on a phone and a laptop sees the same
    # city.
    class Preferences
      def initialize(db) = @db = db

      # Nil until the person has picked one.
      def city(user_id) = @db[:preferences].where(user_id:).get(:city)

      # Picking again overwrites: the row is the latest choice, not a history.
      def choose_city(user_id, city)
        @db[:preferences].insert_conflict(:replace).insert(user_id:, city: city.to_s, updated_at: Clock.now)
      end
    end
  end
end
