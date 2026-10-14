module Booking
  # The Forecast: what the sky over each City is expected to do, hour by
  # hour. Asked for because the first thing anybody checks before booking an
  # open court is whether it will rain on it — and a court under a roof is
  # only worth the detour on a day when it will.
  #
  # From Open-Meteo: free, keyless, hourly, and sixteen days out, which covers
  # the Booking horizon twice over. One point per city — a city's clubs sit
  # within a few kilometres of each other, which is about the model's own
  # resolution, so asking per club would buy ten copies of one answer. Across
  # cities it is a different answer: Batumi's sea weather is nothing like
  # Tbilisi's on the same evening.
  module Weather
    URL = "https://api.open-meteo.com/v1/forecast".freeze
    # Each city's centre, as [latitude, longitude]. Kutaisi's is exactly where
    # GeoNames (Open-Meteo's own geocoder) puts it, and Tbilisi's and
    # Rustavi's within two or three kilometres of that; Batumi's is GeoNames'
    # own, because the point first proposed for it sat at the city's southern
    # edge, three kilometres from the old town. Gudauri's is GeoNames' too.
    # GeoNames has no Kachreti, a village around a golf resort, so its point
    # is the court itself, where OpenStreetMap puts Padel Island Kachreti —
    # the resort is the only thing there. A city missing here gets no
    # Forecast, and its clubs are drawn without weather rather than with a
    # neighbour's.
    CITIES = {
      "Tbilisi" => [41.7151, 44.8271],
      "Rustavi" => [41.5495, 44.9930],
      "Batumi" => [41.6408, 41.6306],
      "Kutaisi" => [42.2679, 42.6946],
      "Gudauri" => [42.4780, 44.4762],
      "Kachreti" => [41.6330, 45.6823]
    }.freeze
    # Open-Meteo refuses anything further out.
    MAX_DAYS = 16

    # Likely enough that an open court is a bad bet.
    WET_CHANCE = 50
    # Worth a mention, not worth changing plans over.
    DAMP_CHANCE = 20
    # Where a day's list starts calling an open court wet: the blue under an
    # hour, the roof that leads the hint. Between the two above, because the
    # list is choosing between courts rather than calling the evening off.
    RAINY_CHANCE = 30
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

      # Rain enough that an open court is the wrong one to pick tonight.
      def rainy? = wet? || likely?(RAINY_CHANCE, WET_MM)

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

    # The Forecast keyed by the second each hour starts, which is how both a
    # Cell and a Slot look an hour up.
    def by_hour(hours) = hours.to_h { [_1.starts_at.to_i, _1] }

    # The one hour that matters for a stretch of time: the wettest it touches.
    # A ninety-minute game is rained off by its last half hour as surely as by
    # its first. Nil where the Forecast does not reach.
    def worst(forecast, from, to)
      first = from.to_i - (from.to_i % 3600)
      touched = first.step(to.to_i - 1, 3600).filter_map { forecast[_1] }

      touched.max_by { [_1.wet? ? 2 : _1.damp? ? 1 : 0, _1.rain_chance.to_i] }
    end

    # Every city's hours, by city, from one request: Open-Meteo takes a list
    # of points and answers with a list of forecasts in the order asked — or,
    # for a single point, with the forecast alone. One request rather than
    # one per city, so the cities come from the same model run, and one
    # failure leaves every city on its last good Forecast.
    #
    # Days counted from today in GMT, which is the timezone asked for, plus
    # two: one because a Georgian date starts four hours before GMT's does,
    # and one for the clubs whose evening runs past midnight.
    def fetch(http, cities:, days:)
      points = cities.map { CITIES.fetch(_1) }
      body = http.get_json(URL, {
                             latitude: points.map(&:first).join(","),
                             longitude: points.map(&:last).join(","),
                             hourly: "temperature_2m,precipitation_probability,precipitation,weather_code,is_day",
                             timezone: "GMT",
                             timeformat: "unixtime",
                             forecast_days: [days + 2, MAX_DAYS].min
                           })
      answers = body.is_a?(Array) ? body : [body]
      # Matched up by position, so a list of the wrong length would pin one
      # city's sky on another.
      raise Adapters::SourceUnavailable, "asked for #{cities.size} cities, got #{answers.size}" if answers.size != cities.size

      cities.zip(answers).to_h { |city, answer| [city, parse(answer)] }
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

    # Fetches the Forecast for every city with an enabled club and keeps it,
    # on the poller's schedule. A failure keeps the Forecast already there:
    # hours from the last good answer are a better guess than none.
    class Refresh
      # `clubs` is asked on every refresh rather than once, so a city's
      # Forecast comes and goes with its clubs.
      def initialize(http:, forecast:, clubs:, days: Config.horizon_days, logger: nil)
        @http = http
        @forecast = forecast
        @clubs = clubs
        @days = days
        @logger = logger || Booking.default_logger
      end

      def call(now: Clock.now)
        cities = Club.cities(@clubs.enabled)
        unknown = cities - CITIES.keys
        @logger.call("weather: no point for #{unknown.join(", ")} — add it to Weather::CITIES") if unknown.any?
        cities -= unknown
        return if cities.empty?

        Weather.fetch(@http, cities:, days: @days).each do |city, hours|
          next @logger.call("weather: #{city} empty — previous kept") if hours.empty?

          @forecast.replace(hours, city:, fetched_at: now)
          @logger.call("weather: #{city} #{hours.size} hours, #{hours.count(&:wet?)} wet")
        end
        # Only after an answer: a failed fetch is no reason to forget a city.
        @forecast.keep_only(cities)
      rescue Adapters::SourceUnavailable, KeyError => e
        @logger.call("weather: failed — #{e.message}")
      end
    end
  end
end
