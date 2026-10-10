module Booking
  # One handle for the six tables, so callers take a single collaborator
  # instead of six constructor arguments.
  Repos = Data.define(:clubs, :slots, :events, :watches, :notifications, :favourites) do
    def self.for(db)
      new(
        clubs: Repo::Clubs.new(db),
        slots: Repo::Slots.new(db),
        events: Repo::Events.new(db),
        watches: Repo::Watches.new(db),
        notifications: Repo::Notifications.new(db),
        favourites: Repo::Favourites.new(db)
      )
    end
  end
end
