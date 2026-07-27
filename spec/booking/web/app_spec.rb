require "rack/test"

RSpec.describe Booking::Web::App do
  include Rack::Test::Methods

  let(:token) { "123456:TEST-TOKEN-do-not-use" }
  let(:sessions) { Booking::Web::Session.new(secret: "a-secret-that-only-the-server-knows") }

  # Clubs and Slots are stood in for: the web only reads them, and the routes
  # are what is under test, not Sequel. Watches are the real repository over an
  # in-memory database, because here the web *writes* — and a faked repository
  # would prove only that the route called the method it was written to call.
  FakeRepos = Struct.new(:clubs, :slots, :watches)
  FakeClubs = Struct.new(:enabled)
  FakeSlots = Struct.new(:all)

  let(:db) { Booking::DB.connect("sqlite:/") }
  let(:watches) { Booking::Repo::Watches.new(db) }
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
  let(:free_slots) { [] }
  let(:repos) { FakeRepos.new(FakeClubs.new(clubs), FakeSlots.new(free_slots), watches) }

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

  describe "the watches screen" do
    def standing(user_id: 42, club_slugs: ["padel-club-2"], weekdays: [5], from_minute: 1140, to_minute: 1320)
      watches.create(user_id:, club_slugs:, weekdays:, from_minute:, to_minute:)
    end

    # The shape a tapped Cell will produce: the weekday of that date, that
    # single hour, and the date itself.
    def dated(user_id: 42, date: today + 1, from_minute: 1140)
      watches.create(
        user_id:, date:, club_slugs: ["padel-club-2"],
        weekdays: [date.wday], from_minute:, to_minute: from_minute + 60
      )
    end

    it "is not served to somebody without a session" do
      get "/watches"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/start")
    end

    # There is no link to keep anywhere and no menu but Telegram's own, so the
    # two screens have to reach each other.
    it "is reachable from the grid, and reaches it back" do
      sign_in(user_id: 42)

      get "/"
      expect(last_response.body).to include('href="/watches"')

      get "/watches"
      expect(last_response.body).to include('href="/"')
    end

    it "says so when there is nothing to show" do
      sign_in(user_id: 42)

      get "/watches"

      expect(last_response.body).to include("No watches yet")
    end

    it "names the clubs a watch covers" do
      standing
      sign_in(user_id: 42)

      get "/watches"

      expect(last_response.body).to include("Padel Club 2")
    end

    it "spells out a standing watch's days and hours" do
      standing(weekdays: [5], from_minute: 1140, to_minute: 1320)
      sign_in(user_id: 42)

      get "/watches"

      expect(last_response.body).to include("Fri").and include("19:00–22:00")
    end

    # Standing and Dated are one record downstream, so the screen is the only
    # place the difference is visible — and it has to be visible without
    # reading the hours twice.
    it "tells a dated watch apart by naming the one day it is about" do
      dated(date: today + 1, from_minute: 1140)
      sign_in(user_id: 42)

      get "/watches"

      expect(last_response.body).to include((today + 1).strftime("%a %-d %b"))
      expect(last_response.body).to include("Dated")
    end

    # Tidiness rather than correctness: an expired Dated watch has already
    # stopped matching, it just has no business still being on the screen.
    it "drops a dated watch whose hour has gone by" do
      dated(date: today - 1)
      sign_in(user_id: 42)

      get "/watches"

      expect(last_response.body).not_to include("Padel Club 2")
    end

    it "keeps a dated watch whose hour is still to come" do
      dated(date: today + 1)
      sign_in(user_id: 42)

      get "/watches"

      expect(last_response.body).to include("Padel Club 2")
    end

    it "does not call a standing watch dated" do
      standing
      sign_in(user_id: 42)

      get "/watches"

      expect(last_response.body).to include("Standing")
      expect(last_response.body).not_to include("Dated")
    end

    # The shared link is not a shared account: two people using the app at once
    # must each see their own list and nobody else's.
    it "leaves somebody else's watches out" do
      standing(user_id: 7, club_slugs: ["kus-tba-padel"])
      sign_in(user_id: 42)

      get "/watches"

      expect(last_response.body).not_to include("Kus Tba Padel")
    end

    describe "pausing" do
      # Pausing is not a slow way of deleting: the watch is still there, and
      # `active` is what the Matcher reads, so this is the whole behaviour.
      it "stops the watch matching without losing it" do
        watch = standing
        sign_in(user_id: 42)

        post "/watches/#{watch.id}/pause"

        expect(watches.active).to be_empty
        expect(watches.for_user(42).size).to eq(1)
      end

      it "says so on the screen it returns to" do
        watch = standing
        sign_in(user_id: 42)

        post "/watches/#{watch.id}/pause"
        follow_redirect!

        expect(last_response.body).to include("Paused")
      end

      it "puts a resumed watch back in front of the matcher" do
        watch = standing
        sign_in(user_id: 42)

        post "/watches/#{watch.id}/pause"
        post "/watches/#{watch.id}/resume"

        expect(watches.active.size).to eq(1)
      end
    end

    describe "deleting" do
      it "removes the watch" do
        watch = standing
        sign_in(user_id: 42)

        post "/watches/#{watch.id}/delete"

        expect(watches.for_user(42)).to be_empty
      end

      it "takes it off the screen it returns to" do
        watch = standing
        sign_in(user_id: 42)

        post "/watches/#{watch.id}/delete"
        follow_redirect!

        expect(last_response.body).not_to include("Padel Club 2")
      end
    end

    # The watch id is a small integer arriving from the page, so "nobody else
    # is using it" is not an access control. Everything that changes a watch
    # checks who owns it.
    describe "somebody else's watch" do
      %w[pause resume delete].each do |action|
        it "cannot be #{action}d" do
          watch = standing(user_id: 7)
          sign_in(user_id: 42)

          post "/watches/#{watch.id}/#{action}"

          expect(last_response.status).to eq(404)
        end
      end

      it "survives the attempt untouched" do
        watch = standing(user_id: 7)
        sign_in(user_id: 42)

        post "/watches/#{watch.id}/pause"
        post "/watches/#{watch.id}/delete"

        expect(watches.find(watch.id)).to be_active
      end

      it "is out of reach without any session at all" do
        watch = standing(user_id: 7)

        post "/watches/#{watch.id}/delete"

        expect(watches.find(watch.id)).not_to be_nil
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
