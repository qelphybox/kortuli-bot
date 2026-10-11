module Booking
  module Repo
    # The latest Forecast, whole: each refresh replaces every hour rather than
    # merging, because a newer run of the model supersedes an older one
    # everywhere it reaches. Written by the poller, read by the web.
    class Forecast
      def initialize(db) = @db = db

      def replace(hours, fetched_at: Clock.now)
        rows = hours.map do |hour|
          {
            starts_at: hour.starts_at, rain_chance: hour.rain_chance, rain_mm: hour.rain_mm,
            code: hour.code, temperature: hour.temperature, day: hour.day, fetched_at:
          }
        end

        @db.transaction do
          @db[:forecast_hours].delete
          @db[:forecast_hours].multi_insert(rows)
        end
      end

      def hours = @db[:forecast_hours].order(:starts_at).map { to_hour(_1) }

      # When the Forecast on file was asked for, or nil before the first time.
      # Not `max`: SQLite hands an aggregate back as text, and only a plain
      # column read comes back as a Time.
      def fetched_at = @db[:forecast_hours].reverse(:fetched_at).get(:fetched_at)

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
