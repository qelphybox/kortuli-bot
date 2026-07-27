RSpec.describe Booking::Watch do
  def watch(clubs: ["reservio-demo"], days: [6], from: "19:00", to: "22:00", active: true, date: nil)
    described_class.new(
      id: 1, user_id: 42, club_slugs: clubs, weekdays: days,
      from_minute: Booking::Watch.minute_of_day(from),
      to_minute: Booking::Watch.minute_of_day(to),
      active:, date:
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

  # Nothing reaps an expired Dated watch — the Matcher discards slots that have
  # already started, so it stops matching on its own. This predicate exists so
  # the screen can stop showing a request that can no longer come true.
  describe "#expired?" do
    def dated(date:, from: "19:00", to: "20:00") = watch(date:, days: [Date.iso8601(date).wday], from:, to:)

    it "is never true of a standing watch, however old" do
      expect(watch).not_to be_expired(Booking::Clock.local_to_utc("2030-01-01 12:00"))
    end

    it "is false while the hour is still to come" do
      expect(dated(date: "2026-08-01")).not_to be_expired(Booking::Clock.local_to_utc("2026-08-01 18:59"))
    end

    # The hour it watches is the hour it wanted to play. Once that has started,
    # the Matcher would discard the slot anyway — so the request has stopped
    # being one that can come true, and the screen should stop carrying it.
    it "is true once the hour has begun, not merely once it has finished" do
      expect(dated(date: "2026-08-01")).to be_expired(Booking::Clock.local_to_utc("2026-08-01 19:00"))
      expect(dated(date: "2026-08-01")).to be_expired(Booking::Clock.local_to_utc("2026-08-01 19:30"))
    end

    # An hour after midnight belongs to the date it starts on, which is the
    # date the watch carries — so this is the case that would break if the
    # arithmetic went through the weekday instead.
    it "handles an hour that starts after midnight" do
      early = dated(date: "2026-08-02", from: "01:00", to: "02:00")

      expect(early).not_to be_expired(Booking::Clock.local_to_utc("2026-08-01 23:30"))
      expect(early).to be_expired(Booking::Clock.local_to_utc("2026-08-02 01:00"))
    end

    # 24:00 is not a time Ruby will parse, so the last hour of the day is where
    # naive formatting of the range would blow up.
    it "handles the last hour of the day" do
      last = dated(date: "2026-08-01", from: "23:00", to: "24:00")

      expect(last).not_to be_expired(Booking::Clock.local_to_utc("2026-08-01 22:59"))
      expect(last).to be_expired(Booking::Clock.local_to_utc("2026-08-01 23:00"))
    end

    it "judges the hour in Tbilisi, not UTC" do
      # 19:00 Tbilisi is 15:00 UTC; a naive comparison would keep this watch on
      # the screen for another four hours.
      expect(dated(date: "2026-08-01")).to be_expired(Time.utc(2026, 8, 1, 15, 0))
      expect(dated(date: "2026-08-01")).not_to be_expired(Time.utc(2026, 8, 1, 14, 59))
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
