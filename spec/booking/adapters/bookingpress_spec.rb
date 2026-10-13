require "json"

# Answers from recorded copies of tbilisipadel.ge as served 2026-10-13: the
# booking form's page, trimmed to its JSON island, and `month-details` for
# three services. Didi Dighomi (6) had one court booked at 09:00 on the 14th
# and at 19:00 and 20:00 on the 15th, and its evenings shut from 19:00 the week
# of the 26th; Ilia's Garden (1) was booked 18:00–23:00 on the 14th.
class FakeBookingpressHttp
  attr_reader :requests

  # `refuse` is how many POSTs in a row to turn away as a stale nonce would be.
  def initialize(page: nil, months: nil, refuse: 0)
    # Read as bytes, the way a body comes off the wire.
    @page = page || File.binread("spec/fixtures/bookingpress_form.html")
    @months = months || JSON.parse(File.read("spec/fixtures/bookingpress_month_details.json"))
    @refuse = refuse
    @requests = []
  end

  def get_body(url, params = {})
    @requests << { url:, params: }
    @page
  end

  def post_json(url, body = {}, headers: {})
    @requests << { url:, body:, headers: }
    if @refuse.positive?
      @refuse -= 1
      raise Booking::Adapters::SourceUnavailable, "#{url} returned 403"
    end
    return @months.call(body) if @months.respond_to?(:call)

    month = format("%04d-%02d", body["selected_year"], body["selected_month"])
    @months.dig(body["service_id"].to_s, month) || { "ok" => true, "data" => { "working_details" => [] } }
  end

  def pages = requests.count { _1[:url].end_with?("/en/") }

  def posts = requests.select { _1.key?(:body) }
end

RSpec.describe Booking::Adapters::Bookingpress do
  let(:http) { FakeBookingpressHttp.new }
  let(:sessions) { {} }
  let(:didi_dighomi) do
    Booking::Club.new(
      slug: "tbilisi-padel-didi-dighomi",
      name: "Tbilisi Padel Didi Dighomi",
      adapter: "bookingpress",
      settings: {
        "service_id" => 6,
        "booking_url" => "https://tbilisipadel.ge/en/",
        "price" => "60 GEL",
        "opening_hours" => { "from" => "09:00", "to" => "02:00" },
        "max_days" => 14,
        "courts" => 4
      }
    )
  end
  let(:ilias_garden) do
    Booking::Club.new(
      slug: "tbilisi-padel-ilias-garden",
      name: "Tbilisi Padel Ilia's Garden",
      adapter: "bookingpress",
      settings: {
        "service_id" => 1,
        "booking_url" => "https://tbilisipadel.ge/en/",
        "price" => "60 GEL",
        "opening_hours" => { "from" => "09:00", "to" => "24:00" },
        "max_days" => 14
      }
    )
  end
  let(:club) { didi_dighomi }
  let(:the_14th) { Date.new(2026, 10, 14)..Date.new(2026, 10, 14) }
  let(:before_the_day) { Booking::Clock.local_to_utc("2026-10-13 12:00") }

  def adapter(club = self.club, now: before_the_day)
    described_class.new(club, http:, sessions:, clock: Struct.new(:now).new(now))
  end

  def fetch(range = the_14th, club: self.club, now: before_the_day) = adapter(club, now:).fetch(range)

  def at(slots, hour) = slots.select { _1.local_starts_at.hour == hour }

  describe "a location with several courts" do
    # Seventeen starts, 09:00 to 01:00, on four courts — less the one court
    # booked at 09:00.
    it "returns one slot per free court per hour" do
      expect(fetch.size).to eq((17 * 4) - 1)
    end

    # The source counts the free courts but never names them, so the refs are
    # a count the Grid can read as "3 of 4", not a court a person can find.
    it "counts the free courts under numbered refs, and names none of them" do
      expect(at(fetch, 9).map(&:court_ref)).to contain_exactly("1", "2", "3")
      expect(at(fetch, 10).map(&:court_ref)).to contain_exactly("1", "2", "3", "4")
      expect(fetch.map(&:court_label).uniq).to eq(["A court"])
    end

    it "never counts more free courts than the club declares" do
      capped = club.with(settings: club.settings.merge("courts" => 2))

      expect(at(fetch(club: capped), 10).size).to eq(2)
    end

    # 00:00 and 01:00 are sold under the date before, and `store_service_date`
    # says which night they really fall on.
    it "files the small hours on the calendar date the source gives them" do
      one = at(fetch, 1).first

      expect(one.local_date).to eq(Date.new(2026, 10, 15))
      # 01:00 in Tbilisi (+04:00) is 21:00 UTC the evening before.
      expect(one.starts_at).to eq(Time.utc(2026, 10, 14, 21, 0))
    end

    # That rollover is also why a business day's last hours land in the next
    # month without a second request for it.
    it "keeps a month's last night with the month it was sold under" do
      slots = fetch(Date.new(2026, 10, 31)..Date.new(2026, 10, 31))

      expect(at(slots, 1).first.local_date).to eq(Date.new(2026, 11, 1))
      expect(http.posts.size).to eq(1)
    end
  end

  describe "a single-court location" do
    let(:club) { ilias_garden }

    it "reports the hour, not a court" do
      expect(fetch.map(&:court_ref).uniq).to eq(["any"])
      expect(fetch.map(&:court_label).uniq).to eq(["A court"])
    end

    # Presence is the whole signal: a booked hour is a missing row.
    it "returns exactly the hours the source lists" do
      expect(fetch.map { _1.local_starts_at.hour }).to eq([9, 10, 11, 12, 13, 14, 15, 16, 17, 23])
    end
  end

  it "makes hour-long slots on the hour, at the configured price and link" do
    slot = fetch.first

    expect(fetch.map(&:duration_minutes).uniq).to eq([60])
    expect(fetch.map { _1.local_starts_at.min }.uniq).to eq([0])
    expect(slot.price).to eq("60 GEL")
    expect(slot.deeplink).to eq("https://tbilisipadel.ge/en/")
  end

  describe "when the source offers a half-hour start" do
    let(:http) do
      FakeBookingpressHttp.new(months: lambda do |_|
        rows = %w[09:00 09:30].map { { "start_time" => _1, "is_available" => 1, "remaining_capacity" => 1 } }
        { "ok" => true, "data" => { "working_details" => { "2026-10-14" => rows } } }
      end)
    end

    # None seen yet; the Grid matches a Cell on an hourly start, so one would
    # notify and then be drawn nowhere.
    it "drops it" do
      expect(fetch(club: ilias_garden).map { _1.local_starts_at.strftime("%H:%M") }).to eq(["09:00"])
    end
  end

  it "drops hours that have already gone" do
    late = fetch(now: Booking::Clock.local_to_utc("2026-10-14 22:30"))

    expect(late.map { _1.local_starts_at.hour }.uniq).to contain_exactly(23, 0, 1)
  end

  it "asks once per month, not once per date" do
    fetch(Date.new(2026, 10, 30)..Date.new(2026, 11, 2))

    expect(http.posts.map { _1[:body].slice("from_date", "selected_year", "selected_month") }).to eq([
      { "from_date" => "2026-10-01", "selected_year" => 2026, "selected_month" => 10 },
      { "from_date" => "2026-11-01", "selected_year" => 2026, "selected_month" => 11 }
    ])
    expect(http.posts.map { _1[:body]["service_id"] }.uniq).to eq([6])
  end

  it "reads only the dates it was asked about out of a month" do
    expect(fetch.map(&:local_date).uniq).to contain_exactly(Date.new(2026, 10, 14), Date.new(2026, 10, 15))
    expect(fetch.select { _1.local_date == Date.new(2026, 10, 15) }.map { _1.local_starts_at.hour }.uniq).to contain_exactly(0, 1)
  end

  # The form offers a year ahead and answers for all of it with empty courts.
  it "stops at the club's max_days" do
    capped = club.with(settings: club.settings.merge("max_days" => 2))
    slots = fetch(Date.new(2026, 10, 14)..Date.new(2026, 12, 31), club: capped)

    expect(http.posts.size).to eq(1)
    expect(slots.map(&:local_date).uniq.min).to eq(Date.new(2026, 10, 14))
  end

  describe "the tokens" do
    # Scraped from the island, never from the page's other "nonces" object.
    it "sends the ones the booking form was rendered with" do
      fetch

      post = http.posts.first
      expect(post[:headers]).to eq("X-WP-Nonce" => "c08d8e68c0")
      expect(post[:body]).to include(
        "bp_v3_nonce" => "3d730f36ca",
        "bp_v3_instance_token" => "CPcwmKjVU3LKfmlxeIsGCLyrNwo7TAxJ",
        "instanceId" => "b6ca0683d885"
      )
    end

    # Three locations share one form; scraping per adapter would fetch the
    # same page three times a tick.
    it "scrapes the form once for every location and every tick that follows" do
      fetch(club: didi_dighomi)
      fetch(club: ilias_garden)
      fetch(club: didi_dighomi)

      expect(http.pages).to eq(1)
      expect(http.posts.size).to eq(3)
    end

    describe "when the server refuses them once" do
      let(:http) { FakeBookingpressHttp.new(refuse: 1) }

      it "scrapes a fresh set and asks again" do
        expect(fetch.size).to eq((17 * 4) - 1)
        expect(http.pages).to eq(2)
        expect(http.posts.size).to eq(2)
      end
    end

    describe "when the server refuses the fresh ones too" do
      let(:http) { FakeBookingpressHttp.new(refuse: 2) }

      it "fails the tick after one retry" do
        expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable, /403/)
        expect(http.pages).to eq(2)
      end
    end

    # A 500 has already been retried by Http; a new set of tokens would not
    # change the server's mind.
    it "does not re-scrape for a failure that is not about them" do
      http = FakeBookingpressHttp.new
      def http.post_json(url, *, **) = raise(Booking::Adapters::SourceUnavailable, "#{url} returned 500")

      expect { described_class.new(club, http:, sessions:).fetch(the_14th) }.to raise_error(Booking::Adapters::SourceUnavailable, /500/)
      expect(http.pages).to eq(1)
    end
  end

  describe "when the source misbehaves" do
    # An unknown service is answered `ok` with an empty month — every hour
    # booked, as far as anyone downstream could tell.
    it "refuses to ask about a service the form does not offer" do
      gone = club.with(settings: club.settings.merge("service_id" => 99))

      expect { fetch(club: gone) }.to raise_error(Booking::Adapters::SourceUnavailable, /service 99 is not on the booking form/)
      expect(http.posts).to be_empty
    end

    it "fails the tick when the page carries no booking form" do
      http = FakeBookingpressHttp.new(page: "<html><body>Maintenance</body></html>")

      expect { described_class.new(club, http:, sessions:).fetch(the_14th) }
        .to raise_error(Booking::Adapters::SourceUnavailable, /no BookingPress form/)
    end

    it "fails the tick when the answer is not ok" do
      http = FakeBookingpressHttp.new(months: ->(_) { { "ok" => false, "error" => { "code" => "bp_v3_whatever" } } })

      expect { described_class.new(club, http:, sessions:).fetch(the_14th) }
        .to raise_error(Booking::Adapters::SourceUnavailable, /no working_details/)
    end

    # PHP serialises an empty month as a list; it is a month with nothing
    # left in it, not a broken answer.
    it "reads an empty month as nothing free rather than a failure" do
      expect(fetch(Date.new(2026, 12, 1)..Date.new(2026, 12, 2))).to eq([])
    end
  end

  it "is what the registry builds for the `bookingpress` adapter" do
    expect(Booking::Adapters.build(club, http:)).to be_a(described_class)
  end
end
