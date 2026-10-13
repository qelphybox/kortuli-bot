RSpec.describe Booking::Schema do
  let(:db) { Booking::DB.connect("sqlite:/") }
  let(:fetched_at) { Time.utc(2026, 10, 13, 9) }

  # The Forecast as it was before there was a second city: Tbilisi's alone,
  # keyed by the hour. Put back over a fresh database, so applying the schema
  # again is exactly what the first boot after the deploy does.
  def forecast_as_it_was
    db.drop_table(:forecast_hours)
    db.create_table(:forecast_hours) do
      DateTime :starts_at, primary_key: true
      Integer :rain_chance
      Float :rain_mm
      Integer :code
      Float :temperature
      TrueClass :day
      DateTime :fetched_at, null: false
    end
    db[:forecast_hours].insert(starts_at: Time.utc(2026, 10, 13, 15), rain_chance: 80, rain_mm: 1.5, code: 61,
                               temperature: 14.0, day: true, fetched_at:)
  end

  describe "giving the Forecast a city" do
    before do
      forecast_as_it_was
      described_class.apply(db)
    end

    # It was the last good Forecast, and it was Tbilisi's: the app should not
    # go without weather until the poller's next refresh.
    it "keeps the hours already on file, as Tbilisi's" do
      forecast = Booking::Repo::Forecast.new(db)

      expect(forecast.hours("Tbilisi").map(&:rain_chance)).to eq([80])
      expect(forecast.fetched_at("Tbilisi")).to eq(fetched_at)
    end

    it "lets another city hold the same hour" do
      forecast = Booking::Repo::Forecast.new(db)
      hour = Booking::Weather::Hour.new(starts_at: Time.utc(2026, 10, 13, 15), rain_chance: 10, rain_mm: 0.0,
                                        code: 3, temperature: 21.0, day: true)
      forecast.replace([hour], city: "Batumi")

      expect(forecast.hours("Batumi").map(&:rain_chance)).to eq([10])
      expect(forecast.hours("Tbilisi").map(&:rain_chance)).to eq([80])
    end

    # Every boot applies the schema, so the second must find nothing to do.
    it "does nothing the second time" do
      described_class.apply(db)

      expect(db[:forecast_hours].columns).to include(:city)
      expect(db[:forecast_hours].count).to eq(1)
      expect(db.tables).not_to include(:forecast_hours_by_city)
    end
  end
end
