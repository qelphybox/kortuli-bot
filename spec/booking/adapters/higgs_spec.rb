require "json"

# Answers from recorded copies of the real API for 2026-10-13: the court list,
# and each court's own day. Court 1 was booked at 13:00, 14:00 and 21:00; the
# other two stood empty all day.
class FakeHiggsHttp
  attr_reader :requests

  def initialize(courts: nil, availability: nil)
    recorded = JSON.parse(File.read("spec/fixtures/higgs_availability.json", encoding: "UTF-8"))
    @courts = courts || recorded["courts"]
    @availability = availability || recorded["availability"]
    @requests = []
  end

  def get_json(url, params = {})
    @requests << { url:, params: }
    return @courts if url.end_with?("/courts")

    @availability.respond_to?(:call) ? @availability.call(params) : @availability.fetch(params["courtId"])
  end
end

RSpec.describe Booking::Adapters::Higgs do
  let(:http) { FakeHiggsHttp.new }
  let(:club) do
    Booking::Club.new(
      slug: "higgs",
      name: "Higgs",
      adapter: "higgs",
      settings: {
        "booking_url" => "https://higgs.ge/booking",
        "price" => "30–60 GEL",
        "courts" => 3,
        "max_days" => 7
      }
    )
  end
  let(:one_day) { Date.new(2026, 10, 13)..Date.new(2026, 10, 13) }
  let(:before_the_day) { Booking::Clock.local_to_utc("2026-10-12 12:00") }
  let(:court_one) { "a2af1b1e-582b-430f-91cf-879fdee74735" }
  let(:whole_club) { "ce5f18a4-2ac9-4972-ab6f-3c609e2544dc" }

  def fetch(range = one_day, now: before_the_day)
    described_class.new(club, http:, clock: Struct.new(:now).new(now)).fetch(range)
  end

  def hours(slots, court) = slots.select { _1.court_ref == court }.map { _1.local_starts_at.hour }

  # Sixteen hourly starts a day, 08:00 to 23:00, on three courts — less the
  # three hours booked on court 1.
  it "returns one slot per free hour per court" do
    expect(fetch.size).to eq((16 * 3) - 3)
  end

  it "leaves out the hours the source no longer lists" do
    expect(hours(fetch, court_one)).not_to include(13, 14, 21)
    expect(hours(fetch, court_one)).to include(12, 15, 20, 22)
  end

  # The list also names the whole venue as a bookable "court", 08:00–16:00 at
  # 250 GEL; the club's own client hides it, and so must we.
  it "asks only about the real courts, never the whole-club entry" do
    fetch

    asked = http.requests.reject { _1[:url].end_with?("/courts") }.map { _1[:params]["courtId"] }
    expect(asked.size).to eq(3)
    expect(asked).not_to include(whole_club)
  end

  it "skips a court the club has switched off" do
    courts = JSON.parse(File.read("spec/fixtures/higgs_availability.json"))["courts"]
    courts.find { _1["id"] == court_one }["isActive"] = false

    slots = described_class.new(club, http: FakeHiggsHttp.new(courts:), clock: Struct.new(:now).new(before_the_day))
                           .fetch(one_day)

    expect(slots.map(&:court_ref).uniq).not_to include(court_one)
  end

  it "reports the individual court under the club's own name for it" do
    slot = fetch.find { _1.court_ref == court_one }

    expect(slot.court_label).to eq("Court 1")
  end

  it "asks for each court's day by date, naming the hour-long duration" do
    fetch

    asked = http.requests.reject { _1[:url].end_with?("/courts") }
    expect(asked.map { _1[:url] }.uniq).to eq(["https://higgs.ge/api/bookings/available-slots"])
    expect(asked.map { _1[:params]["durationMinutes"] }.uniq).to eq([60])
    expect(asked.map { _1[:params]["date"] }.uniq).to eq(["2026-10-13"])
  end

  it "normalises the club's wall-clock into UTC at the boundary" do
    eight = fetch.find { _1.court_ref == court_one && _1.local_starts_at.hour == 8 }

    # 08:00 in Tbilisi (+04:00) is 04:00 UTC.
    expect(eight.starts_at).to eq(Time.utc(2026, 10, 13, 4, 0))
    expect(eight.ends_at).to eq(Time.utc(2026, 10, 13, 5, 0))
  end

  # Recorded at 23:03 local: the day's 08:00 was still on offer.
  it "drops hours that have already gone" do
    late = fetch(now: Booking::Clock.local_to_utc("2026-10-13 20:30"))

    expect(hours(late, court_one)).to eq([22, 23])
  end

  describe "when an hour is held or taken rather than free" do
    let(:http) do
      FakeHiggsHttp.new(availability: lambda do |_|
        {
          "date" => "2026-10-13T00:00:00",
          "timeSlots" => [
            { "startTime" => "2026-10-13T18:00:00", "status" => 0 },
            { "startTime" => "2026-10-13T19:00:00", "status" => 1 },
            { "startTime" => "2026-10-13T20:00:00", "status" => 2 }
          ]
        }
      end)
    end

    # Pending is somebody at checkout; only Available can be booked.
    it "keeps only the available one" do
      expect(fetch.map { _1.local_starts_at.hour }.uniq).to eq([18])
    end
  end

  it "carries the club's configured price and booking link" do
    expect(fetch.first.price).to eq("30–60 GEL")
    expect(fetch.first.deeplink).to eq("https://higgs.ge/booking")
  end

  # Nothing on the server stops at a window; every far date reads free.
  it "stops at the club's configured window, however long a range it is given" do
    fetch(Date.new(2026, 10, 13)..Date.new(2026, 12, 31))

    expect(http.requests.count { _1[:url].end_with?("/available-slots") }).to eq(7 * 3)
  end

  it "reads the court list once per tick, not once per date" do
    fetch(Date.new(2026, 10, 13)..Date.new(2026, 10, 15))

    expect(http.requests.count { _1[:url].end_with?("/courts") }).to eq(1)
  end

  describe "when a court's day answers with an error instead of slots" do
    let(:http) { FakeHiggsHttp.new(availability: ->(_) { ["Court not found"] }) }

    it "treats it as an unreadable source" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable, /timeSlots/)
    end
  end

  describe "when the court list holds nothing but the whole-club entry" do
    let(:http) do
      courts = JSON.parse(File.read("spec/fixtures/higgs_availability.json"))["courts"]
      FakeHiggsHttp.new(courts: courts.select { _1["id"] == "ce5f18a4-2ac9-4972-ab6f-3c609e2544dc" })
    end

    it "treats it as an unreadable source rather than a club with nothing free" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable)
    end
  end

  it "is what the registry builds for the `higgs` adapter" do
    expect(Booking::Adapters.build(club, http:)).to be_a(described_class)
  end
end
