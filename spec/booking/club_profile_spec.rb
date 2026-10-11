require "tmpdir"

RSpec.describe Booking::ClubProfile do
  let(:entry) do
    {
      "source" => "https://sapadelo.com/georgia/clubs/padelbade-krtsanisi",
      "area" => "Ortachala",
      "lat" => 41.6738582,
      "lng" => 44.8262025,
      "courts" => [
        { "name" => "Blue 1", "cover" => "covered" },
        { "name" => "Black 1", "cover" => "indoor" },
        { "name" => "Blue 2", "cover" => "covered" },
        { "name" => "Yard", "cover" => "outdoor" }
      ],
      "hours" => { "mon" => "08:00–02:00", "tue" => "08:00–02:00", "wed" => "08:00–02:00", "thu" => "08:00–02:00",
                   "fri" => "08:00–02:00", "sat" => "10:00–02:00", "sun" => "10:00–02:00" },
      "prices" => [{ "gel" => 80 }]
    }
  end
  let(:profile) { described_class.from(entry, checked_on: "2026-10-11") }

  it "counts the courts under each cover, roofed first" do
    expect(profile.covers).to eq([["indoor", 1], ["covered", 2], ["outdoor", 1]])
  end

  it "folds days that keep the same hours" do
    expect(profile.hour_runs).to eq([%w[mon fri 08:00–02:00], %w[sat sun 10:00–02:00]])
  end

  it "does not fold days the week puts apart" do
    hours = { "mon" => "08:00–02:00", "tue" => "Closed", "wed" => "08:00–02:00" }

    expect(described_class.from(entry.merge("hours" => hours)).hour_runs)
      .to eq([%w[mon mon 08:00–02:00], %w[tue tue Closed], %w[wed wed 08:00–02:00]])
  end

  it "opens its pin in Google Maps" do
    expect(profile.maps_url).to eq("https://www.google.com/maps/search/?api=1&query=41.6738582,44.8262025")
  end

  it "has no map link without a pin" do
    expect(described_class.from(entry.except("lat", "lng")).maps_url).to be_nil
  end

  it "knows the day its listing was read" do
    expect(profile.checked_on).to eq(Date.new(2026, 10, 11))
  end

  describe ".load" do
    it "reads every club's profile from the file the import writes" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "club_profiles.yml")
        File.write(path, YAML.dump("checked_on" => "2026-10-11", "clubs" => { "padelbade-krtsanisi" => entry }))

        profiles = described_class.load(path)

        expect(profiles.keys).to eq(["padelbade-krtsanisi"])
        expect(profiles["padelbade-krtsanisi"].area).to eq("Ortachala")
      end
    end

    it "is empty without a file rather than refusing to boot" do
      expect(described_class.load("/nonexistent/club_profiles.yml")).to eq({})
    end

    it "reads the file that ships in config/ for every club linked to sapadelo" do
      linked = YAML.safe_load_file("config/clubs.yml").filter_map { _1["slug"] if _1.dig("settings", "sapadelo") }

      expect(described_class.load("config/club_profiles.yml").keys).to match_array(linked)
    end
  end

  describe "in words" do
    it "sums the covers up" do
      expect(Booking::Messages.cover_summary(profile.covers)).to eq("1 indoor · 2 covered · 1 outdoor")
      expect(Booking::Messages.cover_tag(profile.covers)).to eq("indoor + covered + outdoor")
    end

    it "names a run of days" do
      expect(Booking::Messages.day_run("mon", "sun")).to eq("Every day")
      expect(Booking::Messages.day_run("mon", "fri")).to eq("Mon–Fri")
      expect(Booking::Messages.day_run("sat", "sat")).to eq("Sat")
    end

    it "reads a price rule back as one line" do
      expect(Booking::Messages.price_line("gel" => 60)).to eq("60 GEL")
      expect(Booking::Messages.price_line("gel" => 40, "from" => "11:00", "to" => "18:00")).to eq("40 GEL · 11:00–18:00")
      expect(Booking::Messages.price_line("gel" => 80, "days" => %w[sat sun], "from" => "08:00", "to" => "02:00"))
        .to eq("80 GEL · Sat, Sun · 08:00–02:00")
      expect(Booking::Messages.price_line("gel" => 40, "from_price" => true)).to eq("from 40 GEL")
    end
  end
end
