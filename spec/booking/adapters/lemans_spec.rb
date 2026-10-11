require "json"

# Answers from recorded copies of the real API for 2026-10-12: the court list,
# and each court's own day. Court 1 was booked 21:00–00:00 and court 3
# 18:00–20:00; the other two stood empty all day.
class FakeLemansHttp
  attr_reader :requests

  def initialize(courts: nil, availability: nil)
    recorded = JSON.parse(File.read("spec/fixtures/lemans_availability.json", encoding: "UTF-8"))
    @courts = courts || recorded["courts"]
    @availability = availability || recorded["availability"]
    @requests = []
  end

  def get_json(url, params = {})
    @requests << { url:, params: }
    return @courts if url.end_with?("/courts")

    @availability.respond_to?(:call) ? @availability.call(params) : @availability.fetch(params["court_id"].to_s)
  end
end

RSpec.describe Booking::Adapters::Lemans do
  let(:http) { FakeLemansHttp.new }
  let(:club) do
    Booking::Club.new(
      slug: "lemans-padel",
      name: "Lemans Padel",
      adapter: "lemans",
      settings: {
        "booking_url" => "https://lemanspadel.ge/book-padel/",
        "price" => "70 GEL",
        "courts" => 4,
        "max_days" => 14
      }
    )
  end
  let(:one_day) { Date.new(2026, 10, 12)..Date.new(2026, 10, 12) }
  let(:before_the_day) { Booking::Clock.local_to_utc("2026-10-11 12:00") }

  def fetch(range = one_day, now: before_the_day)
    described_class.new(club, http:, clock: Struct.new(:now).new(now)).fetch(range)
  end

  def hours(slots, court) = slots.select { _1.court_ref == court }.map { _1.local_starts_at.hour }

  # Eighteen hourly starts a day, 08:00 to 01:00, on four courts — less the
  # five hours booked that day.
  it "returns one slot per free hour per court" do
    expect(fetch.size).to eq((18 * 4) - 5)
  end

  it "leaves out the hours the source flags as taken" do
    expect(hours(fetch, "1")).not_to include(21, 22, 23)
    expect(hours(fetch, "3")).not_to include(18, 19)
    expect(hours(fetch, "3")).to include(17, 20)
  end

  # The source names the court, so this is a court-level club: a cancellation
  # on court 3 counts even while court 2 stood empty.
  it "reports the individual court, under an English label" do
    slot = fetch.find { _1.court_ref == "3" }

    expect(slot.court_label).to eq("Court 3")
  end

  it "asks each court for its own day, naming the hour-long duration" do
    fetch

    asked = http.requests.reject { _1[:url].end_with?("/courts") }
    expect(asked.map { _1[:params]["court_id"] }).to eq([1, 2, 3, 4])
    expect(asked.map { _1[:params]["duration"] }.uniq).to eq([60])
    expect(asked.map { _1[:params]["date"] }.uniq).to eq(["2026-10-12"])
  end

  it "drops the half-hour starts the source also offers" do
    expect(fetch.map { _1.local_starts_at.min }.uniq).to eq([0])
    expect(fetch.map(&:duration_minutes).uniq).to eq([60])
  end

  # `start_datetime` already dates 00:00 and 01:00 to the morning after, so
  # taking it at its word puts them where a person would look for them.
  it "files the small hours on the date the source gives them" do
    one = fetch.find { _1.court_ref == "2" && _1.local_starts_at.hour == 1 }

    expect(one.local_date).to eq(Date.new(2026, 10, 13))
    # 01:00 in Tbilisi (+04:00) is 21:00 UTC the evening before.
    expect(one.starts_at).to eq(Time.utc(2026, 10, 12, 21, 0))
  end

  it "drops hours that have already gone" do
    late = fetch(now: Booking::Clock.local_to_utc("2026-10-12 22:30"))

    expect(hours(late, "2")).to contain_exactly(23, 0, 1)
  end

  it "carries the club's configured price and booking link" do
    expect(fetch.first.price).to eq("70 GEL")
    expect(fetch.first.deeplink).to eq("https://lemanspadel.ge/book-padel/")
  end

  # Nothing on the server stops at a window; every far date reads free.
  it "stops at the club's configured window, however long a range it is given" do
    fetch(Date.new(2026, 10, 12)..Date.new(2026, 12, 31))

    expect(http.requests.count { _1[:url].end_with?("/availability") }).to eq(14 * 4)
  end

  it "reads the court list once per tick, not once per date" do
    fetch(Date.new(2026, 10, 12)..Date.new(2026, 10, 14))

    expect(http.requests.count { _1[:url].end_with?("/courts") }).to eq(1)
  end

  describe "when the source answers for the whole club instead of the court" do
    # The aggregate answer says whether *some* court is free; read as one
    # court's, every court would look free whenever any was.
    let(:http) do
      FakeLemansHttp.new(availability: ->(_) { { "court_id" => nil, "slots" => [] } })
    end

    it "treats it as an unreadable source" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable, /court 1/)
    end
  end

  describe "when the day answers without a list of slots" do
    let(:http) do
      FakeLemansHttp.new(availability: ->(params) { { "court_id" => params["court_id"], "error" => "nope" } })
    end

    it "treats it as an unreadable source" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable)
    end
  end

  describe "when the court list comes back empty" do
    let(:http) { FakeLemansHttp.new(courts: { "courts" => [] }) }

    it "treats it as an unreadable source rather than a club with nothing free" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable)
    end
  end

  it "is what the registry builds for the `lemans` adapter" do
    expect(Booking::Adapters.build(club, http:)).to be_a(described_class)
  end
end
