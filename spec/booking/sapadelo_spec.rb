require "yaml"

# Read from recorded pages, pruned to the rows the parser looks at: Padelbade
# Dighomi's own page (two courts under two different covers, prices that move
# with the hour and the weekday) and the Tbilisi listing, its clubs stripped of
# the floor plans and photos nobody reads.
RSpec.describe Booking::Sapadelo do
  let(:club_page) { File.read("spec/fixtures/sapadelo_club.html") }
  let(:listing) { File.read("spec/fixtures/sapadelo_tbilisi.html") }
  let(:source) { described_class.club_url("padelbade-dighomi") }

  describe ".profile" do
    subject(:profile) { described_class.profile(club_page, source:, area: "Didi Dighomi") }

    it "names every court and the cover over it, in our words rather than theirs" do
      expect(profile["courts"]).to eq([
        { "name" => "Brick Red (Road)", "cover" => "covered" },
        { "name" => "Green (Wall)", "cover" => "indoor" }
      ])
    end

    it "drops a pin where the club says it is" do
      expect(profile.values_at("lat", "lng")).to eq([41.8050415, 44.7686565])
    end

    it "carries the address and the telephone the page publishes" do
      expect(profile.values_at("address", "phone")).to eq(["240 Davit Aghmashenebeli Ave", "0322500549"])
    end

    it "lists the hours of every day, Monday first, as the page prints them" do
      expect(profile["hours"].keys).to eq(%w[mon tue wed thu fri sat sun])
      expect(profile["hours"]["mon"]).to eq("08:00–02:00")
    end

    it "keeps each price rule with its hours, and folds days that share one" do
      expect(profile["prices"]).to eq([
        { "gel" => 60 },
        { "gel" => 80, "from" => "18:00", "to" => "02:00" },
        { "gel" => 80, "from" => "08:00", "to" => "02:00", "days" => %w[sat sun] }
      ])
    end

    it "remembers where it came from and the neighbourhood it was handed" do
      expect(profile.values_at("source", "area")).to eq([source, "Didi Dighomi"])
    end

    it "is plain data a YAML file can hold and give back" do
      expect(YAML.safe_load(YAML.dump(profile))).to eq(profile)
    end

    it "refuses a page that is not a club's, rather than writing half a profile" do
      expect { described_class.profile("<html>Not found</html>", source:) }.to raise_error(Booking::Error, /no club data/)
    end

    it "reads a body that arrived as bytes" do
      expect(described_class.profile(club_page.b, source:)["courts"].size).to eq(2)
    end
  end

  describe ".prices" do
    def rule(amount, days: [], from: nil, to: nil, order: 0, sport: "padel")
      { "amount" => format("%.3f", amount), "qualifier" => "exact", "sportType" => sport, "days" => days,
        "startMinute" => from, "endMinute" => to, "sortOrder" => order }
    end

    # GymBreeze Ninoshvili's list: 40 at midday undercuts 60, and then the
    # weekend puts 60 back. Folding the weekend into the base price because the
    # amount matches would say midday is 40 on Saturday too.
    it "keeps a rule for some days apart from one for every day, even at the same price" do
      prices = described_class.prices([
        rule(60, order: 0), rule(40, from: 660, to: 1080, order: 1),
        rule(60, days: ["sat"], order: 2), rule(60, days: ["sun"], order: 3)
      ])

      expect(prices).to eq([{ "gel" => 60 }, { "gel" => 40, "from" => "11:00", "to" => "18:00" },
                            { "gel" => 60, "days" => %w[sat sun] }])
    end

    it "leaves out what is not padel" do
      expect(described_class.prices([rule(40, sport: "pickleball"), rule(70)])).to eq([{ "gel" => 70 }])
    end

    it "says so when a price is only where it starts" do
      expect(described_class.prices([rule(40).merge("qualifier" => "from")])).to eq([{ "gel" => 40, "from_price" => true }])
    end
  end

  describe ".areas" do
    it "names the neighbourhood of every club on the city's listing" do
      areas = described_class.areas(listing)

      expect(areas).to include("padelbade-dighomi" => "Didi Dighomi", "padel-academy" => "Saburtalo",
                               "kus-tba-padel" => "Turtle Lake")
    end
  end

  describe ".flight_rows" do
    # A text row carries its length rather than ending at a newline, so the
    # next row can start straight after it on the same line.
    it "reads a text row by its length and carries on into the row after it" do
      stream = %(0:{"a":"$1"}\n1:T5,hello2:["$","div",null,{}]\n)
      html = %(<script>self.__next_f.push([1,#{JSON.generate(stream)}])</script>)

      rows = described_class.flight_rows(html)

      expect(rows).to eq("0" => { "a" => "$1" }, "1" => "hello", "2" => ["$", "div", nil, {}])
      expect(described_class.resolve(rows["0"], rows)).to eq("a" => "hello")
    end
  end
end
