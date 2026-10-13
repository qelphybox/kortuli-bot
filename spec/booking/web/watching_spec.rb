require "rack/test"

# The watching screens across more than one City: the list names each
# watch's, the form picks one inside itself, and the page outside Telegram
# names the ones there are. Set up the way app_spec is — clubs stood in for,
# the repositories the web writes to real — with a Batumi club beside the two
# Tbilisi ones.
RSpec.describe Booking::Web::App, "watching" do
  include Rack::Test::Methods

  WatchingRepos = Struct.new(:clubs, :slots, :watches, :favourites, :forecast, :visits, :preferences)
  WatchingClubs = Struct.new(:enabled)
  WatchingSlots = Struct.new(:all)

  let(:token) { "123456:TEST-TOKEN-do-not-use" }
  let(:sessions) { Booking::Web::Session.new(secret: "a-secret-that-only-the-server-knows") }
  let(:db) { Booking::DB.connect("sqlite:/") }
  let(:watches) { Booking::Repo::Watches.new(db) }
  let(:favourites) { Booking::Repo::Favourites.new(db) }
  let(:preferences) { Booking::Repo::Preferences.new(db) }
  let(:today) { Booking::Clock.local_date(Booking::Clock.now) }

  def club(slug, name, city = nil)
    settings = { "opening_hours" => { "from" => "08:00", "to" => "24:00" } }
    settings["city"] = city if city
    Booking::Club.new(slug:, name:, adapter: "reservio", settings:)
  end

  let(:clubs) do
    [club("padel-club-2", "Padel Club 2"), club("kus-tba-padel", "Kus Tba Padel"), club("padel-port", "Padel Port", "Batumi")]
  end
  let(:repos) do
    WatchingRepos.new(WatchingClubs.new(clubs), WatchingSlots.new([]), watches, favourites,
                      Booking::Repo::Forecast.new(db), Booking::Repo::Visits.new(db), preferences)
  end

  def app
    described_class.tap do |a|
      a.set :telegram_token, token
      a.set :bot_username, "kortuli_test_bot"
      a.set :visitor_sessions, sessions
      a.set :repos, repos
      a.set :club_profiles, {}
      a.set :owner_id, 7
    end
  end

  def sign_in(user_id: 42)
    fields = { "auth_date" => Time.now.to_i.to_s, "user" => %({"id":#{user_id},"first_name":"Kirill"}) }
    check = fields.keys.sort.map { "#{_1}=#{fields[_1]}" }.join("\n")
    key = OpenSSL::HMAC.digest("SHA256", "WebAppData", token)
    fields["hash"] = OpenSSL::HMAC.hexdigest("SHA256", key, check)
    post "/auth", init_data: URI.encode_www_form(fields)
  end

  def body = last_response.body

  def form = body[%r{<form class="new-watch".*?</form>}m].to_s

  def group(city) = body[%r{<div class="club-group" data-city="#{city}">.*?</div>\s*</div>}m].to_s

  describe "the list" do
    before { sign_in }

    it "names the City each watch's clubs are in" do
      watches.create(user_id: 42, club_slugs: ["padel-port"], weekdays: [6], from_minute: 600, to_minute: 780)
      get "/watches"

      expect(body).to include('<span class="watch__city">').and include("Batumi</span>")
    end

    # A Watch names clubs, not a city, so nothing stops one naming two.
    it "names every City of a watch whose clubs are in more than one" do
      watches.create(user_id: 42, club_slugs: %w[padel-port kus-tba-padel], weekdays: [6], from_minute: 600, to_minute: 780)
      get "/watches"

      expect(body).to include("Tbilisi, Batumi</span>")
    end

    it "draws a Dated watch's one day instead of the weekday squares" do
      date = today + 1
      watches.create(user_id: 42, date:, club_slugs: ["padel-club-2"], weekdays: [date.wday], from_minute: 1140, to_minute: 1200)
      get "/watches"

      expect(body).to include("#{date.strftime("%a %-d %b")} only")
      expect(body).not_to include('class="letters"')
    end
  end

  describe "the form" do
    before { sign_in }

    it "offers every City's clubs, grouped, and a City segment instead of the header's pill" do
      get "/watches/new"

      expect(group("Tbilisi")).to include('value="kus-tba-padel"').and include('value="padel-club-2"')
      expect(group("Batumi")).to include('value="padel-port"')
      expect(form).to include('name="city" value="Tbilisi" checked').and include('name="city" value="Batumi" data-city-pick>')
      expect(body).not_to include("city-picker")
    end

    it "opens on the City this person is looking at" do
      preferences.choose_city(42, "Batumi")
      get "/watches/new"

      expect(form).to include('name="city" value="Batumi" checked')
      expect(form).to include("Clubs<span class=\"js-only\"> in <span data-city-name>Batumi</span>")
    end

    # Starring is per club and a club is in one city, so pre-ticking every
    # star would start the watch out in two.
    it "pre-ticks only the starred clubs in the City it opens on" do
      favourites.add(42, "kus-tba-padel")
      favourites.add(42, "padel-port")
      get "/watches/new"

      expect(form).to include('value="kus-tba-padel" checked')
      expect(form).to include('value="padel-port">')
    end

    it "comes back from a refusal on the City of the clubs it picked" do
      post "/watches", club_slugs: ["padel-port"], weekdays: [], from_hour: "19", to_hour: "22", city: "Tbilisi"

      expect(last_response.status).to eq(422)
      expect(form).to include('name="city" value="Batumi" checked').and include('value="padel-port" checked')
    end

    it "comes back on the City its segment was left on when no club was picked" do
      post "/watches", weekdays: ["1"], from_hour: "19", to_hour: "22", city: "Batumi"

      expect(form).to include('name="city" value="Batumi" checked')
    end

    it "ignores a City that has no clubs" do
      post "/watches", weekdays: ["1"], from_hour: "19", to_hour: "22", city: "Gori"

      expect(form).to include('name="city" value="Tbilisi" checked')
    end

    describe "with one City" do
      let(:clubs) { [club("padel-club-2", "Padel Club 2")] }

      it "has no segment, and names the City over the clubs" do
        get "/watches/new"

        expect(form).not_to include('name="city"')
        expect(form).to include("Clubs in Tbilisi")
      end
    end
  end

  it "confirms a new watch's days as one dotted line" do
    sign_in
    post "/watches", club_slugs: ["padel-club-2"], weekdays: %w[1 2 5], from_hour: "19", to_hour: "22"
    follow_redirect!

    expect(body).to include("Mon · Tue · Fri")
  end

  describe "the page outside Telegram" do
    it "names the Cities that have clubs" do
      get "/start"

      expect(body).to include("free padel courts in Tbilisi and Batumi.")
      # Still the script that signs a person in.
      expect(body).to include("Telegram.WebApp.initData")
    end

    describe "with one City" do
      let(:clubs) { [club("padel-port", "Padel Port", "Batumi")] }

      it "names it alone" do
        get "/start"

        expect(body).to include("free padel courts in Batumi.")
      end
    end
  end
end
