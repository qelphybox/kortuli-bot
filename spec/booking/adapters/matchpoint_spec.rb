require "json"

# Answers from recorded copies of booking.padelisland.ge as served in the
# small hours of 2026-10-14, Tbilisi time, to a visitor with no login: the
# grid page, trimmed to its key and venue list, and `ObtenerCuadro` for Lisi
# Lake (6), Kachreti (7) and EXPO (8) on the 14th and 15th. EXPO's roofed
# court was busy most of the 14th; Lisi's court 19 was booked 20:00–22:00;
# Kachreti had nothing booked, its nights blocked 00:00–07:00.
class FakeMatchpointHttp
  BLANK = { "d" => { "__type" => "Matchpoint.Web.Library.Views.CuadroReservasNuevo", "Id" => 0, "Nombre" => nil, "StrFecha" => nil, "Columnas" => nil } }.freeze

  attr_reader :requests

  # `blank` is how many grid calls in a row to answer the way the server
  # answers a dead session: 200, and an empty grid.
  def initialize(page: nil, grids: nil, blank: 0, cookie: "ASP.NET_SessionId=mwill2bxsrdt3vhu2zxoitmp")
    # Read as bytes, the way a body comes off the wire.
    @page = page || File.binread("spec/fixtures/matchpoint_grid.html")
    @grids = grids || JSON.parse(File.read("spec/fixtures/matchpoint_cuadros.json", encoding: "UTF-8"))
    @blank = blank
    @cookie = cookie
    @requests = []
  end

  def get_page(url, params = {})
    @requests << { url:, params: }
    [@page, @cookie]
  end

  def post_json(url, body = {}, headers: {})
    @requests << { url:, body:, headers: }
    if @blank.positive?
      @blank -= 1
      return BLANK
    end

    @grids.dig(body["idCuadro"].to_s, body["fecha"]) || BLANK
  end

  def pages = requests.count { _1[:url].end_with?("/Booking/Grid.aspx") }

  def posts = requests.select { _1.key?(:body) }
end

RSpec.describe Booking::Adapters::Matchpoint do
  let(:http) { FakeMatchpointHttp.new }
  let(:sessions) { {} }
  let(:grids) { JSON.parse(File.read("spec/fixtures/matchpoint_cuadros.json", encoding: "UTF-8")) }

  def club(cuadro_id, courts:, from:, to:, slug: "padel-island-#{cuadro_id}")
    Booking::Club.new(
      slug:,
      name: "Padel Island #{cuadro_id}",
      adapter: "matchpoint",
      settings: {
        "cuadro_id" => cuadro_id,
        "price" => "40–80 GEL",
        "opening_hours" => { "from" => from, "to" => to },
        "max_days" => 14,
        "courts" => courts
      }
    )
  end

  let(:expo) { club(8, courts: 2, from: "07:00", to: "02:00") }
  let(:the_14th) { Date.new(2026, 10, 14)..Date.new(2026, 10, 14) }
  let(:before_the_day) { Booking::Clock.local_to_utc("2026-10-13 12:00") }

  def fetch(range = the_14th, club: expo, now: before_the_day)
    described_class.new(club, http:, sessions:, clock: Struct.new(:now).new(now)).fetch(range)
  end

  def hours(slots, court) = slots.select { _1.court_ref == court }.map { _1.local_starts_at.hour }

  describe "a venue's day" do
    # Nineteen starts, 07:00 to 01:00, on two courts — less five booked hours
    # on the open court and twelve on the roofed one.
    it "returns the day's grid minus what is booked" do
      expect(fetch.size).to eq((19 * 2) - 5 - 12)
    end

    it "leaves out every hour a booking covers" do
      expect(hours(fetch, "27")).to eq([11, 16, 17, 19, 23, 0, 1])
    end

    # A half-hour grid: 08:30–09:30 and 09:30–11:00 leave no whole hour from
    # 08:00 to 11:00, and 22:00–23:30 on the 15th takes 23:00 as well.
    it "counts a booking that covers part of an hour as taking it" do
      expect(hours(fetch, "26")).not_to include(8, 9, 10)
      expect(hours(fetch, "26")).to include(7, 11)
      expect(hours(fetch(Date.new(2026, 10, 15)..Date.new(2026, 10, 15)), "27")).not_to include(22, 23)
    end

    # EXPO sells 00:00 and 01:00 as the end of the day before.
    it "files the small hours on the following calendar day" do
      late = fetch.find { _1.court_ref == "26" && _1.local_starts_at.hour == 1 }

      expect(late.local_date).to eq(Date.new(2026, 10, 15))
      # 01:00 in Tbilisi (+04:00) is 21:00 UTC the evening before.
      expect(late.starts_at).to eq(Time.utc(2026, 10, 14, 21, 0))
    end

    # The `/Date(ms)/` beside it says 18:00 UTC: Madrid's clock, not Tbilisi's.
    it "reads a booking's hours off its wall clock, not its timestamp" do
      expect(hours(fetch, "26")).not_to include(20, 21)
      expect(hours(fetch, "26")).to include(19, 22)
    end

    it "drops the hours that have already started" do
      slots = fetch(now: Booking::Clock.local_to_utc("2026-10-14 12:30"))

      expect(hours(slots, "26")).to eq([13, 14, 15, 16, 17, 18, 19, 22, 23, 0, 1])
    end
  end

  # Opening hours are declared, and may be wider than the venue's: the grid
  # says when it opens and shuts, and nothing outside that is free time.
  describe "the venue's own fence" do
    it "keeps to the grid's opening and closing whatever the club declares" do
      kachreti = club(7, courts: 4, from: "00:00", to: "24:00")

      expect(fetch(club: kachreti).map { _1.local_starts_at.hour }.uniq).to eq((8..22).to_a)
      expect(fetch(club: kachreti).size).to eq(15 * 4)
    end

    # Lisi shuts at 23:59, so a 23:00 start would be cut a minute short.
    it "leaves out an hour that would run past closing" do
      lisi = club(6, courts: 2, from: "07:00", to: "02:00")

      expect(hours(fetch(club: lisi), "20")).to eq((7..22).to_a)
      expect(hours(fetch(club: lisi), "19")).to eq((7..19).to_a + [22])
    end

    it "reads a day the venue has shut as nothing free" do
      grids["8"]["14/10/2026"]["d"]["FechaInhabil"] = true

      expect(described_class.new(expo, http: FakeMatchpointHttp.new(grids:), sessions:, clock: Struct.new(:now).new(before_the_day)).fetch(the_14th)).to be_empty
    end
  end

  describe "each slot" do
    let(:slot) { fetch.find { _1.court_ref == "27" } }

    it "names the court in the venue's own words" do
      expect(fetch.map(&:court_label).uniq).to contain_exactly("EXPO Park No Roof", "EXPO Park Roof")
    end

    it "is an hour long, with the club's price" do
      expect(slot.duration_minutes).to eq(60)
      expect(slot.price).to eq("40–80 GEL")
    end

    it "links to the grid opened on its venue" do
      expect(slot.deeplink).to eq("https://booking.padelisland.ge/Booking/Grid.aspx?id=8")
    end
  end

  describe "the session" do
    it "sends the page's key, its cookie and its own grid as the referrer" do
      fetch

      post = http.posts.first
      expect(post[:body]).to eq("idCuadro" => 8, "fecha" => "14/10/2026", "key" => "eNEe29kXfZCtn7QRgxJJSngai8F3UoJj721u4qsZdcQ=")
      expect(post[:headers]).to eq("Cookie" => "ASP.NET_SessionId=mwill2bxsrdt3vhu2zxoitmp", "Referer" => "https://booking.padelisland.ge/Booking/Grid.aspx")
    end

    # Four venues, one page: a session is opened once, not once per club.
    it "opens one session for every venue and every date" do
      fetch(Date.new(2026, 10, 14)..Date.new(2026, 10, 15))
      fetch(club: club(7, courts: 4, from: "08:00", to: "23:00"))

      expect(http.pages).to eq(1)
      expect(http.posts.size).to eq(3)
    end

    # A dead session is not refused; it is answered with an empty grid.
    it "opens a fresh session when an answer comes back blank, and asks again" do
      http = FakeMatchpointHttp.new(blank: 1)
      slots = described_class.new(expo, http:, sessions:, clock: Struct.new(:now).new(before_the_day)).fetch(the_14th)

      expect(slots.size).to eq(21)
      expect(http.pages).to eq(2)
    end

    it "gives up for the tick when the fresh session is answered blank too" do
      http = FakeMatchpointHttp.new(blank: 2)
      adapter = described_class.new(expo, http:, sessions:, clock: Struct.new(:now).new(before_the_day))

      expect { adapter.fetch(the_14th) }.to raise_error(Booking::Adapters::SourceUnavailable, /blank grid/)
    end

    # An answer about another grid or date is as good as blank.
    it "does not believe an answer about some other date" do
      grids["8"]["14/10/2026"] = grids["8"]["15/10/2026"]
      adapter = described_class.new(expo, http: FakeMatchpointHttp.new(grids:), sessions:, clock: Struct.new(:now).new(before_the_day))

      expect { adapter.fetch(the_14th) }.to raise_error(Booking::Adapters::SourceUnavailable)
    end

    it "refuses a venue the page does not offer, without asking about it" do
      adapter = described_class.new(club(9, courts: 2, from: "07:00", to: "02:00"), http:, sessions:)

      expect { adapter.fetch(the_14th) }.to raise_error(Booking::Adapters::SourceUnavailable, /grid 9 is not on the booking page \(it offers 5, 6, 7, 8\)/)
      expect(http.posts).to be_empty
    end

    it "fails for the tick when the page has no key on it" do
      page = File.read("spec/fixtures/matchpoint_grid.html", encoding: "UTF-8").sub(/hl90njda2b89k='[^']*';/, "")
      adapter = described_class.new(expo, http: FakeMatchpointHttp.new(page:), sessions:)

      expect { adapter.fetch(the_14th) }.to raise_error(Booking::Adapters::SourceUnavailable, /no grid key/)
    end
  end

  # Past its horizon the server answers blank, like a dead session — so a
  # date past the one every answer names is never asked about.
  it "never asks about a date past the grid's horizon" do
    grids["8"]["14/10/2026"]["d"]["StrFechaMax"] = "14/10/2026"
    http = FakeMatchpointHttp.new(grids:)

    described_class.new(expo, http:, sessions:, clock: Struct.new(:now).new(before_the_day)).fetch(Date.new(2026, 10, 14)..Date.new(2026, 10, 20))

    expect(http.posts.map { _1[:body]["fecha"] }).to eq(["14/10/2026"])
  end

  it "asks about no more dates than max_days" do
    short = expo.with(settings: expo.settings.merge("max_days" => 1))

    fetch(Date.new(2026, 10, 14)..Date.new(2026, 10, 15), club: short)

    expect(http.posts.size).to eq(1)
  end

  # Inverted, a grid without its bookings is every court free all day.
  it "refuses a court whose bookings are missing rather than reading it as free" do
    grids["8"]["14/10/2026"]["d"]["Columnas"][0].delete("Ocupaciones")
    adapter = described_class.new(expo, http: FakeMatchpointHttp.new(grids:), sessions:, clock: Struct.new(:now).new(before_the_day))

    expect { adapter.fetch(the_14th) }.to raise_error(Booking::Adapters::SourceUnavailable, /no courts with bookings/)
  end

  it "reports a redesigned grid as the source being unavailable" do
    grids["8"]["14/10/2026"]["d"].delete("StrHoraAperturaCentro")
    adapter = described_class.new(expo, http: FakeMatchpointHttp.new(grids:), sessions:, clock: Struct.new(:now).new(before_the_day))

    expect { adapter.fetch(the_14th) }.to raise_error(Booking::Adapters::SourceUnavailable, /unreadable grid 8/)
  end
end
