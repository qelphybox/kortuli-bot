module Booking
  module Repo
    # The latest Forecast for each City, whole: each refresh replaces every
    # hour of a city rather than merging, because a newer run of the model
    # supersedes an older one everywhere it reaches. Written by the poller,
    # read by the web.
    class Forecast
      def initialize(db) = @db = db

      # Replaces one city's hours and leaves every other city's alone, so a
      # city missing from an answer keeps the last good Forecast it had.
      def replace(hours, city:, fetched_at: Clock.now)
        rows = hours.map do |hour|
          {
            city:, starts_at: hour.starts_at, rain_chance: hour.rain_chance, rain_mm: hour.rain_mm,
            code: hour.code, temperature: hour.temperature, day: hour.day, fetched_at:
          }
        end

        @db.transaction do
          @db[:forecast_hours].where(city:).delete
          @db[:forecast_hours].multi_insert(rows)
        end
      end

      def hours(city) = @db[:forecast_hours].where(city:).order(:starts_at).map { to_hour(_1) }

      # When the city's Forecast on file was asked for, or nil before the
      # first time. Not `max`: SQLite hands an aggregate back as text, and only
      # a plain column read comes back as a Time.
      def fetched_at(city) = @db[:forecast_hours].where(city:).reverse(:fetched_at).get(:fetched_at)

      # The hours each city has on file, for the dashboard.
      def counts = @db[:forecast_hours].group_and_count(:city).to_h { [_1[:city], _1[:count]] }

      # Drops the cities no enabled club is in any more. Their Forecast would
      # otherwise sit on file, never refreshed and never read, aging on the
      # dashboard as if something were broken.
      def keep_only(cities) = @db[:forecast_hours].exclude(city: cities).delete

      private

      def to_hour(row)
        Weather::Hour.new(
          starts_at: row[:starts_at], rain_chance: row[:rain_chance], rain_mm: row[:rain_mm],
          code: row[:code], temperature: row[:temperature], day: row[:day]
        )
      end
    end
  end
end
