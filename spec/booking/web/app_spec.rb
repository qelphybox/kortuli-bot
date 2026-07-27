require "rack/test"

RSpec.describe Booking::Web::App do
  include Rack::Test::Methods

  let(:token) { "123456:TEST-TOKEN-do-not-use" }
  let(:sessions) { Booking::Web::Session.new(secret: "a-secret-that-only-the-server-knows") }

  # Stands in for the real repositories, which the web only ever reads from
  # here. Keeping it this thin is the point: the routes are what is under test,
  # not Sequel.
  FakeRepos = Struct.new(:clubs, :slots)
  FakeClubs = Struct.new(:enabled)
  FakeSlots = Struct.new(:all)

  let(:clubs) { [] }
  let(:free_slots) { [] }
  let(:repos) { FakeRepos.new(FakeClubs.new(clubs), FakeSlots.new(free_slots)) }

  def app
    described_class.tap do |a|
      a.set :telegram_token, token
      a.set :visitor_sessions, sessions
      a.set :repos, repos
    end
  end

  def sign_in(user_id: 42)
    post "/auth", init_data: signed_init_data(user_id:)
  end

  # Signed the way Telegram signs it. Building the payload here rather than
  # pasting a fixed one keeps auth_date current so the freshness check passes;
  # that the algorithm itself is right is pinned by the vector in the InitData
  # spec, not by this.
  def signed_init_data(user_id:, first_name: "Kirill", signing_token: token)
    fields = {
      "auth_date" => Time.now.to_i.to_s,
      "user" => %({"id":#{user_id},"first_name":"#{first_name}"})
    }
    check = fields.keys.sort.map { "#{_1}=#{fields[_1]}" }.join("\n")
    key = OpenSSL::HMAC.digest("SHA256", "WebAppData", signing_token)
    fields["hash"] = OpenSSL::HMAC.hexdigest("SHA256", key, check)

    URI.encode_www_form(fields)
  end

  describe "arriving without a session" do
    it "is sent to the page that can perform the exchange" do
      get "/"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/start")
    end

    it "is not served the page itself" do
      get "/"

      expect(last_response.body).not_to include('class="days"')
    end

    # Telegram puts initData in the URL fragment, which never reaches us, so
    # this page exists purely to run the script that posts it back.
    it "can load the exchange page, which asks Telegram for the payload" do
      get "/start"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Telegram.WebApp.initData")
    end
  end

  describe "exchanging initData for a session" do
    # The greeting itself is drawn client-side from Telegram's own SDK, so what
    # this seam can observe is that the exchange produced a session the next
    # request is served on — which is the part that matters.
    it "accepts a payload Telegram signed and remembers who it was" do
      post "/auth", init_data: signed_init_data(user_id: 42)

      expect(last_response.status).to eq(204)

      get "/"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('class="days"')
    end

    it "refuses a payload signed with a different token" do
      post "/auth", init_data: signed_init_data(user_id: 42, signing_token: "999:WRONG")

      expect(last_response.status).to eq(401)
    end

    it "hands out no session when it refuses" do
      post "/auth", init_data: "user=%7B%22id%22%3A42%7D"

      get "/"
      expect(last_response.status).to eq(302)
    end
  end

  describe "arriving with a session somebody forged" do
    it "is turned away" do
      forged = Booking::Web::Session.new(secret: "not-the-server-secret").issue(42)
      set_cookie("#{Booking::Web::App::COOKIE}=#{forged}")

      get "/"

      expect(last_response.status).to eq(302)
    end
  end

  describe "the grid" do
    let(:today) { Booking::Clock.local_date(Booking::Clock.now) }
    let(:clubs) do
      [
        Booking::Club.new(
          slug: "padel-club-2", name: "Padel Club 2", adapter: "reservio",
          settings: { "opening_hours" => { "from" => "08:00", "to" => "24:00" },
                      "courts" => 4, "booking_url" => "https://padel-club2.example/" }
        ),
        Booking::Club.new(
          slug: "kus-tba-padel", name: "Kus Tba Padel", adapter: "kustba",
          settings: { "opening_hours" => { "from" => "08:00", "to" => "02:00" },
                      "booking_url" => "https://kustba.example/book/" }
        )
      ]
    end

    it "shows a row for every enabled club" do
      sign_in
      get "/"

      expect(last_response.body).to include("Padel Club 2").and include("Kus Tba Padel")
    end

    it "labels the hours of the day" do
      sign_in
      get "/"

      expect(last_response.body).to include("19").and include("08")
    end

    describe "a free hour" do
      let(:free_slots) { [slot(club: "kus-tba-padel", court: "any", at: "#{today} 19:00")] }

      # Tapping a free Cell has to leave the app entirely — we do not book, we
      # hand over. The link is marked so the client opens it through Telegram
      # rather than inside the mini app's own webview.
      it "links out to the club that owns it" do
        sign_in
        get "/"

        expect(last_response.body).to include("https://example.test/book")
        expect(last_response.body).to include("data-external")
      end
    end

    describe "an hour with nothing free" do
      it "is drawn, but goes nowhere" do
        sign_in
        get "/"

        expect(last_response.body).not_to include("data-external")
      end
    end

    describe "moving between dates" do
      it "offers every date across the booking horizon" do
        sign_in
        get "/"

        horizon = (0...Booking::Config.horizon_days).map { (today + _1).to_s }
        expect(horizon.all? { last_response.body.include?(_1) }).to be(true)
      end

      it "renders the date it was asked for" do
        sign_in
        get "/", date: (today + 2).to_s

        expect(last_response.body).to include((today + 2).to_s)
      end

      # A hand-typed date outside the window would render a grid nobody polled,
      # which reads as a club that shut down rather than as a bad request.
      it "falls back to today when handed a date beyond the horizon" do
        sign_in
        get "/", date: (today + 90).to_s

        expect(last_response.status).to eq(302)
      end

      it "falls back to today when handed something that is not a date" do
        sign_in
        get "/", date: "tuesday-ish"

        expect(last_response.status).to eq(302)
      end
    end
  end

  # kamal-proxy will not route to a container that cannot answer this, so a
  # deploy hangs without it.
  describe "the health endpoint" do
    it "answers without a session" do
      get "/up"

      expect(last_response.status).to eq(200)
    end
  end
end
