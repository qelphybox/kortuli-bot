require "rack/test"
require "tmpdir"

# The day screens — the week, a date's clubs, one club's hours — on what
# their redesign added: how fresh the week is, a club we could not read told
# apart from a fully booked one, and whom the rain falls on. Set up as the
# app spec is: Clubs and Slots stood in for, everything the web reads or
# writes besides them real over an in-memory database.
RSpec.describe Booking::Web::App do
  include Rack::Test::Methods

  DayRepos = Struct.new(:clubs, :slots, :watches, :favourites, :forecast, :visits, :preferences, :polls)
  DayClubs = Struct.new(:enabled)
  DaySlots = Struct.new(:all)

  let(:token) { "123456:TEST-TOKEN-do-not-use" }
  let(:sessions) { Booking::Web::Session.new(secret: "a-secret-that-only-the-server-knows") }
  let(:db) { Booking::DB.connect("sqlite:/") }
  let(:polls) { Booking::Repo::Polls.new(db) }
  let(:forecast) { Booking::Repo::Forecast.new(db) }
  let(:today) { Booking::Clock.local_date(Booking::Clock.now) }
  let(:day) { today + 1 }

  def club(slug, name, city: nil)
    Booking::Club.new(
      slug:, name:, adapter: "reservio",
      settings: { "city" => city, "opening_hours" => { "from" => "08:00", "to" => "24:00" }, "price" => "80 GEL" }.compact
    )
  end

  let(:clubs) do
    [club("gldani", "Padel Gldani"), club("academy", "Padel Academy"), club("lemans", "Lemans Padel"),
     club("port", "Padel Port", city: "Batumi")]
  end
  let(:free_slots) { [slot(club: "gldani", at: "#{day} 18:00")] }
  let(:club_profiles) do
    {
      "gldani" => Booking::ClubProfile.from(
        { "source" => "https://sapadelo.com/georgia/clubs/padel-gldani", "area" => "Gldani",
          "courts" => [{ "name" => "1", "cover" => "covered" }, { "name" => "2", "cover" => "outdoor" }] },
        checked_on: "2026-10-11"
      ),
      "lemans" => Booking::ClubProfile.from(
        { "source" => "https://sapadelo.com/georgia/clubs/lemans", "area" => "Saburtalo",
          "courts" => [{ "name" => "1", "cover" => "indoor" }] },
        checked_on: "2026-10-11"
      )
    }
  end
  let(:repos) do
    DayRepos.new(DayClubs.new(clubs), DaySlots.new(free_slots), Booking::Repo::Watches.new(db), Booking::Repo::Favourites.new(db),
                 forecast, Booking::Repo::Visits.new(db), Booking::Repo::Preferences.new(db), polls)
  end

  def app
    described_class.tap do |a|
      a.set :telegram_token, token
      a.set :bot_username, "kortuli_test_bot"
      a.set :visitor_sessions, sessions
      a.set :repos, repos
      a.set :club_profiles, club_profiles
      a.set :owner_id, nil
      a.set :dashboard, nil
    end
  end

  def sign_in(user_id: 42)
    fields = { "auth_date" => Time.now.to_i.to_s, "user" => %({"id":#{user_id},"first_name":"Kirill"}) }
    check = fields.keys.sort.map { "#{_1}=#{fields[_1]}" }.join("\n")
    key = OpenSSL::HMAC.digest("SHA256", "WebAppData", token)
    fields["hash"] = OpenSSL::HMAC.hexdigest("SHA256", key, check)

    post "/auth", init_data: URI.encode_www_form(fields)
  end

  def ago(seconds) = Booking::Clock.now - seconds

  def cards = last_response.body.scan(%r{<li class="club-card[^"]*">.*?</li>}m)

  def card(name) = cards.find { _1.include?(%(<span class="club-row__name">#{name}</span>)) }.to_s

  def club_names_in_order = last_response.body.scan(%r{<span class="club-row__name">([^<]+)</span>}).flatten

  # Somebody who has picked a city: with more than one, `/` would otherwise
  # ask first, and these are about the week behind it.
  before do
    sign_in
    post "/city", city: "Tbilisi", back: "/"
  end

  describe "the week" do
    it "says how long ago the newest good Poll of the city's clubs finished" do
      polls.record("gldani", outcome: "ok", summary: "", at: ago(20 * 60))
      polls.record("lemans", outcome: "ok", summary: "", at: ago(4 * 60))
      get "/"

      expect(last_response.body).to include('<span class="section__aside">Updated 4 min ago</span>')
    end

    # A failed Poll read nothing, and Batumi's clubs are not this city's.
    it "counts neither a failed Poll nor another city's" do
      polls.record("gldani", outcome: "ok", summary: "", at: ago(3 * 3600))
      polls.record("academy", outcome: "failed", summary: "", at: ago(60))
      polls.record("port", outcome: "ok", summary: "", at: ago(60))
      get "/"

      expect(last_response.body).to include("Updated 3 h ago")
    end

    it "claims nothing before the first good Poll" do
      polls.record("academy", outcome: "failed", summary: "", at: ago(60))
      get "/"

      expect(last_response.body).not_to include("Updated")
    end

    it "draws each day's bar as a value rather than a style" do
      get "/"

      expect(last_response.body).to include(%(<progress class="meter-bar" max="100" value="100" aria-hidden="true">))
      expect(last_response.body).not_to include('style="width')
    end
  end

  describe "a date's clubs" do
    before do
      polls.record("gldani", outcome: "ok", summary: "", at: ago(60))
      polls.record("lemans", outcome: "ok", summary: "", at: ago(60))
      polls.record("academy", outcome: "failed", summary: "", at: ago(60))
    end

    it "names the city beside the date" do
      get "/date/#{day}"

      expect(last_response.body).to include(%(<span class="bar__date">#{day.strftime("%b %-d")} · Tbilisi</span>))
    end

    it "calls a club fully booked only when its last Poll read the source" do
      get "/date/#{day}"

      expect(card("Lemans Padel")).to include("Fully booked").and include("is-empty")
      expect(card("Lemans Padel")).not_to include("is-unknown")
    end

    it "says there is no data for a club whose last Poll failed" do
      get "/date/#{day}"

      expect(card("Padel Academy")).to include(%(<span class="club-card__booked">No data</span>)).and include("is-unknown")
      expect(card("Padel Academy")).not_to include("Fully booked")
    end

    it "says the same for a club that has never been polled" do
      db[:polls].where(club_slug: "academy").delete
      get "/date/#{day}"

      expect(card("Padel Academy")).to include("No data")
    end

    # What a failed Poll left behind is still the last thing we read.
    it "still shows the free hours a club had before its Poll failed" do
      polls.record("gldani", outcome: "failed", summary: "", at: ago(30))
      get "/date/#{day}"

      expect(card("Padel Gldani")).to include(%(<span class="club-card__left">1</span>))
      expect(card("Padel Gldani")).not_to include("No data")
    end

    it "lists the unknown after the fully booked, and counts only the open in All" do
      favourites = Booking::Repo::Favourites.new(db)
      favourites.add(42, "academy")
      get "/date/#{day}"

      expect(club_names_in_order).to eq(["Padel Gldani", "Lemans Padel", "Padel Academy"])
      expect(last_response.body).to include(">All 1</a>")
    end

    it "keeps the star a form of its own beside the club's link" do
      get "/date/#{day}"

      expect(card("Padel Gldani")).to include(%(<form class="fav" method="post" action="/favourites/gldani">))
      expect(card("Padel Gldani")).to include(%(<a class="club-card__link" href="/date/#{day}/club/gldani"><span class="club-row__name">Padel Gldani</span></a>))
    end

    describe "under the forecast" do
      def hour(at, chance:, temperature:)
        Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc(at), rain_chance: chance, rain_mm: 0.0,
                                   code: 3, temperature:, day: true)
      end

      # Showers worth a mention but no reason to sink anybody: blue, with
      # how warm it gets.
      it "warns of possible showers in blue, with the day's temperatures" do
        forecast.replace((8..23).map { hour(format("%s %02d:00", day, _1), chance: (19..21).cover?(_1) ? 30 : 0, temperature: _1) }, city: "Tbilisi")
        get "/date/#{day}"

        banner = last_response.body[%r{<div class="weather notice[^"]*">.*?</div>}m]
        expect(banner).to start_with('<div class="weather notice">')
        expect(banner).to include("Showers possible 19:00–22:00").and include("8–23°")
      end

      it "stays a plain card on a dry day" do
        forecast.replace((8..23).map { hour(format("%s %02d:00", day, _1), chance: 0, temperature: 15) }, city: "Tbilisi")
        get "/date/#{day}"

        expect(last_response.body).to include('<div class="weather notice is-dry">')
      end
    end
  end

  describe "one club's hours" do
    def hour(at, chance:)
      Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc(at), rain_chance: chance, rain_mm: 0.0,
                                 code: 61, temperature: 15.0, day: false)
    end

    before do
      forecast.replace((8..23).map { hour(format("%s %02d:00", day, _1), chance: (19..21).cover?(_1) ? 80 : 0) }, city: "Tbilisi")
    end

    def strip = last_response.body[%r{<div class="notice notice--slim">.*?</div>}m].to_s

    it "says over the tiles when it will rain, and that it falls on the open courts" do
      get "/date/#{day}/club/gldani"

      expect(strip).to include("Rain likely 19:00–22:00 · outdoor courts")
    end

    it "leaves the open courts out where the club has none" do
      get "/date/#{day}/club/lemans"

      expect(strip).to include("Rain likely 19:00–22:00")
      expect(strip).not_to include("outdoor")
    end

    it "names the club's area beside the date" do
      get "/date/#{day}/club/gldani"

      expect(last_response.body).to include(%(<div class="bar__sub">#{Booking::Messages::DAY_NAMES[day.wday]} · #{day.strftime("%b %-d")} · Gldani</div>))
    end
  end

  describe "how long ago, said" do
    it "counts in minutes, then hours, then days" do
      expect([20, 59, 60, 4 * 60, 61 * 60, 5 * 3600, 2 * 86_400].map { Booking::Messages.updated_ago(_1) }).to eq(
        ["Updated just now", "Updated just now", "Updated 1 min ago", "Updated 4 min ago", "Updated 1 h ago",
         "Updated 5 h ago", "Updated 2 d ago"]
      )
    end
  end
end
