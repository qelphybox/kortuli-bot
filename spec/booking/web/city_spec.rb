require "rack/test"

# The City pill and the picker it opens: as a page (GET /city), as the sheet
# drawn into the screens that carry the pill, and as the first screen of
# somebody who has never picked.
RSpec.describe "The City picker" do
  include Rack::Test::Methods

  let(:token) { "123456:TEST-TOKEN-do-not-use" }
  let(:sessions) { Booking::Web::Session.new(secret: "a-secret-that-only-the-server-knows") }
  let(:db) { Booking::DB.connect("sqlite:/") }
  let(:preferences) { Booking::Repo::Preferences.new(db) }
  let(:today) { Booking::Clock.local_date(Booking::Clock.now) }

  def club(slug, name, city = nil)
    settings = { "opening_hours" => { "from" => "08:00", "to" => "24:00" } }
    settings["city"] = city if city
    Booking::Club.new(slug:, name:, adapter: "reservio", settings:)
  end

  # Two clubs that name no city, so Tbilisi's, and one in Batumi.
  let(:tbilisi_clubs) { [club("padel-club-2", "Padel Club 2"), club("kus-tba-padel", "Kus Tba Padel")] }
  let(:clubs) { [*tbilisi_clubs, club("padel-port", "Padel Port", "Batumi")] }
  let(:free_slots) do
    [slot(club: "padel-club-2", at: "#{today} 18:00"), slot(club: "kus-tba-padel", at: "#{today} 21:00"),
     slot(club: "kus-tba-padel", at: "#{today + 1} 21:00")]
  end
  let(:repos) do
    Struct.new(:clubs, :slots, :watches, :favourites, :forecast, :visits, :preferences).new(
      Struct.new(:enabled).new(clubs), Struct.new(:all).new(free_slots), Booking::Repo::Watches.new(db),
      Booking::Repo::Favourites.new(db), Booking::Repo::Forecast.new(db), Booking::Repo::Visits.new(db), preferences
    )
  end

  def app
    Booking::Web::App.tap do |a|
      a.set :telegram_token, token
      a.set :bot_username, "kortuli_test_bot"
      a.set :visitor_sessions, sessions
      a.set :repos, repos
      a.set :club_profiles, {}
      a.set :owner_id, nil
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

  def card(city) = body[%r{<label class="city-card" data-city="#{city}".*?</label>}m].to_s

  def pill = body[%r{<(?:a|span) class="city-pill.*?</(?:a|span)>\s*(?=<dialog|\z|</)}m].to_s

  describe "as a page" do
    before do
      sign_in
      preferences.choose_city(42, "Tbilisi")
    end

    it "draws a card per city with what is really there today" do
      get "/city", back: "/clubs"

      expect(last_response.status).to eq(200)
      expect(body).to include("Where do you play?")
      expect(card("Tbilisi")).to include("2 clubs · 2 free today").and include("თბილისი")
      # Tomorrow's hour at Kus Tba is not today's.
      expect(card("Batumi")).to include("1 club · fully booked today").and include("Black Sea").and include("ბათუმი")
    end

    it "ticks the city on screen, and posts the pick back to where it was opened" do
      get "/city", back: "/clubs"

      expect(card("Tbilisi")).to include('value="Tbilisi" checked')
      expect(card("Batumi")).not_to include("checked")
      expect(body).to include('<form class="city-picker city-picker--page" method="post" action="/city"')
      expect(body).to include('name="back" value="/clubs"')
      expect(body).to include("Show courts")
    end

    # "Use my location" measures in the page, so the centres are in it.
    it "carries each city's centre for the location button to measure against" do
      get "/city"

      expect(card("Batumi")).to include(%(data-lat="#{Booking::Weather::CITIES["Batumi"][0]}"))
      expect(body).to include("data-city-locate")
    end

    it "closes back to the screen it came from, and only to one of those" do
      get "/city", back: "/watches/new"
      expect(body).to include('class="city-picker__close" href="/watches/new"')

      get "/city", back: "https://example.com/elsewhere"
      expect(body).to include('class="city-picker__close" href="/"')
      expect(body).to include('name="back" value="/"')
    end

    it "points somebody whose city is missing at the bot" do
      get "/city"

      expect(body).to include(Booking::Messages.feedback_pill_city).and include("https://t.me/kortuli_test_bot?start=feedback")
    end

    describe "with a city nothing is known about but its clubs" do
      let(:clubs) { [*tbilisi_clubs, club("gori-padel", "Gori Padel", "Gori")] }

      it "still draws it, plainly, and never as anybody's nearest" do
        get "/city"

        expect(card("Gori")).to include("Gori").and include("1 club · fully booked today")
        expect(card("Gori")).not_to include("city-card__art")
        expect(card("Gori")).not_to include("data-lat")
      end
    end

    it "lands on the screen it was opened from once a city is picked" do
      post "/city", city: "Batumi", back: "/watches/new"

      expect(last_response.location).to end_with("/watches/new")
      expect(preferences.city(42)).to eq("Batumi")
    end
  end

  it "is not served to somebody without a session" do
    get "/city"

    expect(last_response.location).to end_with("/start")
  end

  describe "the first visit" do
    before { sign_in }

    it "asks which city before it draws a week" do
      get "/"

      expect(body).to include('class="city-picker city-picker--first-run"').and include("KORTULI")
      expect(body).not_to include('class="dates')
      # Nothing behind it to close onto.
      expect(body).not_to include("city-picker__close")
      expect(body).to include('name="back" value="/"')
    end

    it "shows the week of the city picked, and never asks again" do
      post "/city", city: "Batumi", back: "/"
      expect(last_response.location).to end_with("/")

      get "/"
      expect(body).to include('class="dates')
      expect(body).not_to include("city-picker--first-run")
    end

    # Only the home screen asks; a link straight into the app is followed.
    it "does not stand in front of the other screens" do
      get "/clubs"

      expect(body).to include('href="/clubs/kus-tba-padel"')
    end

    describe "with one city" do
      let(:clubs) { tbilisi_clubs }

      it "has nothing to ask" do
        get "/"

        expect(body).to include('class="dates')
        expect(body).not_to include("city-picker")
      end
    end
  end

  describe "the pill" do
    before do
      sign_in
      preferences.choose_city(42, "Tbilisi")
    end

    it "is a link to the picker, which is already on the screen as a sheet" do
      get "/"

      expect(pill).to include('href="/city?back=%2F"').and include("Tbilisi").and include("city-pill__pin")
      expect(body).to include('<dialog class="city-sheet" id="city-sheet"')
      expect(body[%r{<dialog.*?</dialog>}m]).to include("city-picker--sheet").and include("city-picker__close")
    end

    it "counts the city's clubs on the directory" do
      get "/clubs"

      expect(pill).to include("Tbilisi · 2").and include('href="/city?back=%2Fclubs"')
      expect(pill).not_to include("city-pill__pin")
    end

    describe "with one city" do
      let(:clubs) { tbilisi_clubs }

      it "is a label, not a way anywhere" do
        get "/"
        expect(pill).to start_with("<span").and include("Tbilisi")
        expect(body).not_to include("/city?")
        expect(body).not_to include("<dialog")

        get "/clubs"
        expect(pill).to start_with("<span").and include("Tbilisi · 2")
      end
    end
  end
end
