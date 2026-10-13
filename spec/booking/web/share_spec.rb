# The Share screen's hours switch: the whole day, or the evening in a tap.
# The screen itself is exercised in app_spec, beside the rest of the routes.
RSpec.describe Booking::Web::HourSpan do
  let(:date) { Date.new(2026, 10, 14) }

  # The Grid's columns for a day that sells `first` to `last` (counted from
  # the date's midnight, so 25 is 01:00 the next day).
  def columns(first, last) = (first..last).map { Booking::Clock.local_to_utc(format("%s %02d:00", date + (_1 / 24), _1 % 24)) }

  def span(first, last, **params) = described_class.from(params, date:, columns: columns(first, last))

  describe "#evening" do
    it "is 18:00 to 23:00 on a day that sells them" do
      evening = span(8, 25).evening

      expect([evening.from, evening.to]).to eq([18, 23])
      expect(evening.short_label).to eq("18–23")
    end

    it "is cut to the hours on offer" do
      evening = span(8, 20).evening

      expect([evening.from, evening.to]).to eq([18, 21])
    end

    it "is nil on a day that is over before it starts" do
      expect(span(8, 16).evening).to be_nil
    end

    # Nothing the "All day" switch does not already say.
    it "is nil when it would be the whole day" do
      expect(span(18, 22).evening).to be_nil
    end

    it "is nil on a day with no hours at all" do
      expect(described_class.from({}, date:, columns: []).evening).to be_nil
    end
  end

  describe "#evening?" do
    it "is the span picked being the evening" do
      expect(span(8, 25, from: 18, to: 23)).to be_evening
      expect(span(8, 25, from: 18, to: 22)).not_to be_evening
      expect(span(8, 25)).not_to be_evening
    end
  end
end
