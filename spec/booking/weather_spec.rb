require "json"

RSpec.describe Booking::Weather do
  # A recorded answer for Tbilisi, 2026-10-11 and 12 — a dry pair of days.
  let(:recorded) { JSON.parse(File.read("spec/fixtures/open_meteo_forecast.json", encoding: "UTF-8")) }

  def hour(at: "2026-10-12 19:00", chance: 0, mm: 0.0, code: 1, temperature: 18.0, day: false)
    Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc(at), rain_chance: chance, rain_mm: mm,
                               code:, temperature:, day:)
  end

  def answer(times:, chance:, mm: times.map { 0.0 }, code: times.map { 3 })
    {
      "hourly" => {
        "time" => times.map { Booking::Clock.local_to_utc(_1).to_i },
        "precipitation_probability" => chance,
        "precipitation" => mm,
        "weather_code" => code,
        "temperature_2m" => times.map { 15.0 },
        "is_day" => times.map { 1 }
      }
    }
  end

  describe ".parse" do
    it "reads every hour of the recorded answer" do
      hours = described_class.parse(recorded)

      expect(hours.size).to eq(recorded.dig("hourly", "time").size)
      expect(hours.map(&:temperature)).to all(be_a(Numeric))
    end

    # Rain is reported for the hour before each timestamp. Taken at face
    # value, the shower between six and seven would land on the seven o'clock
    # court.
    it "pins each row's rain on the hour that ends at it" do
      hours = described_class.parse(answer(times: ["2026-10-12 19:00", "2026-10-12 20:00"], chance: [80, 0]))

      expect(hours.first.starts_at).to eq(Booking::Clock.local_to_utc("2026-10-12 18:00"))
      expect(hours.first).to be_wet
      expect(hours.last.starts_at).to eq(Booking::Clock.local_to_utc("2026-10-12 19:00"))
      expect(hours.last).not_to be_wet
    end
  end

  describe ".fetch" do
    let(:http) do
      Class.new do
        attr_reader :asked

        def initialize(body) = @body = body

        def get_json(url, params = {})
          @asked = [url, params]
          @body
        end
      end.new(recorded)
    end

    it "asks Open-Meteo for Tbilisi, by the hour, in UTC, past the horizon" do
      forecast = described_class.fetch(http, cities: ["Tbilisi"], days: 7)

      url, params = http.asked
      expect(url).to eq("https://api.open-meteo.com/v1/forecast")
      expect(params).to include(latitude: "41.7151", longitude: "44.8271", timezone: "GMT", timeformat: "unixtime", forecast_days: 9)
      expect(params[:hourly]).to include("precipitation_probability", "precipitation", "weather_code")
      expect(forecast.keys).to eq(["Tbilisi"])
    end

    it "never asks further out than Open-Meteo answers" do
      described_class.fetch(http, cities: ["Tbilisi"], days: 30)

      expect(http.asked.last[:forecast_days]).to eq(16)
    end

    # Several points go up as one list and come back as one list, in the
    # order asked; a single point comes back bare, as above.
    describe "for several cities" do
      let(:batumi) { answer(times: ["2026-10-12 19:00"], chance: [90]) }
      let(:http) do
        Class.new do
          attr_reader :asked

          def initialize(body) = @body = body

          def get_json(url, params = {})
            @asked = [url, params]
            @body
          end
        end.new([recorded, batumi])
      end

      it "asks for every city in one request, and hands each city its own answer" do
        forecast = described_class.fetch(http, cities: %w[Tbilisi Batumi], days: 7)

        expect(http.asked.last).to include(latitude: "41.7151,41.6408", longitude: "44.8271,41.6306")
        expect(forecast["Tbilisi"].size).to eq(recorded.dig("hourly", "time").size)
        expect(forecast["Batumi"].map(&:rain_chance)).to eq([90])
      end

      # Matched by position, so one answer short would put Batumi's rain on
      # whichever city came next.
      it "refuses an answer that does not line up with the cities asked for" do
        expect { described_class.fetch(http, cities: %w[Tbilisi Batumi Kutaisi], days: 7) }
          .to raise_error(Booking::Adapters::SourceUnavailable, /asked for 3 cities, got 2/)
      end
    end
  end

  # Each city's point is its centre; the four the clubs are in today.
  it "knows a point in every city with clubs, all of them in Georgia" do
    expect(described_class::CITIES.keys).to include("Tbilisi", "Rustavi", "Batumi", "Kutaisi")
    expect(described_class::CITIES.values).to all(satisfy { |lat, lng| lat.between?(41, 43.6) && lng.between?(40, 46.8) })
  end

  describe ".worst" do
    let(:forecast) do
      described_class.by_hour([hour(at: "2026-10-12 19:00", chance: 10), hour(at: "2026-10-12 20:00", chance: 70)])
    end

    def at(clock) = Booking::Clock.local_to_utc("2026-10-12 #{clock}")

    it "is the hour a one-hour slot sits in" do
      expect(described_class.worst(forecast, at("19:00"), at("20:00")).rain_chance).to eq(10)
    end

    # A ninety-minute game is rained off by its last half hour.
    it "is the wettest hour a longer or offset slot touches" do
      expect(described_class.worst(forecast, at("19:00"), at("20:30")).rain_chance).to eq(70)
      expect(described_class.worst(forecast, at("19:30"), at("20:30")).rain_chance).to eq(70)
    end

    it "is nothing where the Forecast does not reach" do
      expect(described_class.worst(forecast, at("22:00"), at("23:00"))).to be_nil
    end
  end

  describe described_class::Hour do
    it "is wet when rain is likely" do
      expect(hour(chance: 50)).to be_wet
      expect(hour(chance: 30)).not_to be_wet
    end

    # A single model run drizzles into hours the ensemble barely believes in.
    it "goes by the chance of rain over the millimetres, where it has one" do
      expect(hour(chance: 8, mm: 0.1)).not_to be_damp
      expect(hour(chance: nil, mm: 1.2)).to be_wet
      expect(hour(chance: nil, mm: 0.2)).to be_damp
    end

    it "is wet in a thunderstorm, however little it rains" do
      expect(hour(chance: 5, code: 95)).to be_wet
    end

    it "is damp when rain is possible but not likely" do
      expect(hour(chance: 30)).to be_damp
      expect(hour(chance: 60)).not_to be_damp
      expect(hour(chance: 0)).not_to be_damp
    end

    it "draws a clear night as a moon rather than a sun" do
      expect(hour(code: 0, day: true).icon).to eq("☀️")
      expect(hour(code: 0, day: false).icon).to eq("🌙")
      expect(hour(chance: 80).icon).to eq("🌧")
    end
  end

  describe described_class::Outlook do
    it "folds consecutive wet hours into stretches" do
      outlook = described_class.new(hours: [
        hour(at: "2026-10-12 17:00"),
        hour(at: "2026-10-12 18:00", chance: 70),
        hour(at: "2026-10-12 19:00", chance: 90),
        hour(at: "2026-10-12 20:00"),
        hour(at: "2026-10-12 23:00", chance: 60)
      ])

      expect(outlook).to be_wet
      expect(Booking::Messages.weather_outlook(outlook)).to eq("🌧 Rain likely 18:00–20:00, 23:00–00:00")
    end

    it "only mentions showers when nothing is wet" do
      outlook = described_class.new(hours: [hour(at: "2026-10-12 15:00", chance: 30), hour(at: "2026-10-12 16:00")])

      expect(outlook).not_to be_wet
      expect(Booking::Messages.weather_outlook(outlook)).to eq("🌦 Showers possible 15:00–16:00")
    end

    it "says a dry day is dry, with how warm it gets" do
      outlook = described_class.new(hours: [hour(temperature: 12.4), hour(at: "2026-10-12 20:00", temperature: 20.6)])

      expect(Booking::Messages.weather_outlook(outlook)).to eq("🌤 No rain expected · 12–21°")
      expect(outlook.icon).to be_nil
    end
  end

  describe described_class::Refresh do
    let(:db) { Booking::DB.connect("sqlite:/") }
    let(:forecast) { Booking::Repo::Forecast.new(db) }
    let(:said) { [] }
    let(:logger) { ->(line) { said << line } }
    let(:now) { Time.utc(2026, 10, 11, 12) }
    # Kus Tba says no city, which is Tbilisi.
    let(:enabled) { [club("kus-tba-padel")] }
    let(:clubs) { Struct.new(:enabled).new(enabled) }

    def club(slug, city: nil) = Booking::Club.new(slug:, name: slug, adapter: "kustba", settings: city ? { "city" => city } : {})

    def http_answering(&block) = Struct.new(:block) { def get_json(*) = block.call }.new(block)

    def refresh(http, now: self.now) = described_class.new(http:, forecast:, clubs:, logger:).call(now:)

    it "keeps every hour it was given, and says how many are wet" do
      body = answer(times: ["2026-10-12 19:00", "2026-10-12 20:00"], chance: [80, 0])
      refresh(http_answering { body })

      expect(forecast.hours("Tbilisi").map(&:rain_chance)).to eq([80, 0])
      expect(forecast.hours("Tbilisi").first.starts_at).to eq(Booking::Clock.local_to_utc("2026-10-12 18:00"))
      expect(forecast.fetched_at("Tbilisi")).to eq(now)
      expect(said).to eq(["weather: Tbilisi 2 hours, 1 wet"])
    end

    it "replaces the previous Forecast rather than piling onto it" do
      refresh(http_answering { recorded })
      body = answer(times: ["2026-10-12 19:00"], chance: [10])
      refresh(http_answering { body }, now: now + 3600)

      expect(forecast.hours("Tbilisi").size).to eq(1)
    end

    # The last good Forecast is a better guess than none.
    it "keeps the previous Forecast when Open-Meteo cannot be reached" do
      refresh(http_answering { recorded })
      refresh(http_answering { raise Booking::Adapters::SourceUnavailable, "timeout" }, now: now + 3600)

      expect(forecast.hours("Tbilisi").size).to eq(recorded.dig("hourly", "time").size)
      expect(forecast.fetched_at("Tbilisi")).to eq(now)
      expect(said.last).to eq("weather: failed — timeout")
    end

    describe "with clubs in more than one city" do
      let(:enabled) { [club("kus-tba-padel"), club("padel-port", city: "Batumi")] }
      let(:tbilisi) { answer(times: ["2026-10-12 19:00"], chance: [0]) }
      let(:batumi) { answer(times: ["2026-10-12 19:00"], chance: [90]) }

      it "keeps each city's hours under its own name" do
        refresh(http_answering { [tbilisi, batumi] })

        expect(forecast.hours("Tbilisi").map(&:rain_chance)).to eq([0])
        expect(forecast.hours("Batumi").map(&:rain_chance)).to eq([90])
        expect(said).to eq(["weather: Tbilisi 1 hours, 0 wet", "weather: Batumi 1 hours, 1 wet"])
      end

      it "keeps a city's last good Forecast when its own answer comes back empty" do
        refresh(http_answering { [tbilisi, batumi] })
        refresh(http_answering { [tbilisi, answer(times: [], chance: [])] }, now: now + 3600)

        expect(forecast.hours("Batumi").map(&:rain_chance)).to eq([90])
        expect(forecast.fetched_at("Batumi")).to eq(now)
        expect(forecast.fetched_at("Tbilisi")).to eq(now + 3600)
        expect(said.last).to eq("weather: Batumi empty — previous kept")
      end

      # Nobody is shown Batumi any more, so nothing should be left to age.
      it "forgets a city once none of its clubs is enabled" do
        refresh(http_answering { [tbilisi, batumi] })
        enabled.pop
        refresh(http_answering { tbilisi }, now: now + 3600)

        expect(forecast.hours("Batumi")).to be_empty
        expect(forecast.hours("Tbilisi")).not_to be_empty
      end
    end

    # A club added in a city nobody has given a point yet: the rest still get
    # their weather, and the log says what is missing.
    it "fetches the cities it knows, and names the one it does not" do
      enabled << club("gori-padel", city: "Gori")
      refresh(http_answering { recorded })

      expect(forecast.hours("Tbilisi")).not_to be_empty
      expect(said.first).to eq("weather: no point for Gori — add it to Weather::CITIES")
    end
  end
end
