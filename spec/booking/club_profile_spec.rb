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

  # Google's documented pairing: the place's card, and the query only when
  # Google can no longer find the place.
  it "opens the club's own place when it has one, with the pin to fall back to" do
    expect(profile.with(place_id: "ChIJjUyxFPINREARSYG9mflWPKo").maps_url)
      .to eq("https://www.google.com/maps/search/?api=1&query=41.6738582,44.8262025&query_place_id=ChIJjUyxFPINREARSYG9mflWPKo")
  end

  it "has no map link without a pin" do
    expect(described_class.from(entry.except("lat", "lng")).maps_url).to be_nil
  end

  describe "the way there" do
    it "is the pin when there is one" do
      expect(profile.directions_url(name: "Padelbade Krtsanisi", city: "Tbilisi")).to eq(profile.maps_url)
    end

    # The street alone could be anywhere called that; the club's name and
    # city in front make it the club.
    it "searches for the club's street without one" do
      unpinned = described_class.from(entry.except("lat", "lng").merge("address" => "7 Giorgi Guramishvili St"))

      expect(unpinned.directions_url(name: "Padelbade Krtsanisi", city: "Tbilisi"))
        .to eq("https://www.google.com/maps/search/?api=1&query=Padelbade+Krtsanisi%2C+7+Giorgi+Guramishvili+St%2C+Tbilisi")
    end

    it "names the club's place beside its street" do
      unpinned = described_class.from(entry.except("lat", "lng").merge("place_id" => "ChIJjUyxFPINREARSYG9mflWPKo"))

      expect(unpinned.directions_url(name: "Padelbade Krtsanisi", city: "Tbilisi"))
        .to end_with("query=Padelbade+Krtsanisi%2C+Ortachala%2C+Tbilisi&query_place_id=ChIJjUyxFPINREARSYG9mflWPKo")
    end

    it "falls back from the street to the area" do
      unpinned = described_class.from(entry.except("lat", "lng"))

      expect(unpinned.directions_url(name: "Padelbade Krtsanisi", city: "Tbilisi")).to end_with("query=Padelbade+Krtsanisi%2C+Ortachala%2C+Tbilisi")
    end

    it "has nothing to point at with neither" do
      expect(described_class.from(entry.except("lat", "lng", "area")).directions_url(name: "X", city: "Tbilisi")).to be_nil
    end
  end

  it "knows the day its listing was read" do
    expect(profile.checked_on).to eq(Date.new(2026, 10, 11))
  end

  describe ".pinned" do
    let(:pin) { { "lat" => 42.4616226, "lng" => 44.4842351 } }

    it "places a club with no Profile, and claims nothing else about it" do
      pinned = described_class.pinned(nil, pin)

      expect([pinned.lat, pinned.lng]).to eq([42.4616226, 44.4842351])
      expect(pinned.courts).to be_empty
      expect(pinned).not_to be_listed
    end

    it "places a Profile the listing left without a pin, and keeps the rest of it" do
      pinned = described_class.pinned(profile.with(lat: nil, lng: nil), pin)

      expect(pinned.lat).to eq(42.4616226)
      expect(pinned.area).to eq("Ortachala")
      expect(pinned).to be_listed
    end

    it "leaves a pin the listing gave alone" do
      expect(described_class.pinned(profile, pin)).to eq(profile)
    end

    it "gives a Profile the club's place on Google Maps" do
      expect(described_class.pinned(profile, nil, place_id: "ChIJjUyxFPINREARSYG9mflWPKo").place_id)
        .to eq("ChIJjUyxFPINREARSYG9mflWPKo")
    end

    it "gives a pinned club its place too" do
      expect(described_class.pinned(nil, pin, place_id: "ChIJi-eoAAApRUAR1VbzHgEbFFQ").place_id).to eq("ChIJi-eoAAApRUAR1VbzHgEbFFQ")
    end

    it "makes no Profile out of a place alone" do
      expect(described_class.pinned(nil, nil, place_id: "ChIJjUyxFPINREARSYG9mflWPKo")).to be_nil
    end

    it "changes nothing without a whole pin" do
      expect(described_class.pinned(nil, nil)).to be_nil
      expect(described_class.pinned(nil, { "lat" => 42.46 })).to be_nil
    end
  end

  # The pins written into config/clubs.yml by hand, so checked by hand too:
  # both halves there, and somewhere in Georgia.
  it "is given whole pins in Georgia wherever config/clubs.yml gives one" do
    pins = YAML.safe_load_file("config/clubs.yml").filter_map { _1.dig("settings", "pin") }

    expect(pins).not_to be_empty
    expect(pins).to all(satisfy { |pin| Float(pin["lat"]).between?(41, 43.6) && Float(pin["lng"]).between?(40, 46.8) })
  end

  # Written into config/clubs.yml by hand, like the pins: each one a Google
  # place ID, and no two clubs sharing one.
  it "is given one place on Google Maps per club wherever config/clubs.yml gives one" do
    places = YAML.safe_load_file("config/clubs.yml").filter_map { _1.dig("settings", "place_id") }

    expect(places).not_to be_empty
    expect(places).to all(match(/\AChIJ[\w-]{23}\z/))
    expect(places).to eq(places.uniq)
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

    # The import writes the file as one YAML.dump, so anything else in it was
    # typed or merged by hand — which is how a merge once moved one club's
    # hours and prices under another's with every key still present.
    it "ships the file exactly as the import writes it" do
      text = File.read("config/club_profiles.yml", encoding: "UTF-8")
      body = text.sub(/\A(#[^\n]*\n)+/, "")

      expect(body).to eq(YAML.dump(YAML.safe_load(body)).delete_prefix("---\n"))
    end
  end

  describe "in words" do
    it "sums the covers up" do
      expect(Booking::Messages.cover_summary(profile.covers)).to eq("1 indoor · 2 covered · 1 outdoor")
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
