RSpec.describe "repositories" do
  let(:db) { Booking::DB.connect("sqlite:/") }

  describe Booking::Repo::Slots do
    subject(:repo) { described_class.new(db) }

    it "returns nothing for a club it has never stored" do
      expect(repo.snapshot("reservio-demo")).to be_empty
    end

    it "round-trips a slot without losing its identity or its timezone" do
      original = slot(court: "Court 1", at: "2026-08-01 19:00", price: "60 GEL")

      repo.replace("reservio-demo", [original])
      stored = repo.snapshot("reservio-demo").first

      expect(stored.key).to eq(original.key)
      expect(stored.starts_at).to eq(original.starts_at)
      expect(stored.local_date).to eq(Date.new(2026, 8, 1))
      expect(stored.price).to eq("60 GEL")
    end

    it "replaces the snapshot wholesale rather than accumulating" do
      repo.replace("reservio-demo", [slot(court: "Court 1"), slot(court: "Court 2")])
      repo.replace("reservio-demo", [slot(court: "Court 3")])

      expect(repo.snapshot("reservio-demo").map(&:court_ref)).to eq(["Court 3"])
    end

    it "keeps clubs out of each other's snapshots" do
      repo.replace("club-a", [slot(club: "club-a", court: "Court 1")])
      repo.replace("club-b", [])

      expect(repo.snapshot("club-a").size).to eq(1)
    end
  end

  describe Booking::Repo::Notifications do
    subject(:repo) { described_class.new(db) }

    it "lets the first claim through" do
      expect(repo.claim(watch_id: 1, slot_key: "k")).to be(true)
    end

    it "refuses a second claim on the same slot — the anti-spam guarantee" do
      repo.claim(watch_id: 1, slot_key: "k")

      expect(repo.claim(watch_id: 1, slot_key: "k")).to be(false)
    end

    it "treats different watches on the same slot as separate claims" do
      repo.claim(watch_id: 1, slot_key: "k")

      expect(repo.claim(watch_id: 2, slot_key: "k")).to be(true)
    end

    it "re-arms a claim that was released after a failed send" do
      repo.claim(watch_id: 1, slot_key: "k")
      repo.release(watch_id: 1, slot_key: "k")

      expect(repo.claim(watch_id: 1, slot_key: "k")).to be(true)
    end
  end

  describe Booking::Repo::Watches do
    subject(:repo) { described_class.new(db) }

    def create = repo.create(user_id: 42, club_slugs: ["reservio-demo"], weekdays: [6, 0], from_minute: 1140, to_minute: 1320)

    it "round-trips a watch into a usable domain object" do
      created = create
      found = repo.find(created.id)

      expect(found.user_id).to eq(42)
      expect(found.club_slugs).to eq(Set["reservio-demo"])
      expect(found.weekdays).to eq(Set[0, 6])
      expect(found).to be_active
    end

    it "lists only active watches for the matcher" do
      first = create
      create
      repo.set_active(first.id, false)

      expect(repo.active.size).to eq(1)
    end

    it "forgets a deleted watch" do
      created = create
      repo.delete(created.id)

      expect(repo.for_user(42)).to be_empty
    end
  end

  describe Booking::Repo::Favourites do
    subject(:repo) { described_class.new(db) }

    it "remembers the clubs each person starred, and only theirs" do
      repo.add(42, "padel-club-2")
      repo.add(42, "kus-tba-padel")
      repo.add(7, "gymbreeze-vake")

      expect(repo.for_user(42)).to eq(Set["padel-club-2", "kus-tba-padel"])
    end

    # A double tap on a slow connection arrives as two posts.
    it "treats starring twice as starring once" do
      repo.add(42, "padel-club-2")
      repo.add(42, "padel-club-2")

      expect(repo.for_user(42)).to eq(Set["padel-club-2"])
    end

    it "forgets an unstarred club" do
      repo.add(42, "padel-club-2")
      repo.remove(42, "padel-club-2")

      expect(repo.for_user(42)).to be_empty
    end

    # The order a day's list leads with them.
    it "keeps the stars in the order they were given" do
      repo.add(42, "kus-tba-padel")
      repo.add(42, "padel-club-2")
      repo.add(42, "padelhub")

      expect(repo.ordered(42)).to eq(%w[kus-tba-padel padel-club-2 padelhub])
    end
  end

  describe Booking::Repo::Visits do
    subject(:repo) { described_class.new(db) }

    let(:monday) { Date.new(2026, 10, 12) }

    def rows = db[:visits].order(:date).select_map(%i[user_id date])

    it "keeps one row a day per person, however many screens they open" do
      repo.record(42, on: monday)
      repo.record(42, on: monday)
      repo.record(7, on: monday)

      expect(rows).to contain_exactly([42, monday], [7, monday])
    end

    it "keeps a second day as a second row" do
      repo.record(42, on: monday)
      repo.record(42, on: monday + 1)

      expect(rows).to eq([[42, monday], [42, monday + 1]])
    end
  end

  describe Booking::Repo::Preferences do
    subject(:repo) { described_class.new(db) }

    it "has no city for somebody who never picked one" do
      expect(repo.city(42)).to be_nil
    end

    it "keeps the latest city each person picked, and only theirs" do
      repo.choose_city(42, "Batumi")
      repo.choose_city(42, "Kutaisi")
      repo.choose_city(7, "Rustavi")

      expect(repo.city(42)).to eq("Kutaisi")
      expect(db[:preferences].where(user_id: 42).count).to eq(1)
    end
  end

  describe Booking::Repo::Forecast do
    subject(:repo) { described_class.new(db) }

    let(:now) { Time.utc(2026, 10, 13, 9) }

    def hour(at, chance:)
      Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc(at), rain_chance: chance, rain_mm: 0.0,
                                 code: 3, temperature: 15.0, day: true)
    end

    it "keeps each city's hours apart, the same hour included" do
      repo.replace([hour("2026-10-13 19:00", chance: 0)], city: "Tbilisi", fetched_at: now)
      repo.replace([hour("2026-10-13 19:00", chance: 90)], city: "Batumi", fetched_at: now + 60)

      expect(repo.hours("Tbilisi").map(&:rain_chance)).to eq([0])
      expect(repo.hours("Batumi").map(&:rain_chance)).to eq([90])
      expect(repo.fetched_at("Batumi")).to eq(now + 60)
      expect(repo.counts).to eq("Tbilisi" => 1, "Batumi" => 1)
    end

    # A refresh that only reached one city must not wipe another's.
    it "replaces one city's hours without touching another's" do
      repo.replace([hour("2026-10-13 19:00", chance: 0)], city: "Tbilisi", fetched_at: now)
      repo.replace([hour("2026-10-13 19:00", chance: 90)], city: "Batumi", fetched_at: now)
      repo.replace([hour("2026-10-13 20:00", chance: 40), hour("2026-10-13 21:00", chance: 10)], city: "Tbilisi", fetched_at: now + 3600)

      expect(repo.hours("Tbilisi").map(&:rain_chance)).to eq([40, 10])
      expect(repo.hours("Batumi").map(&:rain_chance)).to eq([90])
    end

    it "forgets the cities it is no longer asked to keep" do
      repo.replace([hour("2026-10-13 19:00", chance: 0)], city: "Tbilisi", fetched_at: now)
      repo.replace([hour("2026-10-13 19:00", chance: 90)], city: "Batumi", fetched_at: now)
      repo.keep_only(["Tbilisi"])

      expect(repo.counts).to eq("Tbilisi" => 1)
      expect(repo.fetched_at("Batumi")).to be_nil
    end
  end

  describe Booking::Repo::Clubs do
    subject(:repo) { described_class.new(db) }

    def upsert(**overrides)
      repo.upsert(**{ slug: "reservio-demo", name: "Demo", adapter: "reservio" }.merge(overrides))
    end

    it "creates then updates in place rather than duplicating" do
      upsert
      upsert(name: "Renamed")

      expect(repo.all.size).to eq(1)
      expect(repo.find("reservio-demo").name).to eq("Renamed")
    end

    it "parses settings back into a hash" do
      upsert(settings: { "court_aliases" => { "Centre Court" => "Court 1" } })

      expect(repo.find("reservio-demo").court_aliases).to eq({ "Centre Court" => "Court 1" })
    end

    it "hides disabled clubs from the poller" do
      upsert(enabled: false)

      expect(repo.enabled).to be_empty
    end

    it "advances the polled horizon" do
      upsert
      repo.observed_through!("reservio-demo", Date.new(2026, 8, 8))

      expect(repo.find("reservio-demo").observed_through).to eq(Date.new(2026, 8, 8))
    end

    it "never retracts the horizon on a short fetch" do
      upsert
      repo.observed_through!("reservio-demo", Date.new(2026, 8, 8))
      repo.observed_through!("reservio-demo", Date.new(2026, 8, 3))

      expect(repo.find("reservio-demo").observed_through).to eq(Date.new(2026, 8, 8))
    end
  end
end

RSpec.describe Booking::Repo::Polls do
  subject(:polls) { described_class.new(Booking::DB.connect("sqlite:/")) }

  let(:at) { Time.utc(2026, 10, 11, 12, 0, 0) }

  it "keeps only the latest poll of each club" do
    polls.record("demo", outcome: :failed, summary: "failed — timeout", at:)
    polls.record("demo", outcome: :ok, summary: "3 free", at: at + 240)

    expect(polls.all.fetch("demo")).to have_attributes(outcome: "ok", summary: "3 free", polled_at: at + 240)
  end

  it "refuses an outcome the dashboard would not know how to draw" do
    expect { polls.record("demo", outcome: :maybe, summary: "?") }.to raise_error(ArgumentError)
  end
end
