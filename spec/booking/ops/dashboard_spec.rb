require "tmpdir"

RSpec.describe Booking::Ops::Dashboard do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  subject(:dashboard) { described_class.new(db:, database_path:, log_dir: @dir, poll_every: 300) }

  let(:database_path) { File.join(@dir, "booking.db") }
  let(:db) { Booking::DB.connect("sqlite://#{database_path}") }
  let(:repos) { Booking::Repos.for(db) }
  let(:now) { Time.utc(2026, 10, 11, 12, 0, 0) }

  after { db.disconnect }

  describe "#polls" do
    before do
      %w[fresh broken stale never].each { repos.clubs.upsert(slug: _1, name: _1.capitalize, adapter: "reservio") }
      repos.polls.record("fresh", outcome: :ok, summary: "3 free", at: now - 60)
      repos.polls.record("broken", outcome: :failed, summary: "failed — timeout", at: now - 60)
      repos.polls.record("stale", outcome: :ok, summary: "3 free", at: now - 901)
    end

    def states = dashboard.polls(now:).to_h { [_1.club.slug, _1.state] }

    it "says how each club's last poll went" do
      expect(states).to include("fresh" => "ok", "broken" => "failed")
    end

    # A poll loop that stopped looks exactly like one whose last poll worked.
    it "calls a poll older than three ticks stale, whatever it said at the time" do
      expect(states["stale"]).to eq("stale")
    end

    it "names a club nobody has polled yet" do
      expect(states["never"]).to eq("never")
    end
  end

  describe "#storage" do
    it "weighs the database file and the WAL beside it, and counts every table" do
      repos.clubs.upsert(slug: "demo", name: "Demo", adapter: "reservio")

      storage = dashboard.storage

      expect(storage.files.map(&:first)).to include("booking.db", "booking.db-wal")
      expect(storage.total_bytes).to be_positive
      expect(storage.tables).to include("clubs" => 1, "polls" => 0)
    end

    it "weighs nothing for a database that lives in memory" do
      memory = described_class.new(db:, database_path: nil, log_dir: @dir, poll_every: 300)

      expect(memory.storage.files).to be_empty
    end
  end

  it "measures the disk the database lives on" do
    expect(dashboard.disk.total_bytes).to be_positive
  end

  describe "#activity" do
    it "counts people once however many watches and stars they have, and the last day's traffic" do
      watch = repos.watches.create(user_id: 1, club_slugs: ["demo"], weekdays: [1], from_minute: 0, to_minute: 60)
      repos.watches.create(user_id: 1, club_slugs: ["demo"], weekdays: [2], from_minute: 0, to_minute: 60)
      repos.favourites.add(1, "demo")
      repos.favourites.add(2, "demo")
      repos.notifications.claim(watch_id: watch.id, slot_key: "recent", at: now - 3600)
      repos.notifications.claim(watch_id: watch.id, slot_key: "old", at: now - 90_000)
      repos.events.record(club_slug: "demo", kind: :became_available, slots: [slot(club: "demo")], at: now - 60)

      activity = dashboard.activity(now:)

      expect(activity.to_h).to eq(people: 2, active_watches: 2, notified_24h: 1, freed_24h: 1)
    end
  end

  it "reads every process's heartbeat, the missing ones included" do
    Booking::Ops::Heartbeat.new(dir: @dir, process: "poller").beat

    expect(dashboard.processes.to_h { [_1.process, _1.beat_at.nil?] }).to eq("poller" => false, "bot" => true, "web" => true)
  end
end
