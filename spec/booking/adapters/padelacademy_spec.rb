require "json"

# Answers from a recorded copy of the club's real answers for 2026-10-12, one
# list of free starts per court. The login is faked: the token is whatever the
# example says it is, and so is whether the server still accepts it.
class FakePadelacademyHttp
  attr_reader :requests, :logins

  def initialize(check: nil, token: "token-1", refuse: [])
    @check = check || JSON.parse(File.read("spec/fixtures/padelacademy_check.json"))
    @token = token
    @refuse = refuse
    @requests = []
    @logins = 0
  end

  def post_json(url, body = {}, headers: {})
    @requests << { url:, body:, headers: }
    return login if url.end_with?("/login")

    bearer = headers["Authorization"].to_s.delete_prefix("Bearer ")
    raise Booking::Adapters::Unauthorized, "#{url} returned 401" if @refuse.include?(bearer)

    @check.dig(body["date"], body["court"]) || []
  end

  private

  def login
    @logins += 1
    { "token" => "#{@token}-#{@logins}", "user" => { "id" => 1 } }
  end
end

RSpec.describe Booking::Adapters::Padelacademy do
  let(:http) { FakePadelacademyHttp.new }
  let(:credentials) { { email: "bot@example.test", password: "secret" } }
  let(:tokens) { {} }
  let(:club) do
    Booking::Club.new(
      slug: "padel-academy",
      name: "Padel Academy",
      adapter: "padelacademy",
      settings: {
        "booking_url" => "https://booking.padelacademy.ge/",
        "price" => "80 GEL",
        "opening_hours" => { "from" => "08:00", "to" => "02:00" },
        "courts" => 3
      }
    )
  end
  let(:one_day) { Date.new(2026, 10, 12)..Date.new(2026, 10, 12) }
  let(:before_the_day) { Booking::Clock.local_to_utc("2026-10-11 12:00") }

  def adapter(now: before_the_day, credentials: self.credentials)
    described_class.new(club, http:, credentials:, tokens:, clock: Struct.new(:now).new(now))
  end

  def fetch(range = one_day, **) = adapter(**).fetch(range)

  # 8 + 11 + 8 starts recorded across the three courts that day.
  it "returns one slot per free hour per court" do
    expect(fetch.size).to eq(27)
  end

  it "reports the individual court" do
    labels = fetch.select { _1.local_starts_at.hour == 9 }.map(&:court_label)

    expect(labels).to eq(["Court 2"])
  end

  # The source lists only what is free; a booked hour is simply absent.
  it "leaves out the hours nobody can book" do
    hours = fetch.select { _1.court_ref == "1" }.map { _1.local_starts_at.hour }

    expect(hours).to eq([8, 14, 15, 16, 17, 23, 0, 1])
  end

  # Verified live at 00:55 on the 11th: the 10th still offered "01:00", so the
  # small hours are filed under the evening before, as at Kus Tba.
  it "files 00:00 and 01:00 on the next calendar day" do
    late = fetch.select { _1.court_ref == "1" && _1.local_starts_at.hour < 8 }

    expect(late.map(&:local_date).uniq).to eq([Date.new(2026, 10, 13)])
    expect(late.map(&:starts_at)).to eq([Time.utc(2026, 10, 12, 20, 0), Time.utc(2026, 10, 12, 21, 0)])
  end

  it "asks each court by its number" do
    fetch

    checks = http.requests.reject { _1[:url].end_with?("/login") }
    expect(checks.map { _1.dig(:body, "court") }).to eq(%w[1 2 3])
    expect(checks.map { _1.dig(:body, "date") }.uniq).to eq(["2026-10-12"])
  end

  it "drops hours that have already started" do
    hours = fetch(now: Booking::Clock.local_to_utc("2026-10-12 16:30"))
            .select { _1.court_ref == "1" }.map { _1.local_starts_at.hour }

    expect(hours).to eq([17, 23, 0, 1])
  end

  describe "the session" do
    it "logs in once and sends the token it got" do
      fetch

      expect(http.logins).to eq(1)
      expect(http.requests.last[:headers]).to include("Authorization" => "Bearer token-1-1")
    end

    # The poller builds a new adapter every tick; logging in each time would
    # mean a login every four minutes.
    it "keeps the token across adapters" do
      fetch
      fetch

      expect(http.logins).to eq(1)
    end

    context "when the server stops accepting the token" do
      let(:tokens) { { "bot@example.test" => "expired" } }
      let(:http) { FakePadelacademyHttp.new(refuse: ["expired"]) }

      it "logs in again and carries on" do
        expect(fetch.size).to eq(27)
        expect(http.logins).to eq(1)
        expect(tokens).to eq("bot@example.test" => "token-1-1")
      end
    end

    context "when a fresh login is refused too" do
      let(:http) { FakePadelacademyHttp.new(refuse: ["token-1-1", "token-1-2"]) }

      it "fails the tick rather than retrying forever" do
        expect { fetch }.to raise_error(Booking::Adapters::Unauthorized)
        expect(http.logins).to eq(2)
      end
    end

    it "fails the tick, without asking anything, when no credentials are set" do
      expect { fetch(credentials: nil) }
        .to raise_error(Booking::Adapters::SourceUnavailable, /PADEL_ACADEMY_EMAIL/)
      expect(http.requests).to be_empty
    end

    it "fails the tick when the login answers without a token" do
      def http.post_json(*, **) = { "message" => "These credentials do not match our records." }

      expect { fetch }.to raise_error(Booking::Adapters::SourceUnavailable, /no token/)
    end
  end

  # An error body would otherwise read as a court with nothing free.
  it "fails the tick when the check answers with something other than a list" do
    http = FakePadelacademyHttp.new(check: { "2026-10-12" => { "1" => { "message" => "Server Error" } } })

    expect { described_class.new(club, http:, credentials:, tokens:).fetch(one_day) }
      .to raise_error(Booking::Adapters::SourceUnavailable, /expected a list of hours/)
  end

  it "stops at the club's max_days" do
    capped = club.with(settings: club.settings.merge("max_days" => 2))
    described_class.new(capped, http:, credentials:, tokens:).fetch(Date.new(2026, 10, 12)..Date.new(2026, 10, 18))

    dates = http.requests.filter_map { _1.dig(:body, "date") }.uniq
    expect(dates).to eq(%w[2026-10-12 2026-10-13])
  end
end
