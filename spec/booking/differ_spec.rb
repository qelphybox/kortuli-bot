RSpec.describe Booking::Differ do
  subject(:differ) { described_class.new }

  # Adapters return only the slots that are *free*. Presence means available;
  # absence means taken.
  def diff(previous, current) = differ.diff(previous:, current:)

  describe "the happy path" do
    it "reports a slot that appeared on an already-known day as freed" do
      previous = [slot(court: "Court 1", at: "2026-08-01 19:00")]
      current  = previous + [slot(court: "Court 2", at: "2026-08-01 20:00")]

      result = diff(previous, current)

      expect(result).to be_ok
      expect(result.became_available.map(&:court_ref)).to eq(["Court 2"])
      expect(result.became_taken).to be_empty
    end

    it "reports a slot that vanished as taken" do
      previous = [slot(court: "Court 1"), slot(court: "Court 2")]
      current  = [slot(court: "Court 1")]

      result = diff(previous, current)

      expect(result.became_taken.map(&:court_ref)).to eq(["Court 2"])
      expect(result.became_available).to be_empty
    end

    it "stays silent when nothing moved" do
      snapshot = [slot(court: "Court 1"), slot(court: "Court 2")]

      result = diff(snapshot, snapshot)

      expect(result.became_available).to be_empty
      expect(result.became_taken).to be_empty
    end
  end

  describe "the sliding booking window" do
    # Clubs open a new day N days out, usually overnight. Every slot on that day
    # is new — but nobody cancelled anything, so nobody should be told.
    it "stays silent about a day it has never seen before" do
      previous = [slot(at: "2026-08-01 19:00")]
      current  = previous + [
        slot(court: "Court 1", at: "2026-08-08 19:00"),
        slot(court: "Court 2", at: "2026-08-08 20:00")
      ]

      result = diff(previous, current)

      expect(result).to be_ok
      expect(result.became_available).to be_empty
    end

    it "still reports cancellations on a known day in the same tick" do
      previous = [slot(court: "Court 1", at: "2026-08-01 19:00")]
      current  = previous + [
        slot(court: "Court 2", at: "2026-08-01 20:00"),   # a real cancellation
        slot(court: "Court 1", at: "2026-08-08 19:00")    # a newly opened day
      ]

      result = diff(previous, current)

      expect(result.became_available.map(&:local_date)).to eq([Date.new(2026, 8, 1)])
    end

    it "treats the very first poll as one big unseen day" do
      result = diff([], [slot(court: "Court 1"), slot(court: "Court 2")])

      expect(result).to be_ok
      expect(result.became_available).to be_empty
    end
  end

  describe "days we have polled but never saw a free slot on" do
    # The snapshot only holds *free* slots, so a fully-booked day leaves no
    # trace in it. Asking the snapshot "have we seen this day?" would swallow
    # the first cancellation on any sold-out day — the single most valuable
    # notification the bot can send. The club's polled horizon is the honest
    # answer instead.
    it "reports a cancellation on a day that was sold out when we last looked" do
      previous = [slot(at: "2026-08-01 19:00")]
      current  = previous + [slot(court: "Court 3", at: "2026-08-05 20:00")]

      result = differ.diff(previous:, current:, known_through: Date.new(2026, 8, 8))

      expect(result.became_available.map(&:local_date)).to eq([Date.new(2026, 8, 5)])
    end

    it "still stays silent past the horizon we have actually polled" do
      previous = [slot(at: "2026-08-01 19:00")]
      current  = previous + [slot(court: "Court 3", at: "2026-08-09 20:00")]

      result = differ.diff(previous:, current:, known_through: Date.new(2026, 8, 8))

      expect(result.became_available).to be_empty
    end
  end

  describe "a whole day arriving at once" do
    # Two different faults look the same from here: a club whose booking window
    # is shorter than ours opening a new day inside the horizon, and a source
    # that returned a partial (or empty) response last tick and has recovered.
    # Both dump a day's entire grid into `appeared`. Neither is a cancellation.
    def grid(day, count) = (8...(8 + count)).map { slot(court: "Court #{_1}", at: "#{day} #{_1}:00") }

    it "does not read a day's whole grid as a rush of cancellations" do
      previous = [slot(at: "2026-08-01 19:00")]
      current = previous + grid("2026-08-03", 12)

      result = differ.diff(previous:, current:, known_through: Date.new(2026, 8, 8))

      expect(result.became_available).to be_empty
    end

    it "names the day it held back, so the log can say why" do
      previous = [slot(at: "2026-08-01 19:00")]
      current = previous + grid("2026-08-03", 12)

      result = differ.diff(previous:, current:, known_through: Date.new(2026, 8, 8))

      expect(result.suppressed_days).to eq([Date.new(2026, 8, 3)])
    end

    it "still reports the handful of cancellations a real day produces" do
      previous = [slot(at: "2026-08-01 19:00")]
      current = previous + grid("2026-08-03", 3)

      result = differ.diff(previous:, current:, known_through: Date.new(2026, 8, 8))

      expect(result.became_available.size).to eq(3)
    end

    it "holds back only the flooded day, not the quiet ones beside it" do
      previous = [slot(at: "2026-08-01 19:00")]
      current = previous + grid("2026-08-03", 12) + grid("2026-08-04", 2)

      result = differ.diff(previous:, current:, known_through: Date.new(2026, 8, 8))

      expect(result.became_available.map(&:local_date).uniq).to eq([Date.new(2026, 8, 4)])
    end

    it "does not flood when a source recovers from having returned nothing" do
      # The empty response was accepted (nothing was known yet), so the horizon
      # advanced and every slot now looks like it landed on a known day.
      result = differ.diff(previous: [], current: grid("2026-08-03", 12), known_through: Date.new(2026, 8, 8))

      expect(result.became_available).to be_empty
    end
  end

  describe "guarding against a flapping source" do
    # A 500, a timeout, or a silently-changed layout all look identical to a
    # naive differ: an empty array, i.e. "the whole club just got booked".
    it "flags an empty response after a healthy one as a bad poll" do
      previous = [slot(court: "Court 1"), slot(court: "Court 2")]

      result = diff(previous, [])

      expect(result).not_to be_ok
      expect(result.reason).to eq(:empty_response)
    end

    it "emits nothing at all on a bad poll" do
      result = diff([slot(court: "Court 1")], [])

      expect(result.became_available).to be_empty
      expect(result.became_taken).to be_empty
    end

    it "accepts an empty response when the club was already empty" do
      expect(diff([], [])).to be_ok
    end
  end
end
