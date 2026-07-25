RSpec.describe Booking::Slot do
  describe "#key — synthetic identity" do
    it "is stable across fetches of the same slot" do
      expect(slot.key).to eq(slot.key)
    end

    it "distinguishes courts within a club" do
      expect(slot(court: "Court 1").key).not_to eq(slot(court: "Court 2").key)
    end

    it "distinguishes start times on the same court" do
      expect(slot(at: "2026-08-01 19:00").key).not_to eq(slot(at: "2026-08-01 20:00").key)
    end

    it "distinguishes clubs holding identically-named courts" do
      expect(slot(club: "a", court: "Court 1").key).not_to eq(slot(club: "b", court: "Court 1").key)
    end

    it "survives cosmetic renames of the court" do
      expect(slot(court: "Court 1").key).to eq(slot(court: "  court   1 ").key)
    end
  end

  describe "#local_date — the day a human would call it" do
    it "reports Tbilisi's date, not UTC's" do
      # 00:30 Tbilisi on Aug 2nd is still Aug 1st in UTC.
      expect(slot(at: "2026-08-02 00:30").local_date).to eq(Date.new(2026, 8, 2))
    end
  end
end

RSpec.describe Booking::CourtName do
  it "collapses whitespace and case" do
    expect(described_class.normalize("  Court   1 ")).to eq("court 1")
  end

  it "ignores decorative punctuation" do
    expect(described_class.normalize("Court #1 (indoor)")).to eq(described_class.normalize("Court 1 indoor"))
  end

  it "resolves a club's manual alias to the name it stands in for" do
    aliases = { "Centre Court" => "Court 1" }

    expect(described_class.canonical("  Centre Court ", aliases:)).to eq("Court 1")
  end

  it "leaves a name no alias covers alone" do
    expect(described_class.canonical("Court 2", aliases: { "Centre Court" => "Court 1" })).to eq("Court 2")
  end
end
