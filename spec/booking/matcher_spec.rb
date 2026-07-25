RSpec.describe Booking::Watch do
  def watch(clubs: ["reservio-demo"], days: [6], from: "19:00", to: "22:00", active: true)
    described_class.new(
      id: 1, user_id: 42, club_slugs: clubs, weekdays: days,
      from_minute: Booking::Watch.minute_of_day(from),
      to_minute: Booking::Watch.minute_of_day(to),
      active:
    )
  end

  # 2026-08-01 is a Saturday (wday 6).
  describe "#covers?" do
    it "accepts a slot inside the window on a watched day at a watched club" do
      expect(watch).to be_covers(slot(at: "2026-08-01 19:00"))
    end

    it "rejects another club" do
      expect(watch(clubs: ["somewhere-else"])).not_to be_covers(slot(at: "2026-08-01 19:00"))
    end

    it "rejects another weekday" do
      expect(watch(days: [1])).not_to be_covers(slot(at: "2026-08-01 19:00"))
    end

    it "rejects a slot starting before the window" do
      expect(watch).not_to be_covers(slot(at: "2026-08-01 18:00"))
    end

    it "rejects a slot that runs past the window" do
      # 21:30–22:30 starts inside 19:00–22:00 but finishes outside it.
      expect(watch).not_to be_covers(slot(at: "2026-08-01 21:30"))
    end

    it "accepts a slot that ends exactly on the boundary" do
      expect(watch).to be_covers(slot(at: "2026-08-01 21:00"))
    end

    it "judges the day and hour in Tbilisi, not UTC" do
      # 00:30 local Sunday is still Saturday 20:30 in UTC; a watch on Sunday
      # late-night should match, a watch on Saturday should not.
      late = slot(at: "2026-08-02 00:30")
      expect(watch(days: [0], from: "00:00", to: "02:00")).to be_covers(late)
      expect(watch(days: [6], from: "00:00", to: "02:00")).not_to be_covers(late)
    end
  end
end

RSpec.describe Booking::Matcher do
  subject(:matcher) { described_class.new }

  def watch(id:, user_id: 42, clubs: ["reservio-demo"], days: [6], active: true)
    Booking::Watch.new(
      id:, user_id:, club_slugs: clubs, weekdays: days,
      from_minute: Booking::Watch.minute_of_day("19:00"),
      to_minute: Booking::Watch.minute_of_day("22:00"),
      active:
    )
  end

  let(:freed) { slot(at: "2026-08-01 19:00") }
  let(:before_the_slot) { Booking::Clock.local_to_utc("2026-07-30 12:00") }

  it "pairs a freed slot with every watch that wants it" do
    candidates = matcher.match(
      events: [freed],
      watches: [watch(id: 1, user_id: 42), watch(id: 2, user_id: 99)],
      now: before_the_slot
    )

    expect(candidates.map { _1.watch.user_id }).to contain_exactly(42, 99)
    expect(candidates.map(&:slot)).to all(eq(freed))
  end

  it "ignores paused watches" do
    candidates = matcher.match(events: [freed], watches: [watch(id: 1, active: false)], now: before_the_slot)

    expect(candidates).to be_empty
  end

  it "ignores a slot that has already started" do
    after_the_slot = Booking::Clock.local_to_utc("2026-08-01 19:30")

    candidates = matcher.match(events: [freed], watches: [watch(id: 1)], now: after_the_slot)

    expect(candidates).to be_empty
  end
end
