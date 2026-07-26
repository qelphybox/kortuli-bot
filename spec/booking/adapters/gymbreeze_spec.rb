require "json"

# Answers from a recorded copy of the real backend response, so the parsing
# stays pinned to what the club actually sends.
class FakeGymbreezeHttp
  attr_reader :requests

  def initialize(payload: nil)
    @requests = []
    @payload = payload
  end

  def get_json(url, params = {})
    @requests << { url:, params: }
    @payload || JSON.parse(File.read("spec/fixtures/gymbreeze_availability.json"))
  end
end

RSpec.describe Booking::Adapters::Gymbreeze do
  subject(:adapter) { described_class.new(club, http:) }

  let(:http) { FakeGymbreezeHttp.new }
  let(:club) do
    Booking::Club.new(
      slug: "gymbreeze-ninoshvili",
      name: "GymBreeze Ninoshvili",
      adapter: "gymbreeze",
      settings: {
        "location_id" => "63f663fa-1852-5bde-bf94-dee5b176de1d",
        "booking_url" => "https://gymbreeze.ge/eng",
        "price" => "40–60 GEL",
        "max_days" => 8
      }
    )
  end
  # The recorded day: 08:00–18:00 free, 19:00–22:00 sold out across all eight
  # courts, then 23:00 and 00:00 free again.
  let(:one_day) { Date.new(2026, 7, 27)..Date.new(2026, 7, 27) }

  it "returns one slot per free hour" do
    expect(adapter.fetch(one_day).size).to eq(13)
  end

  # The endpoint lists only what is free, which is the contract the differ
  # wants: a sold-out hour is simply absent rather than flagged.
  it "leaves out the hours nobody can book" do
    hours = adapter.fetch(one_day).map { _1.local_starts_at.hour }

    expect(hours).not_to include(19, 20, 21, 22)
  end

  # Court granularity is not on offer: passing `court_id` is answered with
  # "no longer supported, use location_id".
  it "reports the hour rather than a named court" do
    slot = adapter.fetch(one_day).first

    expect(slot.court_ref).to eq("any")
    expect(slot.court_label).to eq("A court")
  end

  it "normalises the club's offset into UTC at the boundary" do
    first = adapter.fetch(one_day).first

    # 08:00 in Tbilisi (+04:00) is 04:00 UTC.
    expect(first.starts_at).to eq(Time.utc(2026, 7, 27, 4, 0))
    expect(first.starts_at.utc?).to be(true)
    expect(first.local_date).to eq(Date.new(2026, 7, 27))
  end

  it "books an hour per slot" do
    expect(adapter.fetch(one_day).map(&:duration_minutes).uniq).to eq([60])
  end

  # The club closes at 01:00, so a day's last slot starts at 00:00 — and unlike
  # Kus Tba's feed, this one already dates that hour to the day it belongs to.
  # Taking the timestamp at its word is therefore correct, and no rollover
  # heuristic is needed.
  it "keeps the hour after midnight on the day the club dated it" do
    late = adapter.fetch(one_day).last

    expect(late.local_date).to eq(Date.new(2026, 7, 28))
    expect(late.local_starts_at.hour).to eq(0)
    expect(late.ends_at).to eq(Time.utc(2026, 7, 27, 21, 0))
  end

  it "carries the club's configured price and booking link" do
    first = adapter.fetch(one_day).first

    expect(first.price).to eq("40–60 GEL")
    expect(first.deeplink).to eq("https://gymbreeze.ge/eng")
  end

  it "stamps every slot with the club it came from" do
    expect(adapter.fetch(one_day).map(&:club_slug).uniq).to eq(["gymbreeze-ninoshvili"])
  end

  it "spends one request per date, naming the location and the date" do
    adapter.fetch(Date.new(2026, 7, 27)..Date.new(2026, 7, 29))

    expect(http.requests.size).to eq(3)
    expect(http.requests.map { _1[:params]["date"] }).to eq(%w[2026-07-27 2026-07-28 2026-07-29])
    expect(http.requests.map { _1[:params]["location_id"] }.uniq)
      .to eq(["63f663fa-1852-5bde-bf94-dee5b176de1d"])
  end

  # The API answers for any date at all — a year out it still reports a whole
  # day free, because nobody can book that far and so nothing is taken. Polling
  # out there would hand the differ a wall of slots that never transitions.
  it "stops at the club's own booking window, however long a range it is given" do
    adapter.fetch(Date.new(2026, 7, 27)..Date.new(2026, 8, 20))

    expect(http.requests.size).to eq(8)
  end

  describe "when the backend answers with something other than an availability list" do
    # Its own refusals come back as a 200 with an `error` key, which parses
    # cleanly and would otherwise read as "no slots" — i.e. as the whole club
    # being booked at once.
    let(:http) { FakeGymbreezeHttp.new(payload: { "error" => "date and location_id are required" }) }

    it "treats it as an unreadable source" do
      expect { adapter.fetch(one_day) }.to raise_error(Booking::Adapters::SourceUnavailable)
    end
  end

  describe "when the club is genuinely sold out" do
    let(:http) { FakeGymbreezeHttp.new(payload: { "available_slots" => [] }) }

    it "returns nothing and leaves the empty-response guard to the differ" do
      expect(adapter.fetch(one_day)).to eq([])
    end
  end

  it "refuses to run without the location it is meant to watch" do
    bare = Booking::Club.new(slug: "x", name: "X", adapter: "gymbreeze", settings: {})

    expect { described_class.new(bare, http:) }.to raise_error(KeyError)
  end
end
