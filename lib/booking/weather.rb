module Booking
  # The Forecast: what the sky over Tbilisi is expected to do, hour by hour.
  # Asked for because the first thing anybody checks before booking an open
  # court is whether it will rain on it — and a court under a roof is only
  # worth the detour on a day when it will.
  #
  # From Open-Meteo: free, keyless, hourly, and sixteen days out, which covers
  # the Booking horizon twice over. One point for the whole city — the clubs
  # sit within a few kilometres of each other, which is about the model's own
  # resolution, so asking per club would buy ten copies of one answer.
  module Weather
    URL = "https://api.open-meteo.com/v1/forecast".freeze
    LATITUDE = 41.7151
    LONGITUDE = 44.8271
    # Open-Meteo refuses anything further out.
    MAX_DAYS = 16

    # Likely enough that an open court is a bad bet.
    WET_CHANCE = 50
    # Worth a mention, not worth changing plans over.
    DAMP_CHANCE = 20
    # Millimetres stand in only where the chance is missing: they come from a
    # single model run, which drizzles a tenth of a millimetre into hours the
    # ensemble gives one chance in ten — "🌦 8%" helps nobody.
    WET_MM = 0.5
    DAMP_MM = 0.1

    # WMO weather codes, as Open-Meteo reports them.
    STORM_CODES = [95, 96, 99].freeze
    SNOW_CODES = [71, 73, 75, 77, 85, 86].freeze
    FOG_CODES = [45, 48].freeze

    # One hour of the Forecast, starting at `starts_at` — the same instant a
    # Cell starts at, so the two meet on a key.
    Hour = Data.define(:starts_at, :rain_chance, :rain_mm, :code, :temperature, :day) do
      # A thunderstorm stops play whatever the odds of rain.
      def wet? = storm? || likely?(WET_CHANCE, WET_MM)

      def damp? = !wet? && likely?(DAMP_CHANCE, DAMP_MM)

      def storm? = STORM_CODES.include?(code)

      def snow? = SNOW_CODES.include?(code)

      def icon
        if storm? then "⛈"
        elsif wet? then snow? ? "🌨" : "🌧"
        elsif damp? then "🌦"
        elsif FOG_CODES.include?(code) then "🌫"
        elsif code.to_i <= 1 then day ? "☀️" : "🌙"
        elsif code == 2 then day ? "⛅" : "☁️"
        else "☁️"
        end
      end

      private

      def likely?(chance, mm) = rain_chance ? rain_chance >= chance : rain_mm.to_f >= mm
    end

    # The hours of one page — a date's columns — read together, which is how
    # a person reads them: "will it rain this evening?", not hour by hour.
    Outlook = Data.define(:hours) do
      def wet? = hours.any?(&:wet?)

      def damp? = !wet? && hours.any?(&:damp?)

      # Consecutive wet hours folded into [starts_at, ends_at] stretches.
      def wet_runs = runs(&:wet?)

      def damp_runs = runs(&:damp?)

      def temperatures = hours.map(&:temperature).compact.minmax

      # The one mark a date's row has room for, and only when there is
      # something to warn about.
      def icon
        if wet? then hours.find(&:wet?).icon
        elsif damp? then "🌦"
        end
      end

      private

      def runs(&)
        hours.select(&).chunk_while { |a, b| b.starts_at - a.starts_at == 3600 }
             .map { [_1.first.starts_at, _1.last.starts_at + 3600] }
      end
    end

    module_function

    # Days counted from today in GMT, which is the timezone asked for, plus
    # two: one because a Tbilisi date starts four hours before GMT's does, and
    # one for the clubs whose evening runs past midnight.
    def fetch(http, days:)
      parse(
        http.get_json(URL, {
                        latitude: LATITUDE,
                        longitude: LONGITUDE,
                        hourly: "temperature_2m,precipitation_probability,precipitation,weather_code,is_day",
                        timezone: "GMT",
                        timeformat: "unixtime",
                        forecast_days: [days + 2, MAX_DAYS].min
                      })
      )
    end

    # Rain and its chance are reported for the hour *before* each timestamp —
    # the 19:00 row is what fell between 18:00 and 19:00 — so every row
    # becomes the Hour that ends at it. Read the other way round, a shower at
    # six would be pinned on the court booked for seven.
    def parse(body)
      hourly = body.fetch("hourly")

      hourly.fetch("time").each_with_index.map do |epoch, i|
        Hour.new(
          starts_at: Time.at(epoch - 3600).utc,
          rain_chance: hourly.dig("precipitation_probability", i),
          rain_mm: hourly.dig("precipitation", i),
          code: hourly.dig("weather_code", i),
          temperature: hourly.dig("temperature_2m", i),
          day: hourly.dig("is_day", i) == 1
        )
      end
    end

    # Fetches the Forecast and keeps it, on the poller's schedule. A failure
    # keeps the Forecast already there: hours from the last good answer are
    # a better guess than none.
    class Refresh
      def initialize(http:, forecast:, days: Config.horizon_days, logger: nil)
        @http = http
        @forecast = forecast
        @days = days
        @logger = logger || Booking.default_logger
      end

      def call(now: Clock.now)
        hours = Weather.fetch(@http, days: @days)
        return @logger.call("weather: empty forecast — previous kept") if hours.empty?

        @forecast.replace(hours, fetched_at: now)
        @logger.call("weather: #{hours.size} hours, #{hours.count(&:wet?)} wet")
      rescue Adapters::SourceUnavailable, KeyError => e
        @logger.call("weather: failed — #{e.message}")
      end
    end
  end
end
