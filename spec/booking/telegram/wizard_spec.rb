RSpec.describe Booking::Telegram::Wizard do
  let(:clubs) do
    [
      Booking::Club.new(slug: "demo", name: "Demo Club", adapter: "reservio"),
      Booking::Club.new(slug: "other", name: "Other Club", adapter: "reservio")
    ]
  end

  def start = described_class.begin
  def apply(draft, data) = described_class.apply(draft, Booking::Telegram::Callback.parse(data), clubs:)
  def view(draft) = described_class.view(draft, clubs:)
  def labels(draft) = view(draft).keyboard.flatten.map(&:text)
  def datas(draft) = view(draft).keyboard.flatten.map(&:data)

  # Walks the wizard to the point where hours are being asked for.
  def draft_at_hours
    d = start
    d = apply(d, "w:club:demo").draft
    apply(d, "w:next").draft
      .then { apply(_1, "w:day:6").draft }
      .then { apply(_1, "w:next").draft }
  end

  describe "picking clubs" do
    it "opens on the club step with nothing chosen" do
      expect(start.step).to eq(:clubs)
      expect(start.club_slugs).to be_empty
    end

    it "offers every configured club" do
      expect(labels(start)).to include("Demo Club", "Other Club")
    end

    it "selects a club when it is tapped" do
      expect(apply(start, "w:club:demo").draft.club_slugs).to eq(["demo"])
    end

    it "deselects the same club when it is tapped again" do
      chosen = apply(start, "w:club:demo").draft

      expect(apply(chosen, "w:club:demo").draft.club_slugs).to be_empty
    end

    it "marks the chosen clubs in the keyboard" do
      chosen = apply(start, "w:club:demo").draft

      expect(labels(chosen)).to include(a_string_including("Demo Club").and(a_string_including("✅")))
    end

    it "refuses to move on with nothing chosen" do
      outcome = apply(start, "w:next")

      expect(outcome.draft.step).to eq(:clubs)
      expect(outcome.alert).to eq(Booking::Messages.pick_at_least_one_club)
    end

    it "moves to the days step once a club is chosen" do
      chosen = apply(start, "w:club:demo").draft

      expect(apply(chosen, "w:next").draft.step).to eq(:days)
    end
  end

  describe "picking days" do
    let(:on_days) { apply(apply(start, "w:club:demo").draft, "w:next").draft }

    it "lists the week starting on Monday" do
      expect(labels(on_days).first).to include("Mon")
    end

    it "toggles a day" do
      expect(apply(on_days, "w:day:6").draft.weekdays).to eq([6])
    end

    it "refuses to move on with no day chosen" do
      outcome = apply(on_days, "w:next")

      expect(outcome.draft.step).to eq(:days)
      expect(outcome.alert).to eq(Booking::Messages.pick_at_least_one_day)
    end

    it "moves to the opening hour once a day is chosen" do
      chosen = apply(on_days, "w:day:6").draft

      expect(apply(chosen, "w:next").draft.step).to eq(:from)
    end
  end

  describe "picking hours" do
    it "records the opening hour and asks for the closing one" do
      outcome = apply(draft_at_hours, "w:from:19")

      expect(outcome.draft.from_minute).to eq(19 * 60)
      expect(outcome.draft.step).to eq(:to)
    end

    it "only offers closing hours after the opening one" do
      on_to = apply(draft_at_hours, "w:from:19").draft

      hours = datas(on_to).grep(/\Aw:to:/).map { _1.split(":").last.to_i }
      expect(hours).to all(be > 19)
    end

    it "finishes once the closing hour is chosen" do
      on_to = apply(draft_at_hours, "w:from:19").draft
      outcome = apply(on_to, "w:to:22")

      expect(outcome.status).to eq(:finished)
      expect(outcome.draft.to_minute).to eq(22 * 60)
    end

    it "hands back everything the caller needs to build a watch" do
      finished = apply(apply(draft_at_hours, "w:from:19").draft, "w:to:22").draft

      expect(finished.club_slugs).to eq(["demo"])
      expect(finished.weekdays).to eq([6])
      expect(finished.from_minute).to eq(1140)
      expect(finished.to_minute).to eq(1320)
    end
  end

  describe "leaving early" do
    it "can be cancelled from any step" do
      expect(apply(start, "w:cancel").status).to eq(:cancelled)
      expect(apply(draft_at_hours, "w:cancel").status).to eq(:cancelled)
    end
  end

  describe "input it does not understand" do
    it "ignores a button from another step without losing progress" do
      chosen = apply(start, "w:club:demo").draft
      outcome = apply(chosen, "w:to:22")

      expect(outcome.status).to eq(:ignored)
      expect(outcome.draft).to eq(chosen)
    end

    it "ignores an unknown club" do
      expect(apply(start, "w:club:nonexistent").draft.club_slugs).to be_empty
    end

    it "ignores junk" do
      expect(apply(start, "nonsense").status).to eq(:ignored)
    end
  end

  describe Booking::Telegram::Wizard::Store do
    subject(:store) { described_class.new }

    it "has nothing for a user who never started" do
      expect(store.fetch(42)).to be_nil
    end

    it "remembers a draft per user" do
      store.put(42, "a")
      store.put(99, "b")

      expect(store.fetch(42)).to eq("a")
      expect(store.fetch(99)).to eq("b")
    end

    it "forgets a draft on request" do
      store.put(42, "a")
      store.delete(42)

      expect(store.fetch(42)).to be_nil
    end
  end
end
