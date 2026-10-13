require "json"

# Answers from recorded copies of the real API, taken at 23:05 Tbilisi time on
# 2026-10-13: the bookable dates, the court list (Court 4 inactive), and each
# active court's starts for the 13th and the 14th. The 14th was empty on all
# three courts; on the 13th everything up to 23:00 had gone, which the source
# reports as taken, leaving 23:30 and 00:00.
class FakeAiapadelHttp
  attr_reader :requests

  def initialize(days: nil, courts: nil, slots: nil)
    recorded = JSON.parse(File.read("spec/fixtures/aiapadel_availability.json", encoding: "UTF-8"))
    @days = days || recorded["days"]
    @courts = courts || recorded["courts"]
    @slots = slots || lambda do |params|
      by_date = recorded["slots"].fetch(params["courtId"])
      # A date nobody recorded answers like the empty 14th, under its own date.
      by_date.fetch(params["date"]) { by_date["2026-10-14"].merge("date" => params["date"]) }
    end
    @requests = []
  end

  def get_json(url, params = {}, headers: {})
    @requests << { url:, params:, headers: }
    return @days if url.end_with?("/days")
    return @courts if url.end_with?("/courts")

    @slots.call(params)
  end

  def slot_requests = requests.select { _1[:url].end_with?("/slots") }
end

RSpec.describe Booking::Adapters::Aiapadel do
  let(:http) { FakeAiapadelHttp.new }
  let(:settings) do
    {
      "booking_url" => "https://aiapadel.ge/book",
      "price" => "60 GEL",
      "opening_hours" => { "from" => "09:00", "to" => "01:00" },
      "courts" => 3,
      "max_days" => 10
    }
  end
  let(:club) do
    Booking::Club.new(slug: "aia-padel", name: "AIA Padel", adapter: "aiapadel", settings:)
  end
  let(:the_14th) { Date.new(2026, 10, 14)..Date.new(2026, 10, 14) }
  let(:the_13th) { Date.new(2026, 10, 13)..Date.new(2026, 10, 13) }
  let(:days_before) { Booking::Clock.local_to_utc("2026-10-12 12:00") }

  COURT_1 = "c0000000-0000-4000-8000-000000000001".freeze
  COURT_4 = "c0000000-0000-4000-8000-000000000004".freeze

  def fetch(range = the_14th, now: days_before)
    described_class.new(club, http:, clock: Struct.new(:now).new(now)).fetch(range)
  end

  def hours(slots, court = COURT_1) = slots.select { _1.court_ref == court }.map { _1.local_starts_at.hour }

  # Sixteen hourly starts a day, 09:00 to 00:00, on the three active courts.
  it "returns one slot per free hour per court" do
    expect(fetch.size).to eq(16 * 3)
  end

  it "leaves out the hours the source flags as taken" do
    expect(hours(fetch(the_13th))).to eq([0])
  end

  # The source names the court, so this is a court-level club.
  it "reports the individual court by its stable id, under its own label" do
    slot = fetch.find { _1.court_ref == COURT_1 }

    expect(slot.court_label).to eq("Court 1")
  end

  it "asks each active court for its own day at the hour-long duration, and never the inactive one" do
    fetch

    expect(http.slot_requests.map { _1[:params]["courtId"] }).to eq([COURT_1, COURT_1.sub(/1\z/, "2"), COURT_1.sub(/1\z/, "3")])
    expect(http.slot_requests.map { _1[:params]["courtId"] }).not_to include(COURT_4)
    expect(http.slot_requests.map { _1[:params]["durationMinutes"] }.uniq).to eq([60])
  end

  # Without them the API answers 400 `missing_header`, on every route.
  it "sends the two headers the club's own client always sends" do
    fetch

    expect(http.requests.map { _1[:headers] }.uniq).to eq([{ "X-Client" => "consumer", "Accept-Language" => "en" }])
  end

  it "drops the half-hour starts the source also offers" do
    expect(fetch.map { _1.local_starts_at.min }.uniq).to eq([0])
    expect(fetch.map(&:duration_minutes).uniq).to eq([60])
  end

  # "00:00" comes last in a day's list, after 23:30: it is tonight's midnight.
  it "files the midnight start on the morning after" do
    midnight = fetch.find { _1.court_ref == COURT_1 && _1.local_starts_at.hour.zero? }

    expect(midnight.local_date).to eq(Date.new(2026, 10, 15))
    # 00:00 in Tbilisi (+04:00) is 20:00 UTC the evening before.
    expect(midnight.starts_at).to eq(Time.utc(2026, 10, 14, 20, 0))
  end

  # The source greys out today's gone hours, but answers a past date as
  # entirely free, so the adapter checks the clock itself.
  it "drops hours that have already gone" do
    late = fetch(now: Booking::Clock.local_to_utc("2026-10-14 22:30"))

    expect(hours(late)).to contain_exactly(23, 0)
  end

  it "carries the club's configured price and booking link" do
    expect(fetch.first.price).to eq("60 GEL")
    expect(fetch.first.deeplink).to eq("https://aiapadel.ge/book")
  end

  # The slots route answers any date at all, free; the days list is the
  # club's real window, ten dates from the 13th.
  it "asks only for the dates the club lists as bookable, however long a range it is given" do
    fetch(Date.new(2026, 10, 13)..Date.new(2026, 12, 31))

    expect(http.slot_requests.map { _1[:params]["date"] }.uniq).to eq((Date.new(2026, 10, 13)..Date.new(2026, 10, 22)).map(&:to_s))
  end

  context "when the club's window is configured shorter than its list" do
    let(:settings) { super().merge("max_days" => 2) }

    it "stops at the configured window" do
      fetch(Date.new(2026, 10, 13)..Date.new(2026, 12, 31))

      expect(http.slot_requests.map { _1[:params]["date"] }.uniq).to eq(%w[2026-10-13 2026-10-14])
    end
  end

  describe "when a date is listed as closed" do
    let(:http) do
      FakeAiapadelHttp.new(days: [{ "date" => "2026-10-13", "isAvailable" => true }, { "date" => "2026-10-14", "isAvailable" => false }])
    end

    it "does not ask for its starts" do
      fetch(Date.new(2026, 10, 13)..Date.new(2026, 10, 14))

      expect(http.slot_requests.map { _1[:params]["date"] }.uniq).to eq(["2026-10-13"])
    end
  end

  it "reads the dates and courts once per tick, not once per date" do
    fetch(Date.new(2026, 10, 13)..Date.new(2026, 10, 15))

    expect(http.requests.count { _1[:url].end_with?("/days") }).to eq(1)
    expect(http.requests.count { _1[:url].end_with?("/courts") }).to eq(1)
  end

  describe "when a day answers with an error body" do
    let(:http) { FakeAiapadelHttp.new(slots: ->(_) { { "code" => "invalid_parameter", "message" => "nope" } }) }

    it "treats it as an unreadable source" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable)
    end
  end

  # Read as the date asked for, another date's starts would move every slot.
  describe "when a day answers for a different date" do
    let(:http) { FakeAiapadelHttp.new(slots: ->(_) { { "date" => "2026-10-20", "slots" => [] } }) }

    it "treats it as an unreadable source" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable, /2026-10-14/)
    end
  end

  describe "when no court is active" do
    let(:http) { FakeAiapadelHttp.new(courts: [{ "id" => COURT_4, "name" => "Court 4", "isActive" => false }]) }

    it "treats it as an unreadable source rather than a club with nothing free" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable)
    end
  end

  describe "when the days list is not a list" do
    let(:http) { FakeAiapadelHttp.new(days: { "code" => "missing_header" }) }

    it "treats it as an unreadable source" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable)
    end
  end

  it "is what the registry builds for the `aiapadel` adapter" do
    expect(Booking::Adapters.build(club, http:)).to be_a(described_class)
  end
end
