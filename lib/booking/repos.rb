module Booking
  # One handle for the tables, so callers take a single collaborator instead
  # of a constructor argument per table.
  Repos = Data.define(:clubs, :slots, :events, :watches, :notifications, :favourites, :polls, :forecast, :visits, :preferences) do
    def self.for(db)
      new(
        clubs: Repo::Clubs.new(db),
        slots: Repo::Slots.new(db),
        events: Repo::Events.new(db),
        watches: Repo::Watches.new(db),
        notifications: Repo::Notifications.new(db),
        favourites: Repo::Favourites.new(db),
        polls: Repo::Polls.new(db),
        forecast: Repo::Forecast.new(db),
        visits: Repo::Visits.new(db),
        preferences: Repo::Preferences.new(db)
      )
    end
  end
end
