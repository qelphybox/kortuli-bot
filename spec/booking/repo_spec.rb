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
