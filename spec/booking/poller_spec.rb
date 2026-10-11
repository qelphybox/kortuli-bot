RSpec.describe Booking::Poller do
  subject(:poller) do
    described_class.new(repos:, notifier:, http: nil, horizon_days: 7, adapter_factory:, logger:)
  end

  let(:db) { Booking::DB.connect("sqlite:/") }
  let(:repos) { Booking::Repos.for(db) }
  let(:notifier) { RecordingNotifier.new }
  let(:logged) { [] }
  let(:logger) { ->(line) { logged << line } }
  let(:adapter_factory) { ->(club, http:) { adapters.fetch(club.slug) } }
  let(:adapters) { { "demo" => FakeAdapter.new(fetched) } }
  let(:fetched) { [] }

  class RecordingNotifier
    attr_reader :delivered

    def initialize = @delivered = []

    def deliver(candidates) = (@delivered.concat(candidates)).then { candidates.size }
  end

  class FakeAdapter
    attr_reader :windows

    def initialize(slots) = (@slots = slots; @windows = [])

    def fetch(window)
      @windows << window
      raise @slots if @slots.is_a?(Class) || @slots.is_a?(StandardError)

      @slots
    end
  end

  # 2026-08-01 is a Saturday; the watch below wants Saturday evenings.
  let(:now) { Booking::Clock.local_to_utc("2026-07-30 12:00") }

  before do
    repos.clubs.upsert(slug: "demo", name: "Demo Club", adapter: "reservio")
    repos.watches.create(
      user_id: 42, club_slugs: ["demo"], weekdays: [6],
      from_minute: Booking::Watch.minute_of_day("19:00"),
      to_minute: Booking::Watch.minute_of_day("22:00")
    )
  end

  def snapshot = repos.slots.snapshot("demo")

  describe "the first poll of a club" do
    let(:fetched) { [slot(club: "demo", court: "Court 1", at: "2026-08-01 19:00")] }

    it "stores what it saw" do
      poller.tick(now:)

      expect(snapshot.size).to eq(1)
    end

    it "tells nobody, because everything looks new the first time" do
      poller.tick(now:)

      expect(notifier.delivered).to be_empty
    end

    it "writes down how the poll went, for the dashboard" do
      poller.tick(now:)

      poll = repos.polls.all.fetch("demo")
      expect([poll.outcome, poll.polled_at, poll.summary]).to eq(["ok", now, "1 free, +0 freed, -0 taken, 0 sent"])
    end

    it "records how far it has polled, so the next tick can spot a cancellation" do
      poller.tick(now:)

      expect(repos.clubs.find("demo").observed_through).to eq(Date.new(2026, 8, 5))
    end

    it "asks the adapter for exactly the configured horizon" do
      poller.tick(now:)

      expect(adapters["demo"].windows.last).to eq(Date.new(2026, 7, 30)..Date.new(2026, 8, 5))
    end
  end

  describe "a cancellation on the second poll" do
    let(:fetched) { [slot(club: "demo", court: "Court 1", at: "2026-08-01 19:00")] }

    before do
      poller.tick(now:)
      adapters["demo"] = FakeAdapter.new(fetched + [slot(club: "demo", court: "Court 2", at: "2026-08-01 20:00")])
    end

    it "notifies the watcher whose window it lands in" do
      poller.tick(now:)

      expect(notifier.delivered.map { _1.slot.court_ref }).to eq(["Court 2"])
      expect(notifier.delivered.first.watch.user_id).to eq(42)
    end

    it "writes the transition to the event log" do
      poller.tick(now:)

      expect(repos.events.count_by_kind).to include("became_available" => 1)
    end

    it "does not notify a second time on an unchanged poll" do
      poller.tick(now:)
      notifier.delivered.clear
      poller.tick(now:)

      expect(notifier.delivered).to be_empty
    end
  end

  describe "when the club's site returns nothing at all" do
    let(:fetched) { [slot(club: "demo", court: "Court 1", at: "2026-08-01 19:00")] }

    before do
      poller.tick(now:)
      adapters["demo"] = FakeAdapter.new([])
    end

    it "keeps the previous snapshot instead of believing the club emptied out" do
      poller.tick(now:)

      expect(snapshot.size).to eq(1)
    end

    it "stays quiet" do
      poller.tick(now:)

      expect(notifier.delivered).to be_empty
    end

    it "says so in the log" do
      poller.tick(now:)

      expect(logged.last).to include("demo").and include("suspect")
    end

    it "marks the club's last poll as suspect" do
      poller.tick(now:)

      expect(repos.polls.all.fetch("demo").outcome).to eq("suspect")
    end

    it "does not flood once the club comes back" do
      poller.tick(now:)                                       # the bad poll
      adapters["demo"] = FakeAdapter.new(fetched)             # site recovers, unchanged
      poller.tick(now:)

      expect(notifier.delivered).to be_empty
    end
  end

  describe "when a broken site comes back" do
    # The site answered with nothing on the very first poll, before anything was
    # known — so that empty answer was accepted, and the horizon moved on. When
    # the real grid arrives, every slot in it lands on an already-known day.
    let(:fetched) { [] }
    let(:grid) { (8..19).map { slot(club: "demo", court: "Court #{_1}", at: "2026-08-01 #{_1}:00") } }

    it "does not mistake the club's whole grid for a rush of cancellations" do
      poller.tick(now:)
      adapters["demo"] = FakeAdapter.new(grid)

      poller.tick(now:)

      expect(notifier.delivered).to be_empty
    end

    it "says in the log that it held a day back" do
      poller.tick(now:)
      adapters["demo"] = FakeAdapter.new(grid)

      poller.tick(now:)

      expect(logged.last).to include("held back")
    end

    it "still notifies about the next real cancellation on that day" do
      poller.tick(now:)
      adapters["demo"] = FakeAdapter.new(grid)
      poller.tick(now:)
      adapters["demo"] = FakeAdapter.new(grid + [slot(club: "demo", court: "Court 99", at: "2026-08-01 20:00")])

      poller.tick(now:)

      expect(notifier.delivered.map { _1.slot.court_ref }).to eq(["Court 99"])
    end
  end

  describe "when the club's site cannot be reached" do
    let(:fetched) { [slot(club: "demo", court: "Court 1", at: "2026-08-01 19:00")] }

    before do
      poller.tick(now:)
      adapters["demo"] = FakeAdapter.new(Booking::Adapters::SourceUnavailable.new("timeout"))
    end

    it "survives the tick" do
      expect { poller.tick(now:) }.not_to raise_error
    end

    it "keeps the snapshot and the polled horizon untouched" do
      poller.tick(now:)

      expect(snapshot.size).to eq(1)
      expect(repos.clubs.find("demo").observed_through).to eq(Date.new(2026, 8, 5))
    end

    it "says so in the log" do
      poller.tick(now:)

      expect(logged.last).to include("demo").and include("failed")
    end

    it "marks the club's last poll as failed, with the reason" do
      poller.tick(now:)

      expect(repos.polls.all.fetch("demo")).to have_attributes(outcome: "failed", summary: "failed — timeout")
    end
  end

  describe "with more than one club" do
    let(:adapters) do
      {
        "demo" => FakeAdapter.new(Booking::Adapters::SourceUnavailable.new("timeout")),
        "other" => FakeAdapter.new([slot(club: "other", court: "Court 9", at: "2026-08-01 19:00")])
      }
    end

    before { repos.clubs.upsert(slug: "other", name: "Other Club", adapter: "reservio") }

    it "keeps polling the rest after one of them fails" do
      poller.tick(now:)

      expect(repos.slots.snapshot("other").size).to eq(1)
    end
  end

  it "skips clubs that are switched off" do
    repos.clubs.upsert(slug: "demo", name: "Demo Club", adapter: "reservio", enabled: false)

    poller.tick(now:)

    expect(adapters["demo"].windows).to be_empty
  end
end
