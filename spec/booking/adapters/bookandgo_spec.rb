require "json"

# Answers from a recorded copy of the real backend response, so the parsing
# stays pinned to what the platform actually sends. The recorded day holds all
# three Georgian clubs at once, because one request returns the whole tenant.
class FakeBookandgoHttp
  attr_reader :requests

  def initialize(payload: nil)
    @requests = []
    @payload = payload
  end

  def get_json(url, params = {})
    @requests << { url:, params: }
    @payload || JSON.parse(File.read("spec/fixtures/bookandgo_court_bookings.json"))
  end
end

# The source keeps offering hours that have already gone, so every example
# has to say when "now" is.
FakeClock = Struct.new(:now)

RSpec.describe Booking::Adapters::Bookandgo do
  subject(:adapter) { described_class.new(club, http:, clock: FakeClock.new(before_the_day)) }

  let(:http) { FakeBookandgoHttp.new }
  let(:club) do
    Booking::Club.new(
      slug: "padelbade-krtsanisi",
      name: "Padelbade Krtsanisi",
      adapter: "bookandgo",
      settings: {
        "location_id" => 163,
        "booking_url" => "https://app.padelbade.com/",
        "price" => "80 GEL",
        "courts" => 5,
        "max_days" => 22
      }
    )
  end
  let(:one_day) { Date.new(2026, 8, 2)..Date.new(2026, 8, 2) }
  # Well before the recorded day, so nothing is filtered as past unless an
  # example asks for it.
  let(:before_the_day) { Booking::Clock.local_to_utc("2026-08-01 12:00") }

  def fetch(range = one_day, now: before_the_day)
    described_class.new(club, http:, clock: FakeClock.new(now)).fetch(range)
  end

  # Krtsanisi's two recorded courts offer 00:00, 08:00, 09:00, 10:00 and
  # 08:00, 11:00 on the hour.
  it "returns one slot per free hour per court" do
    expect(fetch.size).to eq(6)
  end

  # The source names the court, so unlike Kus Tba this club can say which one.
  it "reports the individual court" do
    slot = fetch.find { _1.local_starts_at.hour == 11 }

    expect(slot.court_ref).to eq("704")
    expect(slot.court_label).to eq("Blue 2")
  end

  # `available_time_slots` is a whitelist of bookable starts — a taken hour is
  # absent rather than flagged, which is already the contract the differ wants.
  it "leaves out the hours nobody can book" do
    hours = fetch.select { _1.court_ref == "704" }.map { _1.local_starts_at.hour }

    expect(hours).to eq([8, 11])
  end

  # The response carries every club of the tenant in one payload, so the
  # adapter has to keep only its own. Dighomi and Rustavi are in the fixture.
  it "keeps only the club it was configured to watch" do
    expect(fetch.map(&:club_slug).uniq).to eq(["padelbade-krtsanisi"])
    expect(fetch.map(&:court_ref)).to all(match(/^70[34]$/))
  end

  # The same court and hour appears three times over, once per bookable
  # duration. Emitting all of them would hand the differ three overlapping
  # slots for one hour.
  it "takes the hour-long booking and ignores the 90- and 120-minute ones" do
    expect(fetch.map(&:duration_minutes).uniq).to eq([60])
    # On the recorded day 13:00 is offered only at 90 minutes, and 15:00 and
    # 16:00 only at 120 — all on a court whose hour-long row we do read.
    expect(fetch.map { _1.local_starts_at.hour }).not_to include(13, 15, 16)
  end

  # A Slot is one bookable *hour*, and the Grid draws one column per hour, so a
  # slot starting at 08:30 would match no cell and vanish from the app. Half-hour
  # starts are dropped here deliberately rather than silently lost downstream.
  it "drops the half-hour starts the source also offers" do
    expect(fetch.map { _1.local_starts_at.min }.uniq).to eq([0])
  end

  it "normalises the club's wall-clock into UTC at the boundary" do
    eight = fetch.find { _1.court_ref == "703" && _1.local_starts_at.hour == 8 }

    # 08:00 in Tbilisi (+04:00) is 04:00 UTC.
    expect(eight.starts_at).to eq(Time.utc(2026, 8, 2, 4, 0))
    expect(eight.starts_at.utc?).to be(true)
    expect(eight.ends_at).to eq(Time.utc(2026, 8, 2, 5, 0))
  end

  # The club runs past midnight, and unlike Kus Tba's feed this one files the
  # small hours under the calendar date they actually fall on. Taking the date
  # at its word is therefore correct — no rollover heuristic.
  it "keeps an after-midnight hour on the day the source dated it" do
    midnight = fetch.find { _1.local_starts_at.hour == 0 }

    expect(midnight.local_date).to eq(Date.new(2026, 8, 2))
  end

  # Verified live: at 02:09 local the feed still offered 00:00 and 00:30 for
  # that same day. Nothing else in the pipeline drops them, so the adapter must.
  it "drops hours that have already gone" do
    hours = fetch(now: Booking::Clock.local_to_utc("2026-08-02 09:30"))
            .map { _1.local_starts_at.hour }

    expect(hours).to contain_exactly(10, 11)
  end

  it "carries the club's configured price and booking link" do
    expect(fetch.first.price).to eq("80 GEL")
    expect(fetch.first.deeplink).to eq("https://app.padelbade.com/")
  end

  it "spends one request per date, naming only the date" do
    fetch(Date.new(2026, 8, 2)..Date.new(2026, 8, 4))

    expect(http.requests.size).to eq(3)
    expect(http.requests.map { _1[:params]["date"] }).to eq(%w[2026-08-02 2026-08-03 2026-08-04])
    expect(http.requests.map { _1[:url] }.uniq)
      .to eq(["https://api.bookandgo.app/api/v1/apps/58/court-bookings"])
  end

  # Out past the club's window the API returns an empty booking list rather
  # than phantom slots, so the cap is about not making pointless requests.
  it "stops at the club's own booking window, however long a range it is given" do
    fetch(Date.new(2026, 8, 2)..Date.new(2026, 9, 30))

    expect(http.requests.size).to eq(22)
  end

  describe "when the tenant answers without a booking list" do
    # A renamed field or a refusal wearing a 200 would otherwise parse cleanly
    # and read as the whole club being booked at once.
    let(:http) { FakeBookandgoHttp.new(payload: { "status" => "error", "message" => "invalid app" }) }

    it "treats it as an unreadable source" do
      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable)
    end
  end

  describe "when the day is genuinely sold out" do
    let(:http) { FakeBookandgoHttp.new(payload: { "data" => { "bookings" => [] } }) }

    it "returns nothing and leaves the empty-response guard to the differ" do
      expect(fetch).to eq([])
    end
  end

  it "refuses to run without the location it is meant to watch" do
    bare = Booking::Club.new(slug: "x", name: "X", adapter: "bookandgo", settings: {})

    expect { described_class.new(bare, http:) }.to raise_error(KeyError)
  end

  # The documented contract is `fetch(date_range)`; the clock is a constructor
  # dependency so the poller keeps calling adapters the one documented way.
  it "reads the wall clock itself when nobody supplies one" do
    expect(described_class.new(club, http:).fetch(one_day))
      .to eq(fetch(now: Booking::Clock.now))
  end

  # Love Padel in Kutaisi is another tenant of the same platform, recorded on
  # 2026-10-14: two padel courts, and two pickleball courts filed under the
  # same location as variants of their own. Court 1 had 11:00 and 12:00
  # booked; court 2 stood empty.
  describe "on another tenant" do
    let(:http) do
      FakeBookandgoHttp.new(payload: JSON.parse(File.read("spec/fixtures/bookandgo_lovepadel_court_bookings.json", encoding: "UTF-8")))
    end
    let(:club) do
      Booking::Club.new(
        slug: "love-padel",
        name: "Love Padel",
        adapter: "bookandgo",
        settings: {
          "base_url" => "https://api.bookandgo.app/api/v1/apps/126",
          "location_id" => 246,
          "booking_url" => "https://book.lovepadel.ge/",
          "courts" => 2,
          "max_days" => 8
        }
      )
    end
    let(:one_day) { Date.new(2026, 10, 14)..Date.new(2026, 10, 14) }
    let(:before_the_day) { Booking::Clock.local_to_utc("2026-10-13 12:00") }

    it "asks that tenant rather than Padelbade's" do
      fetch

      expect(http.requests.map { _1[:url] }.uniq)
        .to eq(["https://api.bookandgo.app/api/v1/apps/126/court-bookings"])
    end

    # Seventeen hourly starts a court — 00:00, then 08:00 through 23:00 — less
    # court 1's two booked hours. The pickleball court beside them offers
    # seventeen more.
    it "reads only the padel courts, not the pickleball ones beside them" do
      expect(fetch.map(&:court_ref).uniq).to contain_exactly("938", "939")
      expect(fetch.size).to eq(15 + 17)
    end

    it "leaves out the hours nobody can book" do
      hours = fetch.select { _1.court_ref == "938" }.map { _1.local_starts_at.hour }

      expect(hours).not_to include(11, 12)
      expect(hours).to include(10, 13)
    end

    it "labels the court as the club does" do
      expect(fetch.find { _1.court_ref == "939" }.court_label).to eq("Court 2 (Blue)")
    end

    # Like Padelbade's, this tenant keeps offering hours that have gone.
    it "drops hours that have already gone" do
      late = fetch(now: Booking::Clock.local_to_utc("2026-10-14 21:30"))

      expect(late.select { _1.court_ref == "939" }.map { _1.local_starts_at.hour }).to eq([22, 23])
    end
  end
end
