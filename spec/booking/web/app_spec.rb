require "rack/test"
require "tmpdir"

RSpec.describe Booking::Web::App do
  include Rack::Test::Methods

  let(:token) { "123456:TEST-TOKEN-do-not-use" }
  let(:sessions) { Booking::Web::Session.new(secret: "a-secret-that-only-the-server-knows") }

  # Clubs and Slots are stood in for: the web only reads them, and the routes
  # are what is under test, not Sequel. Watches, Favourites, Visits and
  # Preferences are the real repositories over an in-memory database, because here the web
  # *writes* — and a faked repository would prove only that the route called
  # the method it was written to call. The Forecast is real too, because filling it is
  # simpler than faking it.
  FakeRepos = Struct.new(:clubs, :slots, :watches, :favourites, :forecast, :visits, :preferences)
  FakeClubs = Struct.new(:enabled)
  FakeSlots = Struct.new(:all)

  let(:db) { Booking::DB.connect("sqlite:/") }
  let(:watches) { Booking::Repo::Watches.new(db) }
  let(:favourites) { Booking::Repo::Favourites.new(db) }
  let(:forecast) { Booking::Repo::Forecast.new(db) }
  let(:visits) { Booking::Repo::Visits.new(db) }
  let(:preferences) { Booking::Repo::Preferences.new(db) }
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
  # Kus Tba has a Profile; Padel Club 2, as in config/, does not.
  let(:club_profiles) do
    {
      "kus-tba-padel" => Booking::ClubProfile.from(
        {
          "source" => "https://sapadelo.com/georgia/clubs/kus-tba-padel",
          "area" => "Turtle Lake",
          "address" => "Turtle Lake",
          "phone" => "+995585889977",
          "lat" => 41.700688, "lng" => 44.7570599,
          "courts" => [{ "name" => "Court 1", "cover" => "outdoor" }, { "name" => "Court 2", "cover" => "outdoor" }],
          "hours" => %w[mon tue wed thu fri sat sun].to_h { [_1, "10:00–02:00"] },
          "prices" => [{ "gel" => 80 }, { "gel" => 60, "from" => "10:00", "to" => "14:00" }]
        },
        checked_on: "2026-10-11"
      )
    }
  end
  let(:repos) { FakeRepos.new(FakeClubs.new(clubs), FakeSlots.new(free_slots), watches, favourites, forecast, visits, preferences) }

  let(:owner_id) { 7 }
  let(:log_dir) { Dir.mktmpdir }
  let(:dashboard) { Booking::Ops::Dashboard.new(db:, database_path: nil, log_dir:, poll_every: 300) }

  after { FileUtils.rm_rf(log_dir) }

  def app
    described_class.tap do |a|
      a.set :telegram_token, token
      a.set :bot_username, "kortuli_test_bot"
      a.set :visitor_sessions, sessions
      a.set :repos, repos
      a.set :club_profiles, club_profiles
      a.set :owner_id, owner_id
      a.set :dashboard, dashboard
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

      expect(last_response.body).not_to include('class="dates"')
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
      expect(last_response.body).to include('class="dates')
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

  describe "the dates screen" do
    it "offers every date across the booking horizon" do
      sign_in
      get "/"

      horizon = (0...Booking::Config.horizon_days).map { (today + _1).to_s }
      expect(horizon.all? { last_response.body.include?(_1) }).to be(true)
    end

    # Looking, a Rundown and a Game all start from a date, so the dates are
    # the screen. Watching and the clubs are the other two tabs: one tap
    # away, but under the thumb rather than over the list.
    describe "its tabs" do
      def tabs = last_response.body[%r{<nav class="tabbar".*?</nav>}m].to_s

      it "reach the watches and the clubs" do
        sign_in
        get "/"

        expect(tabs).to include('href="/watches"', 'href="/clubs"')
      end

      it "leave nothing but the dates outside them" do
        sign_in
        get "/"

        outside = last_response.body.sub(tabs, "")
        expect(outside).not_to include('href="/watches', 'href="/clubs"')
      end

      it "count the watches somebody already has" do
        watches.create(user_id: 42, club_slugs: ["padel-club-2"], weekdays: [5], from_minute: 1140, to_minute: 1320)
        sign_in(user_id: 42)
        get "/"

        expect(tabs).to include('<span class="tab__count">1</span>')
      end
    end

    # The escape hatch out of the app and into the bot chat. See ADR-0002 —
    # the pill has to carry `start=feedback` so the bot answers with the
    # feedback prompt on arrival rather than the plain welcome.
    it "offers a feedback pill that deep-links into the bot chat" do
      sign_in
      get "/"

      expect(last_response.body).to include('href="https://t.me/kortuli_test_bot?start=feedback"')
      expect(last_response.body).to include(Booking::Messages.feedback_pill_dates)
    end
  end

  describe "the clubs screen" do
    it "lists every enabled club for that date" do
      sign_in
      get "/date/#{today}"

      expect(last_response.body).to include("Padel Club 2").and include("Kus Tba Padel")
    end

    it "sends on to a single club's slots" do
      sign_in
      get "/date/#{today}"

      expect(last_response.body).to include(%(href="/date/#{today}/club/padel-club-2"))
    end

    it "carries a feedback pill with the missing-club prompt" do
      sign_in
      get "/date/#{today}"

      expect(last_response.body).to include(Booking::Messages.feedback_pill_clubs)
    end

    # A hand-typed date outside the window would render a page nobody polled,
    # which reads as a club that shut down rather than as a bad request.
    it "falls back to the dates screen when handed a date beyond the horizon" do
      sign_in
      get "/date/#{today + 90}"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/")
    end

    it "falls back to the dates screen when handed something that is not a date" do
      sign_in
      get "/date/tuesday-ish"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/")
    end

    describe "starring a club" do
      def club_names_in_order = last_response.body.scan(%r{<span class="club-row__name">([^<]+)</span>}).flatten

      it "offers a star on every club, none of them lit at first" do
        sign_in
        get "/date/#{today}"

        expect(last_response.body).to include(%(action="/favourites/padel-club-2"))
        expect(last_response.body).to include(%(action="/favourites/kus-tba-padel"))
        expect(last_response.body).not_to include("is-on")
      end

      it "remembers the star and turns it over on the same screen" do
        sign_in(user_id: 42)
        post "/favourites/kus-tba-padel", date: today.to_s

        expect(last_response.location).to end_with("/date/#{today}")
        expect(favourites.for_user(42)).to eq(Set["kus-tba-padel"])

        follow_redirect!
        expect(last_response.body).to include(%(action="/favourites/kus-tba-padel/delete"))
      end

      it "takes the star back off" do
        sign_in(user_id: 42)
        favourites.add(42, "kus-tba-padel")

        post "/favourites/kus-tba-padel/delete", date: today.to_s

        expect(favourites.for_user(42)).to be_empty
      end

      # Kus Tba sorts after Padel Club 2 by slug, so leading is the star's doing.
      it "lists favourites first" do
        sign_in(user_id: 42)
        favourites.add(42, "kus-tba-padel")

        get "/date/#{today}"

        expect(club_names_in_order).to eq(["Kus Tba Padel", "Padel Club 2"])
      end

      it "is somebody's own: another person's stars do not show" do
        favourites.add(7, "kus-tba-padel")
        sign_in(user_id: 42)

        get "/date/#{today}"

        expect(last_response.body).not_to include("is-on")
      end

      it "refuses a club nobody watches" do
        sign_in(user_id: 42)
        post "/favourites/not-a-club", date: today.to_s

        expect(last_response.status).to eq(404)
        expect(favourites.for_user(42)).to be_empty
      end

      it "cannot be done without a session" do
        post "/favourites/kus-tba-padel", date: today.to_s

        expect(last_response.location).to end_with("/start")
      end

      it "lands on the dates screen when the page's date has gone by" do
        sign_in(user_id: 42)
        post "/favourites/kus-tba-padel", date: (today - 1).to_s

        expect(last_response.location).to end_with("/")
      end

      # The same star sits on a club's Profile, and turns over there.
      it "goes back to the club's profile when starred from it, keeping its date" do
        sign_in(user_id: 42)
        post "/favourites/kus-tba-padel", back: "profile", date: today.to_s

        expect(last_response.location).to end_with("/clubs/kus-tba-padel?date=#{today}")
        expect(favourites.for_user(42)).to eq(Set["kus-tba-padel"])
      end
    end

    # The week as tabs over the list, so the next day is one tap away.
    it "links every date across the horizon, marking the one on screen" do
      sign_in
      get "/date/#{today + 1}"

      strip = last_response.body[%r{<nav class="strip".*?</nav>}m].to_s
      expect(strip.scan(%r{href="/date/[\d-]+"}).size).to eq(Booking::Config.horizon_days)
      expect(strip).to include(%(href="/date/#{today + 1}" aria-current="date"))
    end

    describe "narrowed by the chips" do
      def club_names_in_order = last_response.body.scan(%r{<span class="club-row__name">([^<]+)</span>}).flatten

      # Kus Tba has a Profile with every court outdoors; Padel Club 2 has no
      # Profile, so neither is known to have a roof.
      it "keeps only the clubs with a roof when asked for covered ones" do
        sign_in
        get "/date/#{today}?only=covered"

        expect(club_names_in_order).to be_empty
      end

      it "keeps only the favourites when asked for them" do
        sign_in(user_id: 42)
        favourites.add(42, "padel-club-2")
        get "/date/#{today}?only=favourites"

        expect(club_names_in_order).to eq(["Padel Club 2"])
      end

      it "shows every club for anything it does not know" do
        sign_in
        get "/date/#{today}?only=nonsense"

        expect(club_names_in_order).to contain_exactly("Padel Club 2", "Kus Tba Padel")
      end
    end
  end

  describe "the share screen" do
    let(:day) { today + 1 }
    let(:free_slots) do
      [slot(club: "padel-club-2", at: "#{day} 18:00"), slot(club: "padel-club-2", at: "#{day} 19:00"),
       slot(club: "kus-tba-padel", court: "any", at: "#{day} 10:00"),
       slot(club: "kus-tba-padel", court: "any", at: "#{day + 1} 01:00")]
    end

    def preview = CGI.unescapeHTML(last_response.body[%r{<pre class="copy-source"[^>]*>(.*?)</pre>}m, 1].to_s)

    def shared_text
      href = last_response.body[/data-tg-share href="([^"]+)"/, 1]
      CGI.unescape(CGI.unescapeHTML(href)[/[?&]text=([^&]*)/, 1].to_s)
    end

    it "is reached from the clubs screen of the same date" do
      sign_in
      get "/date/#{day}"

      expect(last_response.body).to include(%(href="/date/#{day}/share"))
    end

    it "is not served to somebody without a session" do
      get "/date/#{day}/share"

      expect(last_response.location).to end_with("/start")
    end

    it "falls back to the dates screen when handed a date beyond the horizon" do
      sign_in
      get "/date/#{today + 90}/share"

      expect(last_response.location).to end_with("/")
    end

    # The first case: the whole day, every club, in one message.
    it "puts every club's free hours for the day into one message" do
      sign_in
      get "/date/#{day}/share"

      expect(preview).to include("Padel Club 2\n18:00–20:00\nhttps://example.test/book")
      expect(preview).to include("Kus Tba Padel\n10:00–11:00, 01:00–02:00")
    end

    # The message is the one place the weather leaves the app, so it says
    # what the date's list says, and how warm it gets besides.
    it "puts the day's weather under the heading" do
      forecast.replace((8..23).map do |hour|
        Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc(format("%s %02d:00", day, hour)),
                                   rain_chance: hour == 19 ? 80 : 0, rain_mm: 0.0, code: 3,
                                   temperature: 12.0 + (hour / 4), day: false)
      end, city: "Tbilisi")
      sign_in
      get "/date/#{day}/share"

      expect(preview).to match(/\A🎾 Free padel courts · .+\n🌧 Rain likely 19:00–20:00 · 14–17°\n\n/)
      expect(shared_text).to include("🌧 Rain likely 19:00–20:00 · 14–17°")
    end

    # The share sheet sends what the preview shows; only the clipboard adds
    # the bot's link, which the sheet adds by itself.
    it "sends through Telegram's share sheet exactly the text it previews" do
      sign_in
      get "/date/#{day}/share"

      expect(last_response.body).to include('data-tg-share href="https://t.me/share/url?url=https%3A%2F%2Ft.me%2Fkortuli_test_bot&amp;text=')
      expect("#{shared_text}\n\nvia https://t.me/kortuli_test_bot").to eq(preview)
    end

    # The second case: a span of hours, picked after the day.
    it "narrows the message to the hours picked" do
      sign_in
      get "/date/#{day}/share", from: 18, to: 22

      expect(preview).to include(", 18:00–22:00")
      expect(preview).to include("Padel Club 2\n18:00–20:00")
      expect(preview).to include("Fully booked: Kus Tba Padel")
    end

    # Counted from the date's midnight, so a span into the small hours runs
    # forwards rather than wrapping round to the morning.
    it "lets a span run past midnight, into the hours a late club sells" do
      sign_in
      get "/date/#{day}/share", from: 23, to: 26

      expect(preview).to include(", 23:00–02:00")
      expect(preview).to include("Kus Tba Padel\n01:00–02:00")
      expect(preview).not_to include("10:00")
    end

    it "offers the hours a club open past midnight sells, after 23:00" do
      sign_in
      get "/date/#{day}/share"

      expect(last_response.body).to include('<option value="25">01:00</option>')
      expect(last_response.body).to include('<option value="26" selected>02:00</option>')
    end

    # A filter, not a form: something off the list shows the whole day rather
    # than a refusal.
    it "shows the whole day when the span picked is backwards or not on offer" do
      sign_in

      get "/date/#{day}/share", from: 22, to: 18
      expect(preview.lines.first).not_to include(",")
      expect(preview).to include("10:00–11:00")

      get "/date/#{day}/share", from: 4, to: "soon"
      expect(preview).to include("10:00–11:00")
    end

    it "offers no send button when the span holds nothing free" do
      sign_in
      get "/date/#{day}/share", from: 8, to: 9

      expect(last_response.body).to include(Booking::Messages.share_nothing)
      expect(last_response.body).not_to include("data-tg-share")
    end

    describe "narrowed to some clubs" do
      it "speaks for every club until told otherwise" do
        sign_in
        get "/date/#{day}/share"

        expect(last_response.body).to include('name="only" value="all" checked')
        expect(last_response.body).not_to include('name="clubs[]"')
      end

      it "narrows the message to the clubs starred" do
        sign_in(user_id: 42)
        favourites.add(42, "kus-tba-padel")

        get "/date/#{day}/share", only: "favourites"

        expect(preview).to include("Kus Tba Padel\n10:00–11:00")
        expect(preview).not_to include("Padel Club 2")
      end

      # Not an empty message: every club, and a line saying where stars are made.
      it "shows every club, and says why, when nothing is starred yet" do
        sign_in(user_id: 42)
        get "/date/#{day}/share", only: "favourites"

        expect(preview).to include("Padel Club 2").and include("Kus Tba Padel")
        expect(last_response.body).to include(Booking::Messages.share_no_favourites)
      end

      it "narrows the message to the clubs ticked by hand" do
        sign_in
        get "/date/#{day}/share", only: "picked", clubs: ["padel-club-2"]

        expect(preview).to include("Padel Club 2\n18:00–20:00")
        expect(preview).not_to include("Kus Tba Padel")
        expect(last_response.body).to include('name="clubs[]" value="padel-club-2" checked')
        expect(last_response.body).to include('name="clubs[]" value="kus-tba-padel">')
      end

      # Switching to "Pick" starts from the whole list and unticks down.
      it "starts picking from every club ticked" do
        sign_in
        get "/date/#{day}/share", only: "picked"

        expect(last_response.body).to include('name="clubs[]" value="padel-club-2" checked')
        expect(last_response.body).to include('name="clubs[]" value="kus-tba-padel" checked')
        expect(preview).to include("Padel Club 2").and include("Kus Tba Padel")
      end

      it "ignores a club nobody watches" do
        sign_in
        get "/date/#{day}/share", only: "picked", clubs: %w[padel-club-2 not-a-club]

        expect(preview).to include("Padel Club 2")
        expect(preview).not_to include("not-a-club")
      end

      # Kus Tba has nothing between 18:00 and 22:00, and unpicked it is not
      # a club the reader was asked about — so it is not named as booked.
      it "names as fully booked only the clubs it was narrowed to" do
        sign_in
        get "/date/#{day}/share", only: "picked", clubs: ["padel-club-2"], from: 18, to: 22

        expect(preview).to include("Padel Club 2\n18:00–20:00")
        expect(preview).not_to include("Fully booked")
      end

      it "narrows by clubs and hours at once" do
        sign_in
        get "/date/#{day}/share", only: "picked", clubs: ["kus-tba-padel"], from: 23, to: 26

        expect(preview).to include(", 23:00–02:00")
        expect(preview).to include("Kus Tba Padel\n01:00–02:00")
        expect(preview).not_to include("Padel Club 2")
      end

      # The span resets; the clubs picked do not.
      it "keeps the clubs on the way back to the whole day" do
        sign_in
        get "/date/#{day}/share", only: "picked", clubs: ["kus-tba-padel"], from: 18, to: 22

        expect(last_response.body).to include(%(href="/date/#{day}/share?only=picked&amp;clubs%5B%5D=kus-tba-padel">Whole day))
      end
    end
  end

  describe "the slots screen" do
    it "labels the hours the club sells" do
      sign_in
      get "/date/#{today + 1}/club/kus-tba-padel"

      expect(last_response.body).to include("08:00").and include("19:00")
    end

    it "carries a feedback pill with the wrong-times prompt" do
      sign_in
      get "/date/#{today + 1}/club/kus-tba-padel"

      expect(last_response.body).to include(Booking::Messages.feedback_pill_slots)
    end

    it "is 404 when the club is not among the enabled ones" do
      sign_in
      get "/date/#{today}/club/no-such-club"

      expect(last_response.status).to eq(404)
    end

    # We do not book, we hand over. Every free hour would link to the same
    # page, so the screen carries that page once, in its header — marked so
    # the client opens it through Telegram rather than inside the mini app's
    # own webview.
    it "links out to the club's booking page once, from its header" do
      sign_in
      get "/date/#{today + 1}/club/kus-tba-padel"

      header = last_response.body[%r{<header.*?</header>}m]
      expect(header).to include('data-external href="https://kustba.example/book/"')
      expect(last_response.body.scan("data-external").size).to eq(1)
    end

    it "offers the booking page even when nothing is free" do
      sign_in
      get "/date/#{today}/club/padel-club-2"

      expect(last_response.body).to include('data-external href="https://padel-club2.example/"')
    end

    # Being told about a taken hour is made on the watches screen now, for a
    # window rather than one hour, so a row here offers nothing but its tick.
    it "offers no watch on a taken hour" do
      sign_in
      get "/date/#{today + 1}/club/padel-club-2"

      expect(last_response.body).not_to include("/watches")
      expect(last_response.body).to include("taken")
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

    # The create form names every club, so "is this watch on the screen" has to
    # ask the list rather than the page. Empty when there is no list at all.
    def listed = last_response.body[%r{<ul class="watches">.*</ul>}m].to_s

    it "is not served to somebody without a session" do
      get "/watches"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/start")
    end

    # There is no link to keep anywhere, so the two screens have to reach
    # each other — the way there is the home screen's Menu.
    it "is reachable from the dates screen once a watch exists, and reaches it back" do
      standing
      sign_in(user_id: 42)

      get "/"
      expect(last_response.body).to include('href="/watches"')

      get "/watches"
      expect(last_response.body).to include('href="/"')
    end

    # The form has its own screen now, so an empty list points at the button
    # that opens it rather than at a form above.
    it "says so when there is nothing to show, and points at the button" do
      sign_in(user_id: 42)

      get "/watches"

      expect(last_response.body).to include(Booking::Messages.no_watches_in_app)
      expect(last_response.body).to include('href="/watches/new"')
    end

    it "names the clubs a watch covers" do
      standing
      sign_in(user_id: 42)

      get "/watches"

      expect(listed).to include("Padel Club 2")
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

      expect(listed).not_to include("Padel Club 2")
    end

    it "keeps a dated watch whose hour is still to come" do
      dated(date: today + 1)
      sign_in(user_id: 42)

      get "/watches"

      expect(listed).to include("Padel Club 2")
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

      expect(listed).not_to include("Kus Tba Padel")
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

        expect(listed).not_to include("Padel Club 2")
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

    # One form instead of four messages: clubs, weekdays and both ends of an
    # hour range, submitted in a single step.
    describe "the create form" do
      def submit(**overrides)
        post "/watches", {
          club_slugs: ["padel-club-2"], weekdays: %w[1 5], from_hour: "19", to_hour: "22"
        }.merge(overrides)
      end

      it "offers the watched clubs as choices rather than asking for a name" do
        sign_in(user_id: 42)

        get "/watches/new"

        expect(last_response.body).to include('value="padel-club-2"').and include('value="kus-tba-padel"')
        expect(last_response.body).to include("Padel Club 2").and include("Kus Tba Padel")
      end

      # The clubs a person starred are the ones they would tick anyway.
      it "starts with the starred clubs ticked" do
        sign_in(user_id: 42)
        favourites.add(42, "kus-tba-padel")

        get "/watches/new"

        expect(last_response.body).to include('value="kus-tba-padel" checked')
        expect(last_response.body).not_to include('value="padel-club-2" checked')
      end

      it "offers the weekdays and both ends of the range on the same form" do
        sign_in(user_id: 42)

        get "/watches/new"

        form = last_response.body[%r{<form class="new-watch".*?</form>}m].to_s
        expect(form).to include('name="weekdays[]"').and include("Mon").and include("Sun")
        expect(form).to include('name="from_hour"').and include('name="to_hour"')
        # The whole point of the ticket: one submit, not four messages.
        expect(form.scan(/<button(?![^>]*type="button")/).size).to eq(1)
      end

      it "takes clubs, weekdays and both ends of the range in one step" do
        sign_in(user_id: 42)

        submit
        # A successful submit lands on the confirm screen; the list is one
        # more click on from there.
        get "/watches"

        expect(listed).to include("Padel Club 2").and include("Mon, Fri").and include("19:00–22:00")
      end

      # The moment after the form is accepted. Post-redirect-get lands
      # here rather than on the list itself so the affirmation arrives
      # attached to what was just created.
      it "lands on a confirmation screen naming what was created" do
        sign_in(user_id: 42)

        submit
        follow_redirect!

        expect(last_response.body).to include("Padel Club 2")
        expect(last_response.body).to include("19:00–22:00")
      end

      # "Begins matching on the next tick" — `active` is the list the Matcher is
      # handed, so being in it is the whole of that claim.
      it "begins matching straight away" do
        sign_in(user_id: 42)

        submit

        expect(watches.active.size).to eq(1)
      end

      it "belongs to whoever submitted it" do
        sign_in(user_id: 7)

        submit

        expect(watches.for_user(7).size).to eq(1)
      end

      it "cannot be created without a session" do
        submit

        expect(watches.active).to be_empty
      end

      # A watch that can never fire is worse than no watch: it sits in the list
      # looking like cover. Each of these is refused with the reason, not
      # accepted quietly.
      describe "a submission that could never fire" do
        it "refuses one with no clubs" do
          sign_in(user_id: 42)

          submit(club_slugs: [])

          expect(watches.for_user(42)).to be_empty
          expect(last_response.body).to include("at least one club")
        end

        it "refuses one with no days" do
          sign_in(user_id: 42)

          submit(weekdays: [])

          expect(watches.for_user(42)).to be_empty
          expect(last_response.body).to include("at least one day")
        end

        it "refuses a range that ends where it starts" do
          sign_in(user_id: 42)

          submit(from_hour: "19", to_hour: "19")

          expect(watches.for_user(42)).to be_empty
          expect(last_response.body).to include("after")
        end

        it "refuses a range that ends before it starts" do
          sign_in(user_id: 42)

          submit(from_hour: "22", to_hour: "19")

          expect(watches.for_user(42)).to be_empty
          expect(last_response.body).to include("after")
        end

        # The select only offers hours in range, so anything else was not typed
        # by a person using the screen — but the reason still has to be true of
        # what happened, and "the end must be after the start" is not true of
        # the word "tea time".
        it "refuses hours that were never on offer, and says that rather than something else" do
          sign_in(user_id: 42)

          submit(from_hour: "tea time", to_hour: "99")

          expect(watches.for_user(42)).to be_empty
          expect(last_response.status).to eq(422)
          expect(last_response.body).to include("from the list")
          expect(last_response.body).not_to include("after its start")
        end

        # A refusal that also empties the form punishes the person for reading
        # it — and the whole point of the ticket is one step, not a retype.
        it "hands back everything that was picked" do
          sign_in(user_id: 42)

          submit(club_slugs: %w[padel-club-2 kus-tba-padel], weekdays: [], from_hour: "20", to_hour: "23")

          form = last_response.body[%r{<form class="new-watch".*?</form>}m].to_s
          expect(form).to include('value="padel-club-2" checked').and include('value="kus-tba-padel" checked')
          expect(form).to include('value="20" selected').and include('value="23" selected')
        end

        it "does not re-tick a club that was not picked" do
          sign_in(user_id: 42)

          submit(club_slugs: ["padel-club-2"], weekdays: [])

          form = last_response.body[%r{<form class="new-watch".*?</form>}m].to_s
          expect(form).to include('value="kus-tba-padel">')
        end

        it "refuses a club that is not watched" do
          sign_in(user_id: 42)

          submit(club_slugs: ["some-club-we-do-not-poll"])

          expect(watches.for_user(42)).to be_empty
          expect(last_response.body).to include("at least one club")
        end

      end
    end
  end

  # kamal-proxy will not route to a container that cannot answer this, so a
  # deploy hangs without it.
  describe "the clubs directory" do
    it "is reached from the dates screen" do
      sign_in
      get "/"

      expect(last_response.body).to include('href="/clubs"')
    end

    it "lists every watched club, each opening its profile" do
      sign_in
      get "/clubs"

      expect(last_response.body).to include("Padel Club 2").and include("Kus Tba Padel")
      expect(last_response.body).to include('href="/clubs/kus-tba-padel"').and include('href="/clubs/padel-club-2"')
    end

    it "says where a club is and what its courts are under" do
      sign_in
      get "/clubs"

      expect(last_response.body).to include("Turtle Lake · 2 outdoor")
    end

    it "puts favourites first" do
      sign_in
      post "/favourites/padel-club-2"
      get "/clubs"

      expect(last_response.body.index("Padel Club 2")).to be < last_response.body.index("Kus Tba Padel")
    end

    it "is not served to somebody without a session" do
      get "/clubs"

      expect(last_response.location).to end_with("/start")
    end
  end

  describe "a club's profile" do
    it "names its courts and the cover over each" do
      sign_in
      get "/clubs/kus-tba-padel"

      expect(last_response.body).to include("2 outdoor").and include("Court 1").and include("cover--outdoor")
    end

    it "opens its pin in Google Maps, outside the app" do
      sign_in
      get "/clubs/kus-tba-padel"

      expect(last_response.body).to include("https://www.google.com/maps/search/?api=1&amp;query=41.700688,44.7570599")
      expect(last_response.body).to match(/data-external href="https:\/\/www\.google\.com\/maps/)
    end

    it "folds a week of the same hours into one line" do
      sign_in
      get "/clubs/kus-tba-padel"

      expect(last_response.body).to include("Every day").and include("10:00–02:00")
    end

    it "lists its prices, per court and per hour" do
      sign_in
      get "/clubs/kus-tba-padel"

      expect(last_response.body).to include("80 GEL").and include("60 GEL · 10:00–14:00")
    end

    it "offers a call and the booking page" do
      sign_in
      get "/clubs/kus-tba-padel"

      expect(last_response.body).to include('href="tel:+995585889977"').and include("https://kustba.example/book/")
    end

    it "says where the listing came from, and when" do
      sign_in
      get "/clubs/kus-tba-padel"

      expect(last_response.body).to include("sapadelo.com, as of 11 Oct")
      expect(last_response.body).to include("https://sapadelo.com/georgia/clubs/kus-tba-padel")
    end

    it "says there is nothing to show for a club without one, and still links to its booking page" do
      sign_in
      get "/clubs/padel-club-2"

      expect(last_response.body).to include(Booking::Messages.profile_missing)
      expect(last_response.body).to include("https://padel-club2.example/")
    end

    it "is 404 for a club nobody watches" do
      sign_in
      get "/clubs/no-such-club"

      expect(last_response.status).to eq(404)
    end

    it "goes back to the directory by default" do
      sign_in
      get "/clubs/kus-tba-padel"

      expect(last_response.body).to include('href="/clubs" aria-label="Back"')
    end

    it "is reached from a club's hours on a date, and goes back there" do
      sign_in
      get "/date/#{today + 1}/club/kus-tba-padel"
      expect(last_response.body).to include(%(href="/clubs/kus-tba-padel?date=#{today + 1}"))

      get "/clubs/kus-tba-padel?date=#{today + 1}"
      expect(last_response.body).to include(%(href="/date/#{today + 1}/club/kus-tba-padel" aria-label="Back"))
    end

    it "does not go back to a date past the horizon" do
      sign_in
      get "/clubs/kus-tba-padel?date=#{today + 400}"

      expect(last_response.body).to include('href="/clubs" aria-label="Back"')
    end
  end

  describe "the clubs screen naming covers" do
    let(:free_slots) do
      [slot(club: "padel-club-2", at: "#{today + 1} 18:00"), slot(club: "kus-tba-padel", court: "any", at: "#{today + 1} 18:00")]
    end

    it "puts what the courts are under beside a club with a profile, and nothing beside one without" do
      sign_in
      get "/date/#{today + 1}"

      expect(last_response.body).to include('<span class="tag tag--outdoor">outdoor</span>')
      expect(last_response.body.scan('class="tag tag--').size).to eq(1)
    end
  end

  describe "sharing a game" do
    let(:day) { today + 1 }

    def preview = CGI.unescapeHTML(last_response.body[%r{<pre class="copy-source"[^>]*>(.*?)</pre>}m, 1].to_s)

    def shared_text
      href = last_response.body[/data-tg-share href="([^"]+)"/, 1]
      CGI.unescape(CGI.unescapeHTML(href)[/[?&]text=([^&]*)/, 1].to_s)
    end

    # The hours a club's screen lets you tick, as the values they submit.
    def tickable = last_response.body.scan(/name="hours\[\]" value="(\d+)" form="game-pick"/).flatten.map(&:to_i)

    describe "on a club's hours" do
      # Free or taken alike: the booking may not have reached the Grid yet,
      # and somebody who has just booked the last court sees it as taken.
      it "offers a tick on every hour, free or not, for the form that shares them" do
        sign_in
        get "/date/#{day}/club/padel-club-2"

        expect(tickable).to eq((8..23).to_a)
        expect(last_response.body).to include(%(<form class="game-pick dock" id="game-pick" method="get" action="/date/#{day}/club/padel-club-2/game">))
      end

      # Counted from the page's midnight, like the Share screen's pickers, so
      # a game from 23:00 to 01:00 comes out forwards.
      it "counts the hours after midnight on from the evening they belong to" do
        sign_in
        get "/date/#{day}/club/kus-tba-padel"

        expect(tickable.last(3)).to eq([23, 24, 25])
      end

      it "offers no tick on an hour that is already over" do
        sign_in
        get "/date/#{today}/club/padel-club-2"

        over = (8..23).count { Booking::Clock.local_to_utc(format("%s %02d:00", today, _1)) + 3600 <= Booking::Clock.now }
        expect(tickable).to eq((8 + over..23).to_a)
      end
    end

    describe "the message" do
      before { forecast.replace([Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc("#{day} 20:00"), rain_chance: 80, rain_mm: 2.0, code: 61, temperature: 13.6, day: false)], city: "Tbilisi") }

      it "is not served to somebody without a session" do
        get "/date/#{day}/club/kus-tba-padel/game", hours: %w[19 20]

        expect(last_response.location).to end_with("/start")
      end

      it "runs from the first hour ticked to the end of the last" do
        sign_in
        get "/date/#{day}/club/kus-tba-padel/game", hours: %w[19 20]

        expect(preview).to include("🎾 Court booked · Kus Tba Padel\n#{day.strftime("%a %-d %b")}, 19:00–21:00")
        expect(last_response.body).to include('<option value="19" selected>').and include('<option value="21" selected>')
      end

      # A Game is one stretch: the hour between two ticks comes with them,
      # and the preview shows it before anything leaves.
      it "takes the hours between two ticks as well" do
        sign_in
        get "/date/#{day}/club/kus-tba-padel/game", hours: %w[19 21]

        expect(preview).to include("19:00–22:00")
      end

      it "is moved by its two pickers" do
        sign_in
        get "/date/#{day}/club/kus-tba-padel/game", from: 23, to: 25

        expect(preview).to include("23:00–01:00")
        expect(preview).to include("/game/kus-tba-padel/#{day}/23-25")
      end

      it "says where, what the sky does over the wettest hour, and the pin" do
        sign_in
        get "/date/#{day}/club/kus-tba-padel/game", hours: %w[19 20]

        expect(preview).to include("🌧 Rain 80% · 14°")
        expect(preview).to include("📍 Turtle Lake https://www.google.com/maps/search/?api=1&query=41.700688,44.7570599")
        expect(preview).to include("📅 Add to calendar: http://example.org/game/kus-tba-padel/#{day}/19-21")
      end

      it "sends through Telegram's share sheet exactly the text it previews" do
        sign_in
        get "/date/#{day}/club/kus-tba-padel/game", hours: %w[19 20]

        expect("#{shared_text}\n\nvia https://t.me/kortuli_test_bot").to eq(preview)
      end

      it "puts it in the sender's own calendar in one tap, either kind" do
        sign_in
        get "/date/#{day}/club/kus-tba-padel/game", hours: %w[19 20]

        expect(last_response.body).to include("https://calendar.google.com/calendar/render?action=TEMPLATE")
        expect(last_response.body).to include(%(href="http://example.org/game/kus-tba-padel/#{day}/19-21.ics"))
      end

      # Nothing ticked — a press without JS — or a span the club does not
      # sell: back to the hours, to tick again.
      it "goes back to the hours when there is nothing to share" do
        sign_in
        get "/date/#{day}/club/kus-tba-padel/game"
        expect(last_response.location).to end_with("/date/#{day}/club/kus-tba-padel")

        get "/date/#{day}/club/kus-tba-padel/game", from: 3, to: 5
        expect(last_response.location).to end_with("/date/#{day}/club/kus-tba-padel")
      end

      it "is 404 for a club nobody watches" do
        sign_in
        get "/date/#{day}/club/no-such-club/game", hours: %w[19]

        expect(last_response.status).to eq(404)
      end
    end

    # The link in the message. The people it is sent to need not use the bot,
    # so it opens without a session.
    describe "the page the group opens" do
      it "opens without a session, and says what is booked" do
        get "/game/kus-tba-padel/#{day}/19-21"

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include("Kus Tba Padel").and include("19:00–21:00")
        expect(last_response.body).to include("https://calendar.google.com/calendar/render?action=TEMPLATE")
        expect(last_response.body).to include(%(href="http://example.org/game/kus-tba-padel/#{day}/19-21.ics"))
        expect(last_response.body).to include("https://www.google.com/maps/search/?api=1&amp;query=41.700688,44.7570599")
      end

      # Padel Club 2 has no Profile, so there is no pin to drop.
      it "offers no map for a club without a pin" do
        get "/game/padel-club-2/#{day}/19-20"

        expect(last_response.status).to eq(200)
        expect(last_response.body).not_to include("Google Maps")
      end

      # A link in a chat outlives the week it was sent in.
      it "still opens once the game has gone by" do
        get "/game/kus-tba-padel/#{today - 30}/19-21"

        expect(last_response.status).to eq(200)
      end

      it "is 404 for a club nobody watches, a span the club does not sell, or a date that is not one" do
        ["/game/no-such-club/#{day}/19-21", "/game/kus-tba-padel/#{day}/3-5", "/game/kus-tba-padel/#{day}/21-19",
         "/game/kus-tba-padel/2026-02-31/19-21"].each do |path|
          get path

          expect(last_response.status).to eq(404), path
        end
      end

      describe "as a calendar file" do
        before { get "/game/kus-tba-padel/#{day}/23-25.ics" }

        it "is served as one, inline, so a phone offers to add it" do
          expect(last_response.status).to eq(200)
          expect(last_response.content_type).to start_with("text/calendar")
          expect(last_response.headers["Content-Disposition"]).to start_with("inline")
        end

        it "is the hours of the game, past midnight included" do
          body = last_response.body.gsub("\r\n ", "")

          expect(body).to include("DTSTART:#{Booking::Calendar.stamp(Booking::Clock.local_to_utc("#{day} 23:00"))}")
          expect(body).to include("DTEND:#{Booking::Calendar.stamp(Booking::Clock.local_to_utc("#{day + 1} 01:00"))}")
          expect(body).to include("URL:http://example.org/game/kus-tba-padel/#{day}/23-25")
        end
      end
    end
  end

  describe "the forecast" do
    let(:tomorrow) { today + 1 }

    def forecast_hour(at, chance:, temperature: 14.0)
      Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc(at), rain_chance: chance, rain_mm: 0.0,
                                 code: 3, temperature:, day: false)
    end

    def club_names_in_order = last_response.body.scan(%r{<span class="club-row__name">([^<]+)</span>}).flatten

    describe "with rain likely in the evening" do
      before do
        forecast.replace((8..23).map { forecast_hour("#{tomorrow} #{format("%02d", _1)}:00", chance: [19, 20].include?(_1) ? 80 : 0) }, city: "Tbilisi")
      end

      it "says when it will rain above the date's clubs" do
        sign_in
        get "/date/#{tomorrow}"

        expect(last_response.body).to include("Rain likely 19:00–21:00")
        expect(last_response.body).to include(Booking::Messages.weather_roofed_first)
      end

      # Kus Tba's courts are all in the open. Starred, it would lead; on a
      # wet evening the club with a roof — or at least not known to lack
      # one — comes first anyway.
      it "sinks the clubs entirely in the open, even a favourite" do
        sign_in(user_id: 42)
        favourites.add(42, "kus-tba-padel")
        get "/date/#{tomorrow}"

        expect(club_names_in_order).to eq(["Padel Club 2", "Kus Tba Padel"])
      end

      it "marks each hour wet or not beside it" do
        sign_in
        get "/date/#{tomorrow}/club/kus-tba-padel"

        expect(last_response.body).to include('<span class="hour__weather is-wet" title="🌧 Rain 80% · 14°">☂ 80% · 14°</span>')
        expect(last_response.body).to include('<span class="hour__weather" title="☁️ 14°">14°</span>')
      end

      it "marks the date as rainy on the home screen" do
        sign_in
        get "/"

        expect(last_response.body.scan('class="rain-chip"').size).to eq(1)
      end
    end

    describe "with a dry day" do
      before { forecast.replace((8..23).map { forecast_hour("#{tomorrow} #{format("%02d", _1)}:00", chance: 0) }, city: "Tbilisi") }

      it "says it will stay dry, and leaves the favourites leading" do
        sign_in(user_id: 42)
        favourites.add(42, "kus-tba-padel")
        get "/date/#{tomorrow}"

        expect(last_response.body).to include("No rain expected").and include("14–14°")
        expect(club_names_in_order).to eq(["Kus Tba Padel", "Padel Club 2"])
      end
    end

    # Before the poller's first refresh, or past the end of what it fetched.
    it "draws nothing where there is no forecast" do
      sign_in
      get "/date/#{tomorrow}"
      expect(last_response.body).not_to include('class="weather')

      get "/date/#{tomorrow}/club/kus-tba-padel"
      expect(last_response.body).not_to include("hour__weather")
    end
  end

  describe "picking a city" do
    let(:day) { today + 1 }
    # Padel Club 2 and Kus Tba say no city, so they are Tbilisi's, as every
    # entry was before there was a second.
    let(:padel_port) do
      Booking::Club.new(
        slug: "padel-port", name: "Padel Port", adapter: "reservio",
        settings: { "city" => "Batumi", "opening_hours" => { "from" => "08:00", "to" => "24:00" },
                    "courts" => 4, "booking_url" => "https://padel-port.example/" }
      )
    end
    let(:batumi_clubs) { [*clubs, padel_port] }
    let(:repos) { FakeRepos.new(FakeClubs.new(batumi_clubs), FakeSlots.new(free_slots), watches, favourites, forecast, visits, preferences) }
    let(:free_slots) do
      [slot(club: "padel-club-2", at: "#{day} 18:00"), slot(club: "kus-tba-padel", court: "any", at: "#{day} 18:00"),
       slot(club: "padel-port", at: "#{day} 19:00")]
    end

    def club_names_in_order = last_response.body.scan(%r{<span class="club-row__name">([^<]+)</span>}).flatten

    def switch = last_response.body[%r{<dialog class="city-sheet".*?</dialog>}m].to_s

    def pill = last_response.body[%r{<a class="city-pill.*?</a>}m].to_s

    def preview = CGI.unescapeHTML(last_response.body[%r{<pre class="copy-source"[^>]*>(.*?)</pre>}m, 1].to_s)

    def pick(city, back: "/") = post("/city", city:, back:)

    describe "with one city" do
      let(:batumi_clubs) { clubs }

      # Nowhere else to go, so nothing to pick between.
      it "draws no switch, and names the city the clubs are in" do
        sign_in
        get "/"

        expect(last_response.body).not_to include("city-picker")
        expect(last_response.body).to include("Free padel courts across Tbilisi.")
      end
    end

    # The home screen asks first (see city_spec); every other screen starts
    # in Tbilisi until somebody picks.
    it "starts in Tbilisi, with a switch to every city that has a club" do
      sign_in
      get "/clubs"

      expect(switch).to include('value="Tbilisi" checked').and include('value="Batumi"')
      # The pill in the header opens the picker: it names the city, and the
      # picker posts back to the screen it was opened on.
      expect(pill).to include("Tbilisi")
      expect(switch).to include('action="/city"').and include('name="back" value="/clubs"')
      get "/date/#{day}"
      expect(club_names_in_order).to contain_exactly("Padel Club 2", "Kus Tba Padel")
    end

    it "lands back on the screen the switch was pressed on" do
      sign_in
      pick("Batumi", back: "/clubs")

      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/clubs")
    end

    # The path comes from the page; only the screens the switch is drawn on
    # are somewhere to go back to.
    it "sends anything else back to the dates" do
      sign_in
      pick("Batumi", back: "https://example.com/elsewhere")

      expect(URI(last_response.location).path).to eq("/")
    end

    it "refuses a city no club is in" do
      sign_in
      pick("Gori")

      expect(last_response.status).to eq(404)
      expect(preferences.city(42)).to be_nil
    end

    it "is not served to somebody without a session" do
      pick("Batumi")

      expect(last_response.location).to end_with("/start")
    end

    describe "once Batumi is picked" do
      before do
        sign_in(user_id: 42)
        pick("Batumi")
      end

      it "counts only Batumi's free hours on the dates" do
        get "/"

        expect(last_response.body).to include("Free padel courts across Batumi.")
        expect(switch).to include('value="Batumi" checked')
        row = last_response.body[%r{href="/date/#{day}".*?</a>}m].to_s
        expect(row).to include('<span class="day-row__slots">1</span>')
      end

      it "lists only Batumi's clubs on a date" do
        get "/date/#{day}"

        expect(club_names_in_order).to eq(["Padel Port"])
      end

      it "shares only Batumi's clubs" do
        get "/date/#{day}/share"

        expect(preview).to include("Padel Port")
        expect(preview).not_to include("Kus Tba Padel")
        expect(preview).not_to include("Padel Club 2")
      end

      it "lists only Batumi's clubs in the directory" do
        get "/clubs"

        expect(last_response.body).to include("1 watched")
        expect(switch).to include('value="Batumi" checked')
        expect(last_response.body).to include('href="/clubs/padel-port"')
        expect(last_response.body).not_to include('href="/clubs/kus-tba-padel"')
      end

      # A Watch names clubs, so the form offers the ones in the city picked.
      it "offers only Batumi's clubs to watch" do
        get "/watches/new"

        expect(last_response.body).to include('name="club_slugs[]" value="padel-port"')
        expect(last_response.body).not_to include('name="club_slugs[]" value="kus-tba-padel"')
        # The picker's form sits in the header, outside the watch's, which
        # HTML would otherwise swallow.
        expect(last_response.body.index('<form class="city-picker')).to be < last_response.body.index('<form class="new-watch"')
        expect(switch).to include('value="Batumi" checked')
      end

      it "still lists every watch, whatever city its clubs are in" do
        watches.create(user_id: 42, club_slugs: ["kus-tba-padel"], weekdays: [1], from_minute: 18 * 60, to_minute: 22 * 60)
        get "/watches"

        expect(last_response.body).to include("Kus Tba Padel")
      end

      # A club's own screens are reached by its slug, from a link that may
      # have been made while the other city was picked.
      it "still opens a Tbilisi club's hours and Profile" do
        get "/date/#{day}/club/kus-tba-padel"
        expect(last_response.status).to eq(200)

        get "/clubs/kus-tba-padel"
        expect(last_response.status).to eq(200)
      end

      it "keeps the favourites chip to Batumi's favourites" do
        favourites.add(42, "kus-tba-padel")
        favourites.add(42, "padel-port")
        get "/date/#{day}?only=favourites"

        expect(club_names_in_order).to eq(["Padel Port"])
      end

      # Padel Port has no Profile, so it is not known to have a roof.
      it "keeps the roof chip working inside the city" do
        get "/date/#{day}?only=covered"

        expect(club_names_in_order).to be_empty
        expect(last_response.body).to include("No club with a roof has anything on this day.")
      end

      it "is remembered for the next visit, and for nobody else" do
        get "/"
        expect(last_response.body).to include("across Batumi")

        sign_in(user_id: 99)
        get "/clubs"
        expect(last_response.body).to include('href="/clubs/kus-tba-padel"')
        expect(last_response.body).not_to include('href="/clubs/padel-port"')
      end
    end

    # Each club reads the sky over its own city: a wet evening in Batumi
    # says nothing about Tbilisi's open courts, and the other way round.
    describe "the forecast" do
      def hour(at, chance:, temperature:)
        Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc(at), rain_chance: chance, rain_mm: 0.0,
                                   code: 3, temperature:, day: false)
      end

      before do
        forecast.replace((8..23).map { hour(format("%s %02d:00", day, _1), chance: 0, temperature: 15.0) }, city: "Tbilisi")
        forecast.replace((8..23).map { hour(format("%s %02d:00", day, _1), chance: _1 == 20 ? 80 : 0, temperature: 22.0) }, city: "Batumi")
        sign_in(user_id: 42)
      end

      it "heads a date with the picked city's weather" do
        get "/date/#{day}"
        expect(last_response.body).to include("No rain expected")

        pick("Batumi")
        get "/date/#{day}"
        expect(last_response.body).to include("Rain likely 20:00–21:00")
      end

      it "marks the rainy date on the picked city's home screen alone" do
        pick("Tbilisi")
        get "/"
        expect(last_response.body).to include('class="dates')
        expect(last_response.body).not_to include('class="rain-chip"')

        pick("Batumi")
        get "/"
        expect(last_response.body.scan('class="rain-chip"').size).to eq(1)
      end

      it "puts the picked city's weather into the Rundown" do
        pick("Batumi")
        get "/date/#{day}/share"

        expect(preview).to include("Rain likely 20:00–21:00")
      end

      it "marks a club's hours with its own city's weather, whichever is picked" do
        pick("Batumi")
        get "/date/#{day}/club/kus-tba-padel"

        expect(last_response.body).to include("15°")
        expect(last_response.body).not_to include("22°")
      end

      it "gives a Game the weather of the club's city" do
        get "/game/padel-port/#{day}/20-21"

        expect(last_response.body).to include("80% · 22°")
      end
    end
  end

  describe "counting visits" do
    def visitors = db[:visits].select_map(%i[user_id date])

    it "counts a signed-in person once a day, however many screens they open" do
      sign_in(user_id: 42)
      get "/"
      get "/clubs"

      expect(visitors).to eq([[42, today]])
    end

    it "counts nobody who has not signed in" do
      get "/"

      expect(visitors).to be_empty
    end

    it "leaves the owner out of their own count" do
      sign_in(user_id: owner_id)
      get "/"

      expect(visitors).to be_empty
    end
  end

  describe "the dashboard" do
    def log(process, *lines)
      File.write(Booking::Ops::LogFile.path(log_dir, process), lines.map { "#{_1}\n" }.join, encoding: Encoding::UTF_8)
    end

    before do
      Booking::Repo::Clubs.new(db).upsert(slug: "padel-club-2", name: "Padel Club 2", adapter: "reservio")
      Booking::Repo::Polls.new(db).record("padel-club-2", outcome: :failed, summary: "failed — timeout")
      Booking::Ops::Heartbeat.new(dir: log_dir, process: "poller").beat
      log("poller", "2026-10-11T10:04:00Z poll padel-club-2: failed — timeout", "2026-10-11T10:05:00Z poll kus-tba-padel: 40 free")
      log("bot", "2026-10-11T10:02:00Z telegram: <script>alert(1)</script> listening")
    end

    it "sends somebody without a session to /start" do
      get "/admin"

      expect(last_response).to be_redirect
      expect(last_response.location).to end_with("/start")
    end

    # Anybody else gets the same answer as for a page that is not there.
    it "does not exist for anybody but the owner" do
      sign_in(user_id: 42)

      get "/admin"
      expect(last_response.status).to eq(404)
      get "/admin/logs?q=poll"
      expect(last_response.status).to eq(404)
    end

    it "is linked from the dates screen for the owner alone" do
      sign_in(user_id: 42)
      get "/"
      expect(last_response.body).not_to include('href="/admin"')

      sign_in(user_id: owner_id)
      get "/"
      expect(last_response.body).to include('href="/admin"')
    end

    describe "for the owner" do
      before { sign_in(user_id: owner_id) }

      it "shows which processes are beating and how each club's last poll went" do
        get "/admin"

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include("poller", "state--up", "state--missing")
        expect(last_response.body).to include("Padel Club 2", "failed — timeout", "state--failed")
      end

      it "weighs the database, the disk under it, and the last day's activity" do
        get "/admin"

        expect(last_response.body).to include("Database", "Disk", "Active watches", "rows", "Forecast")
      end

      it "ages the Forecast city by city" do
        Booking::Repo::Clubs.new(db).upsert(slug: "padel-port", name: "Padel Port", adapter: "reservio", settings: { city: "Batumi" })
        hour = Booking::Weather::Hour.new(starts_at: Time.now.utc, rain_chance: 0, rain_mm: 0.0, code: 1, temperature: 18.0, day: true)
        forecast.replace([hour], city: "Tbilisi", fetched_at: Time.now.utc - 600)

        get "/admin"

        expect(last_response.body).to include("<dt>Tbilisi</dt>", "fetched 10m ago · 1 hours")
        expect(last_response.body).to include("<dt>Batumi</dt>", "never fetched · 0 hours")
      end

      it "says how many people open the app, and how many are new" do
        visits.record(42, on: today)

        get "/admin"

        expect(last_response.body).to include("Visitors", "1 opened the app", "1 new")
      end

      it "lists the latest lines that report trouble" do
        get "/admin"

        expect(last_response.body).to include("2026-10-11T10:04:00Z poll padel-club-2: failed — timeout")
        expect(last_response.body).not_to include("kus-tba-padel: 40 free")
      end

      it "searches the logs, marking what matched" do
        get "/admin/logs", q: "KUS-TBA"

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include("<mark>kus-tba</mark>-padel: 40 free")
        expect(last_response.body).not_to include("telegram:")
      end

      it "narrows the search to one process, or to trouble" do
        get "/admin/logs", process: "bot"
        expect(last_response.body).to include("listening")
        expect(last_response.body).not_to include("poll padel-club-2")

        get "/admin/logs", problems: "1"
        expect(last_response.body).to include("failed — timeout")
        expect(last_response.body).not_to include("listening")
      end

      it "escapes what the log says, so a line cannot become markup" do
        get "/admin/logs", q: "<script>"

        expect(last_response.body).to include("<mark>&lt;script&gt;</mark>alert(1)")
        expect(last_response.body).not_to include("<script>alert(1)")
      end

      it "says so when nothing matches" do
        get "/admin/logs", q: "nothing like this"

        expect(last_response.body).to include("Nothing in the logs matches.")
      end
    end
  end

  describe "the health endpoint" do
    it "answers without a session" do
      get "/up"

      expect(last_response.status).to eq(200)
    end
  end
end
