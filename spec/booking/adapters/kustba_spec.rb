require "json"

# Answers from a recorded copy of the real turtle-booking response, so the
# parsing stays pinned to what the plugin actually sends.
class FakeKustbaHttp
  attr_reader :requests

  def initialize(payload: nil)
    @requests = []
    @payload = payload
  end

  def get_json(url, params = {})
    @requests << { url:, params: }
    @payload || JSON.parse(File.read("spec/fixtures/kustba_available_slots.json"))
  end
end

RSpec.describe Booking::Adapters::Kustba do
  subject(:adapter) { described_class.new(club, http:) }

  let(:http) { FakeKustbaHttp.new }
  let(:club) do
    Booking::Club.new(
      slug: "kus-tba-padel",
      name: "Kus Tba Padel",
      adapter: "kustba",
      settings: {
        "booking_url" => "https://kustbapadel.ge/book/",
        "price" => "80 GEL",
        "max_days" => 7
      }
    )
  end
  # The recorded day: 08:00–19:00 open, 20:00–22:00 sold out, then 23:00, 00:00
  # and 01:00 open again.
  let(:one_day) { Date.new(2026, 7, 27)..Date.new(2026, 7, 27) }

  it "returns one slot per hour the club reports as available" do
    expect(adapter.fetch(one_day).size).to eq(15)
  end

  it "leaves out the hours nobody can book" do
    hours = adapter.fetch(one_day).map { _1.local_starts_at.hour }

    # `full` means every court is taken, `inactive` means past or closed.
    expect(hours).not_to include(20, 21, 22)
  end

  # The feed reports availability per hour, not per court, so one request buys a
  # whole day. The cost of court-level identity is one request per open hour —
  # 110 per poll against 7 — which is why a slot here stands for the hour.
  it "reports the hour rather than a named court" do
    slot = adapter.fetch(one_day).first

    expect(slot.court_ref).to eq("any")
    expect(slot.court_label).to eq("A court")
  end

  it "normalises the club's local time into UTC at the boundary" do
    first = adapter.fetch(one_day).first

    # 08:00 in Tbilisi (+04:00) is 04:00 UTC.
    expect(first.starts_at).to eq(Time.utc(2026, 7, 27, 4, 0))
    expect(first.starts_at.utc?).to be(true)
    expect(first.local_date).to eq(Date.new(2026, 7, 27))
  end

  it "books an hour per slot" do
    expect(adapter.fetch(one_day).first.duration_minutes).to eq(60)
  end

  # The club's day runs past midnight: the feed lists 23:00, 00:00, 01:00 under
  # one date, and the last two belong to the next one. Filing them on the
  # requested date would put a Tuesday 01:00 slot in front of a Monday watch.
  describe "the hours past midnight" do
    it "lands them on the following calendar day" do
      late = adapter.fetch(one_day).select { _1.local_date == Date.new(2026, 7, 28) }

      expect(late.map { _1.local_starts_at.hour }).to eq([0, 1])
    end

    it "keeps the evening hours on the requested day" do
      evening = adapter.fetch(one_day).select { _1.local_date == Date.new(2026, 7, 27) }

      expect(evening.map { _1.local_starts_at.hour }.last).to eq(23)
    end
  end

  it "carries the club's configured price and booking link" do
    first = adapter.fetch(one_day).first

    expect(first.price).to eq("80 GEL")
    expect(first.deeplink).to eq("https://kustbapadel.ge/book/")
  end

  it "stamps every slot with the club it came from" do
    expect(adapter.fetch(one_day).map(&:club_slug).uniq).to eq(["kus-tba-padel"])
  end

  it "spends one request per date, asking for that date by name" do
    adapter.fetch(Date.new(2026, 7, 27)..Date.new(2026, 7, 29))

    expect(http.requests.size).to eq(3)
    expect(http.requests.map { _1[:params]["date"] }).to eq(%w[2026-07-27 2026-07-28 2026-07-29])
  end

  # The API answers for any date it is asked about, including ones past the
  # club's own booking window — and every hour out there reads `available`
  # because nobody can book it yet. Polling that far would hand the differ a
  # wall of slots that never transitions.
  it "stops at the club's own booking window, however long a range it is given" do
    adapter.fetch(Date.new(2026, 7, 27)..Date.new(2026, 8, 10))

    expect(http.requests.size).to eq(7)
  end

  describe "when the plugin answers with something other than a list of hours" do
    # A renamed route answers 200 with a JSON error body, which parses fine and
    # would otherwise sail through as "no slots" — i.e. as mass cancellation.
    let(:http) { FakeKustbaHttp.new(payload: { "code" => "rest_no_route" }) }

    it "treats it as an unreadable source" do
      expect { adapter.fetch(one_day) }.to raise_error(Booking::Adapters::SourceUnavailable)
    end
  end

  describe "when the club is genuinely sold out" do
    let(:http) { FakeKustbaHttp.new(payload: []) }

    it "returns nothing and leaves the empty-response guard to the differ" do
      expect(adapter.fetch(one_day)).to eq([])
    end
  end
end
