require "json"

module Booking
  module Repo
    class Clubs
      def initialize(db) = @db = db

      def enabled = @db[:clubs].where(enabled: true).order(:slug).map { to_club(_1) }

      def all = @db[:clubs].order(:slug).map { to_club(_1) }

      def find(slug) = (row = @db[:clubs][slug: slug.to_s]) && to_club(row)

      def upsert(slug:, name:, adapter:, settings: {}, poll_interval_seconds: DEFAULT_POLL_INTERVAL_SECONDS, enabled: true)
        attrs = {
          name:, adapter:,
          settings: JSON.generate(settings),
          poll_interval_seconds:, enabled:
        }
        updated = @db[:clubs].where(slug: slug.to_s).update(attrs)
        @db[:clubs].insert(**attrs, slug: slug.to_s, created_at: Clock.now) if updated.zero?
        find(slug)
      end

      # Records how far along the sliding window this club has been polled.
      # Only ever moves forward — a short fetch must not retract the horizon and
      # re-arm the "new day" suppression for days we already know.
      def observed_through!(slug, date)
        club = find(slug)
        return if club&.observed_through && club.observed_through >= date

        @db[:clubs].where(slug: slug.to_s).update(observed_through: date)
      end

      def to_club(row)
        Club.new(
          slug: row[:slug],
          name: row[:name],
          adapter: row[:adapter],
          settings: row[:settings],
          poll_interval_seconds: row[:poll_interval_seconds],
          enabled: row[:enabled],
          observed_through: row[:observed_through]
        )
      end
      private :to_club
    end
  end
end
