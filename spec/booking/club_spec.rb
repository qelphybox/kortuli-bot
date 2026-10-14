require "yaml"

RSpec.describe Booking::Club do
  def club(settings = {}) = described_class.new(slug: "padel-port", name: "Padel Port", adapter: "reservio", settings:)

  describe "#city" do
    it "is the city its settings name" do
      expect(club("city" => "Batumi").city).to eq("Batumi")
    end

    # Every club was in Tbilisi before a club could say otherwise, and the
    # entries written then say nothing.
    it "is Tbilisi when the settings do not say" do
      expect(club.city).to eq("Tbilisi")
      expect(club("city" => " ").city).to eq("Tbilisi")
    end

    # The database hands settings back as JSON text.
    it "survives the round trip through the database" do
      clubs = Booking::Repo::Clubs.new(Booking::DB.connect("sqlite:/"))
      clubs.upsert(slug: "padel-port", name: "Padel Port", adapter: "reservio", settings: { city: "Batumi" })

      expect(clubs.find("padel-port").city).to eq("Batumi")
    end
  end

  describe ".cities" do
    it "names each city once, the default first and the rest by name" do
      clubs = [club("city" => "Rustavi"), club, club("city" => "Batumi"), club("city" => "Rustavi")]

      expect(described_class.cities(clubs)).to eq(%w[Tbilisi Batumi Rustavi])
    end
  end

  describe "#short_name" do
    it "is what the settings name, for the pin on the map" do
      expect(club("short_name" => "PORT").short_name).to eq("PORT")
    end

    it "is the first word until they do" do
      expect(club.short_name).to eq("PADEL")
    end
  end

  it "is given a short name for its pin in every entry of config/clubs.yml" do
    names = YAML.safe_load_file("config/clubs.yml").map { _1.dig("settings", "short_name") }

    expect(names).to all(satisfy { _1.is_a?(String) && _1.length.between?(2, 8) })
  end

  # The file the poller mirrors on boot. Saying the city outright rather than
  # leaning on the default keeps the file readable once it holds four cities.
  it "is given a city in every entry of config/clubs.yml, and one the Forecast has a point for" do
    entries = YAML.safe_load_file("config/clubs.yml")

    expect(entries.map { _1.dig("settings", "city") }).to all(be_a(String))
    expect(entries.map { _1.dig("settings", "city") }).to all(satisfy { Booking::Weather::CITIES.key?(_1) })
  end
end
