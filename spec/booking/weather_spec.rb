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
      described_class.fetch(http, days: 7)

      url, params = http.asked
      expect(url).to eq("https://api.open-meteo.com/v1/forecast")
      expect(params).to include(latitude: 41.7151, longitude: 44.8271, timezone: "GMT", timeformat: "unixtime", forecast_days: 9)
      expect(params[:hourly]).to include("precipitation_probability", "precipitation", "weather_code")
    end

    it "never asks further out than Open-Meteo answers" do
      described_class.fetch(http, days: 30)

      expect(http.asked.last[:forecast_days]).to eq(16)
    end
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

    def http_answering(&block) = Struct.new(:block) { def get_json(*) = block.call }.new(block)

    it "keeps every hour it was given, and says how many are wet" do
      body = answer(times: ["2026-10-12 19:00", "2026-10-12 20:00"], chance: [80, 0])
      described_class.new(http: http_answering { body }, forecast:, logger:).call(now:)

      expect(forecast.hours.map(&:rain_chance)).to eq([80, 0])
      expect(forecast.hours.first.starts_at).to eq(Booking::Clock.local_to_utc("2026-10-12 18:00"))
      expect(forecast.fetched_at).to eq(now)
      expect(said).to eq(["weather: 2 hours, 1 wet"])
    end

    it "replaces the previous Forecast rather than piling onto it" do
      described_class.new(http: http_answering { recorded }, forecast:, logger:).call(now:)
      body = answer(times: ["2026-10-12 19:00"], chance: [10])
      described_class.new(http: http_answering { body }, forecast:, logger:).call(now: now + 3600)

      expect(forecast.hours.size).to eq(1)
    end

    # The last good Forecast is a better guess than none.
    it "keeps the previous Forecast when Open-Meteo cannot be reached" do
      described_class.new(http: http_answering { recorded }, forecast:, logger:).call(now:)
      failing = http_answering { raise Booking::Adapters::SourceUnavailable, "timeout" }
      described_class.new(http: failing, forecast:, logger:).call(now: now + 3600)

      expect(forecast.hours.size).to eq(recorded.dig("hourly", "time").size)
      expect(forecast.fetched_at).to eq(now)
      expect(said.last).to eq("weather: failed — timeout")
    end
  end
end
