RSpec.describe Booking::Telegram::Callback do
  it "reads back what it wrote" do
    data = described_class.build("w", "club", "padel-club-2")

    expect(described_class.parse(data)).to have_attributes(prefix: "w", action: "club", value: "padel-club-2")
  end

  it "survives the round trip with no value, rather than growing a trailing colon" do
    data = described_class.build("w", "cancel")

    expect(data).to eq("w:cancel")
    expect(described_class.parse(data).value).to be_nil
  end

  # Club slugs contain no colons today, but the separator limit is what stops a
  # slug that grows one from silently truncating into a different button.
  it "keeps a value that contains the separator intact" do
    data = described_class.build("l", "delete", "a:b:c")

    expect(described_class.parse(data).value).to eq("a:b:c")
  end

  it "reports a prefix nothing owns, so routing can ignore it" do
    expect(described_class.parse("garbage").prefix).to eq("garbage")
  end

  it "treats an empty callback as owned by nobody" do
    expect(described_class.parse(nil)).to have_attributes(prefix: nil, action: nil, value: nil)
  end
end
