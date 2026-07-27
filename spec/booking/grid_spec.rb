RSpec.describe Booking::Grid do
  # A court-level club: its source names the individual court, so its Cells can
  # say how many of the four are free.
  let(:court_level) do
    Booking::Club.new(
      slug: "padel-club-2", name: "Padel Club 2", adapter: "reservio",
      settings: { "opening_hours" => { "from" => "08:00", "to" => "24:00" },
                  "courts" => 4,
                  "booking_url" => "https://padel-club2.example/" }
    )
  end

  # An hour-level club: the source will only say whether *some* court is free.
  # Kus Tba books until 02:00, so its day runs past midnight.
  let(:hour_level) do
    Booking::Club.new(
      slug: "kus-tba-padel", name: "Kus Tba Padel", adapter: "kustba",
      settings: { "opening_hours" => { "from" => "08:00", "to" => "02:00" },
                  "booking_url" => "https://kustba.example/book/" }
    )
  end

  let(:date) { Date.new(2026, 8, 3) }

  def table(clubs, slots) = described_class.build(clubs:, slots:, date:)

  def build(clubs, slots) = table(clubs, slots).rows

  def free_at(club, local, court: "any")
    slot(club: club.slug, court:, at: local)
  end

  it "gives every club a row, in the order it was handed them" do
    rows = build([court_level, hour_level], [])

    expect(rows.map(&:club_name)).to eq(["Padel Club 2", "Kus Tba Padel"])
  end

  describe "how long a row is" do
    it "runs across the club's own opening hours" do
      row = build([court_level], []).first

      expect(row.cells.map { _1.local_starts_at.hour }).to eq((8..23).to_a)
    end

    # The club shuts at 02:00, so the last hour anyone can start is 01:00 — and
    # two of its cells belong to the following calendar day.
    it "keeps going past midnight when the club does" do
      row = build([hour_level], []).first

      expect(row.cells.map { _1.local_starts_at.hour }).to eq((8..23).to_a + [0, 1])
    end

    it "puts the hours after midnight on the day they belong to" do
      row = build([hour_level], []).first
      late = row.cells.last(2)

      expect(late.map { _1.local_starts_at.to_date }.uniq).to eq([Date.new(2026, 8, 4)])
    end
  end

  # Absence of a Slot is what "taken" means — the snapshot only ever holds free
  # ones — so a club nobody can book still has to draw a full row rather than
  # disappear from the screen.
  it "draws a full row of unavailable cells for a club with nothing free" do
    row = build([court_level], []).first

    expect(row.cells.size).to eq(16)
    expect(row.cells.map(&:free?).uniq).to eq([false])
  end

  describe "a court-level club" do
    it "counts the distinct courts free that hour, against the club's real total" do
      slots = [
        free_at(court_level, "2026-08-03 19:00", court: "Court 1"),
        free_at(court_level, "2026-08-03 19:00", court: "Court 3")
      ]

      cell = build([court_level], slots).first.cells.find { _1.local_starts_at.hour == 19 }

      expect(cell).to be_free
      expect(cell.free_courts).to eq(2)
      expect(cell.total_courts).to eq(4)
    end

    # The denominator is what the club has, not what happened to be free this
    # week — otherwise a fully booked court quietly shrinks the club.
    it "reports the total even when only one court was ever free" do
      slots = [free_at(court_level, "2026-08-03 09:00", court: "Court 2")]

      cell = build([court_level], slots).first.cells.find { _1.local_starts_at.hour == 9 }

      expect(cell.free_courts).to eq(1)
      expect(cell.total_courts).to eq(4)
    end
  end

  describe "an hour-level club" do
    it "says the hour is free without inventing a count" do
      slots = [free_at(hour_level, "2026-08-03 20:00")]

      cell = build([hour_level], slots).first.cells.find { _1.local_starts_at.hour == 20 }

      expect(cell).to be_free
      expect(cell).not_to be_counted
      expect(cell.free_courts).to be_nil
      expect(cell.total_courts).to be_nil
    end
  end

  it "leaves an hour with nothing free unavailable" do
    slots = [free_at(hour_level, "2026-08-03 20:00")]

    cell = build([hour_level], slots).first.cells.find { _1.local_starts_at.hour == 21 }

    expect(cell).not_to be_free
  end

  it "does not let one club's slots light up another club's row" do
    slots = [free_at(hour_level, "2026-08-03 19:00")]

    row = build([court_level, hour_level], slots).first

    expect(row.cells.map(&:free?).uniq).to eq([false])
  end

  it "carries somewhere to go on a free cell" do
    slots = [free_at(hour_level, "2026-08-03 12:00")]

    cell = build([hour_level], slots).first.cells.find { _1.local_starts_at.hour == 12 }

    expect(cell.deeplink).to eq("https://example.test/book")
  end

  it "orders cells by when they start" do
    cells = build([hour_level], []).first.cells

    expect(cells.map(&:starts_at)).to eq(cells.map(&:starts_at).sort)
  end

  # Clubs keep different hours — one shuts at midnight, another runs to 02:00 —
  # so the screen needs one axis wide enough for all of them, and rows have to
  # be able to say "not me" for a column outside their own day.
  describe "the shared column axis" do
    it "spans the union of every club's hours, in order" do
      columns = table([court_level, hour_level], []).columns

      expect(columns.map { Booking::Clock.to_local(_1).hour }).to eq((8..23).to_a + [0, 1])
    end

    it "has no cell for a club that is already shut" do
      built = table([court_level, hour_level], [])
      after_midnight = built.columns.last
      closes_at_midnight = built.rows.find { _1.club_slug == "padel-club-2" }

      expect(closes_at_midnight.cell_at(after_midnight)).to be_nil
    end

    it "still has one for a club that is open then" do
      built = table([court_level, hour_level], [])
      after_midnight = built.columns.last
      open_late = built.rows.find { _1.club_slug == "kus-tba-padel" }

      expect(open_late.cell_at(after_midnight)).not_to be_nil
    end

    it "carries the date it was built for" do
      expect(table([court_level], []).date).to eq(date)
    end
  end
end
