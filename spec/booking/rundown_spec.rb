RSpec.describe Booking::Rundown do
  let(:court_level) do
    Booking::Club.new(
      slug: "padel-club-2", name: "Padel Club 2", adapter: "reservio",
      settings: { "opening_hours" => { "from" => "08:00", "to" => "24:00" },
                  "courts" => 4, "price" => "50 GEL",
                  "booking_url" => "https://padel-club2.example/" }
    )
  end

  # Books until 02:00, so its day runs past midnight.
  let(:hour_level) do
    Booking::Club.new(
      slug: "kus-tba-padel", name: "Kus Tba Padel", adapter: "kustba",
      settings: { "opening_hours" => { "from" => "08:00", "to" => "02:00" },
                  "booking_url" => "https://kustba.example/book/" }
    )
  end

  let(:clubs) { [court_level, hour_level] }
  let(:date) { Date.new(2026, 8, 3) }
  # Early on the morning before, so nothing on the page has begun yet.
  let(:now) { Booking::Clock.local_to_utc("2026-08-02 09:00") }

  def at(local) = Booking::Clock.local_to_utc(local)

  def free(club, local, court: "any") = slot(club: club.slug, court:, at: local)

  def sheet(slots, window: nil, now: self.now)
    table = Booking::Grid.build(clubs:, slots:, date:)
    described_class.build(table:, clubs:, window:, now:)
  end

  def runs(entry) = entry.runs.map { [Booking::Clock.to_local(_1.starts_at).hour, Booking::Clock.to_local(_1.ends_at).hour] }

  it "folds consecutive free hours into one stretch, and breaks it where an hour is taken" do
    rundown = sheet(["2026-08-03 18:00", "2026-08-03 19:00", "2026-08-03 21:00"].map { free(court_level, _1) })

    expect(runs(rundown.entries.first)).to eq([[18, 20], [21, 22]])
  end

  # Two free courts in one hour are still one hour to the person reading.
  it "counts an hour once however many courts are free in it" do
    rundown = sheet([free(court_level, "2026-08-03 18:00", court: "1"), free(court_level, "2026-08-03 18:00", court: "2")])

    expect(runs(rundown.entries.first)).to eq([[18, 19]])
  end

  it "carries the club's price and the link to book it" do
    entry = sheet([free(court_level, "2026-08-03 18:00")]).entries.first

    expect(entry.price).to eq("50 GEL")
    expect(entry.link).to eq("https://example.test/book")
  end

  # Said rather than left out, so the reader knows it was looked at.
  it "names the clubs with nothing free" do
    rundown = sheet([free(court_level, "2026-08-03 18:00")])

    expect(rundown.entries.map(&:club_name)).to eq(["Padel Club 2"])
    expect(rundown.booked).to eq(["Kus Tba Padel"])
  end

  it "keeps only the hours inside the window it was narrowed to" do
    slots = ["2026-08-03 10:00", "2026-08-03 18:00", "2026-08-03 22:00"].map { free(court_level, _1) }
    rundown = sheet(slots, window: at("2026-08-03 18:00")...at("2026-08-03 22:00"))

    expect(runs(rundown.entries.first)).to eq([[18, 19]])
  end

  # A window running past midnight still belongs to the evening it started on.
  it "follows a window past midnight into the next morning" do
    rundown = sheet([free(hour_level, "2026-08-04 01:00")], window: at("2026-08-03 23:00")...at("2026-08-04 02:00"))

    expect(rundown.entries.map(&:club_name)).to eq(["Kus Tba Padel"])
  end

  # Sending somebody across town for an hour that has begun is worse than
  # not mentioning it.
  it "leaves out an hour that has already started" do
    rundown = sheet([free(court_level, "2026-08-03 18:00"), free(court_level, "2026-08-03 20:00")],
                    now: at("2026-08-03 18:30"))

    expect(runs(rundown.entries.first)).to eq([[20, 21]])
  end

  it "is empty when nothing is free" do
    expect(sheet([])).to be_empty
  end

  describe "as a message" do
    def text(slots, window: nil) = Booking::Messages.rundown(sheet(slots, window:))

    it "heads with the date, and names the span only when there is one" do
      expect(text([])).to start_with("🎾 Free padel courts · Mon 3 Aug\n")
      expect(text([], window: at("2026-08-03 18:00")...at("2026-08-04 01:00")))
        .to start_with("🎾 Free padel courts · Mon 3 Aug, 18:00–01:00\n")
    end

    it "gives each club its name, price, hours and booking link, one block apiece" do
      message = text([free(court_level, "2026-08-03 18:00"), free(court_level, "2026-08-03 19:00"),
                      free(hour_level, "2026-08-03 21:00")])

      expect(message).to include("Padel Club 2 · 50 GEL\n18:00–20:00\nhttps://example.test/book")
      expect(message).to include("Kus Tba Padel\n21:00–22:00\nhttps://example.test/book")
    end

    it "closes with the clubs that are fully booked" do
      expect(text([free(court_level, "2026-08-03 18:00")])).to end_with("Fully booked: Kus Tba Padel")
    end

    it "says plainly when there is nothing" do
      expect(text([])).to end_with("Nothing free.")
    end
  end
end
