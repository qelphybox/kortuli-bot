RSpec.describe Booking::OpeningHours do
  describe "#starts_by_label" do
    # A club open past midnight files 00:00 and 01:00 under the evening before,
    # and a source that speaks in bare "HH:MM" means exactly that.
    it "keys each start by its wall-clock label, rolling the small hours over" do
      starts = described_class.parse("from" => "22:00", "to" => "02:00").starts_by_label(Date.new(2026, 10, 12))

      expect(starts.keys).to eq(%w[22:00 23:00 00:00 01:00])
      expect(starts["23:00"]).to eq(Booking::Clock.local_to_utc("2026-10-12 23:00"))
      expect(starts["00:00"]).to eq(Booking::Clock.local_to_utc("2026-10-13 00:00"))
    end
  end
end
