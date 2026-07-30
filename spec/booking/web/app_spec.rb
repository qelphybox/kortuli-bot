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
      expect(last_response.body).to include('class="dates"')
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

    # There is no menu but Telegram's own, so the CTA on the home screen has
    # to be the way in to making a watch.
    it "reaches the create-a-watch form" do
      sign_in
      get "/"

      expect(last_response.body).to include('href="/watches/new"')
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
  end

  describe "the slots screen" do
    # Every hour the page invites a tap on. Reading them back is how "the
    # screen offers exactly what the route accepts" gets checked from the
    # outside.
    def offered_hours
      last_response.body.scan(/name="starts_at" value="([^"]+)"/).flatten.map { Time.iso8601(_1) }
    end

    it "labels the hours the club sells" do
      sign_in
      get "/date/#{today + 1}/club/kus-tba-padel"

      expect(last_response.body).to include("08:00").and include("19:00")
    end

    it "is 404 when the club is not among the enabled ones" do
      sign_in
      get "/date/#{today}/club/no-such-club"

      expect(last_response.status).to eq(404)
    end

    describe "a free hour" do
      let(:free_slots) { [slot(club: "kus-tba-padel", court: "any", at: "#{today + 1} 19:00")] }

      # Tapping a free Cell has to leave the app entirely — we do not book, we
      # hand over. The link is marked so the client opens it through Telegram
      # rather than inside the mini app's own webview.
      it "links out to the club that owns it" do
        sign_in
        get "/date/#{today + 1}/club/kus-tba-padel"

        expect(last_response.body).to include("https://example.test/book")
        expect(last_response.body).to include("data-external")
      end
    end

    describe "an hour with nothing free" do
      it "is drawn, but goes nowhere" do
        sign_in
        get "/date/#{today}/club/padel-club-2"

        expect(last_response.body).not_to include("data-external")
      end

      # The main scenario, in one tap: you see the hour is gone, and you ask
      # to be told when it is not — without leaving the screen.
      it "offers a watch on exactly that hour" do
        sign_in
        get "/date/#{today + 1}/club/padel-club-2"

        expect(last_response.body).to include('action="/watches/dated"')
        expect(last_response.body).to include(Booking::Clock.local_to_utc("#{today + 1} 19:00").iso8601)
      end

      # Today's row still shows the hours that have been and gone. Nothing can
      # be asked about them, so they are drawn without a button rather than
      # with one that would refuse.
      it "offers nothing on an hour that has already started" do
        sign_in
        get "/date/#{today}/club/padel-club-2"

        expect(offered_hours).to all(be > Booking::Clock.now)
      end

      # Kus Tba's day runs to 02:00, so the last page of the horizon draws
      # hours that fall on the day *after* it — which nobody has polled. The
      # button must not be offered where the tap would only be refused.
      it "offers nothing on an hour beyond the horizon, even where the screen draws it" do
        sign_in
        get "/date/#{today + Booking::Config.horizon_days - 1}/club/kus-tba-padel"

        expect(offered_hours.map { Booking::Clock.local_date(_1) }).to all(be <= today + Booking::Config.horizon_days - 1)
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

    # The create form names every club, so "is this watch on the screen" has to
    # ask the list rather than the page. Empty when there is no list at all.
    def listed = last_response.body[%r{<ul class="watches">.*</ul>}m].to_s

    it "is not served to somebody without a session" do
      get "/watches"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/start")
    end

    # There is no link to keep anywhere and no menu but Telegram's own, so the
    # two screens have to reach each other.
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

    # Tapping a taken Cell. A Dated watch is a narrowing of the Watch that
    # already exists, so what this checks is that the narrowing is right: the
    # date's weekday, that single hour, and the date itself.
    describe "asking about one taken hour" do
      # Tomorrow rather than today, so the hour is still ahead however late in
      # the day the suite runs — an hour that has started is one the list
      # rightly stops showing.
      let(:on) { today + 1 }
      let(:at) { Booking::Clock.local_to_utc("#{on} 19:00") }

      def tap_cell(club_slug: "padel-club-2", starts_at: at.iso8601)
        post "/watches/dated", club_slug:, starts_at:
      end

      it "needs no further configuration" do
        sign_in(user_id: 42)

        tap_cell

        watch = watches.for_user(42).first
        expect(watch).to be_dated
        expect(watch.club_slugs).to eq(Set["padel-club-2"])
        expect(watch.date).to eq(on)
        expect(watch.weekdays).to eq(Set[on.wday])
        expect(watch.from_minute).to eq(19 * 60)
        expect(watch.to_minute).to eq(20 * 60)
      end

      it "shows up in the list, told apart from a standing watch" do
        sign_in(user_id: 42)

        tap_cell
        get "/watches"

        expect(listed).to include("Dated")
      end

      # Two watches on one hour would mean two messages about it, which the
      # notifications index cannot prevent — it dedupes per watch.
      it "does not stack up when the same hour is tapped twice" do
        sign_in(user_id: 42)

        tap_cell
        tap_cell

        expect(watches.for_user(42).size).to eq(1)
      end

      it "lets a different hour be asked about separately" do
        sign_in(user_id: 42)

        tap_cell
        tap_cell(starts_at: Booking::Clock.local_to_utc("#{on} 20:00").iso8601)

        expect(watches.for_user(42).size).to eq(2)
      end

      it "refuses a club that is not watched" do
        sign_in(user_id: 42)

        tap_cell(club_slug: "some-club-we-do-not-poll")

        expect(watches.for_user(42)).to be_empty
        expect(last_response.status).to eq(422)
      end

      it "refuses an hour nobody has polled" do
        sign_in(user_id: 42)

        tap_cell(starts_at: Booking::Clock.local_to_utc("#{today + 90} 19:00").iso8601)

        expect(watches.for_user(42)).to be_empty
        expect(last_response.status).to eq(422)
      end

      it "refuses something that is not a time at all" do
        sign_in(user_id: 42)

        tap_cell(starts_at: "half past whenever")

        expect(watches.for_user(42)).to be_empty
        expect(last_response.status).to eq(422)
      end

      # An hour that has started cannot be played, so a watch on it would be
      # created already expired — invisible in the list and unmatchable by the
      # Matcher. A tap that silently does nothing is worse than a refusal.
      it "refuses an hour that has already started" do
        sign_in(user_id: 42)

        tap_cell(starts_at: (Booking::Clock.now - 3600).iso8601)

        expect(watches.for_user(42)).to be_empty
        expect(last_response.status).to eq(422)
      end

      it "cannot be done without a session" do
        tap_cell

        expect(watches.active).to be_empty
      end

      # Tapping means "tell me about this hour". Finding a paused watch already
      # on it and doing nothing would answer with a success the person cannot
      # see, so the tap resumes it instead of quietly no-opping.
      it "wakes a paused watch on that hour rather than doing nothing" do
        sign_in(user_id: 42)
        tap_cell
        paused = watches.for_user(42).first
        watches.set_active(paused.id, false)

        tap_cell

        expect(watches.for_user(42).size).to eq(1)
        expect(watches.find(paused.id)).to be_active
      end

      # Kus Tba runs to 02:00, so its 00:00 and 01:00 cells are drawn under the
      # evening they belong to — the page date and the hour's own date differ.
      describe "an hour after midnight" do
        let(:after_midnight) { Booking::Clock.local_to_utc("#{today + 2} 01:00") }

        it "is filed under its own date, not the page it was tapped from" do
          sign_in(user_id: 42)

          post "/watches/dated",
               club_slug: "kus-tba-padel", starts_at: after_midnight.iso8601, date: (today + 1).to_s

          watch = watches.for_user(42).first
          expect(watch.date).to eq(today + 2)
          expect(watch.weekdays).to eq(Set[(today + 2).wday])
          expect(watch.from_minute).to eq(60)
          expect(watch.to_minute).to eq(120)
        end

        it "returns to the page it was tapped from" do
          sign_in(user_id: 42)

          post "/watches/dated",
               club_slug: "kus-tba-padel", starts_at: after_midnight.iso8601, date: (today + 1).to_s

          expect(last_response.location).to end_with("/date/#{today + 1}/club/kus-tba-padel")
        end
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

      it "offers the weekdays and both ends of the range on the same form" do
        sign_in(user_id: 42)

        get "/watches/new"

        form = last_response.body[%r{<form class="new-watch".*?</form>}m].to_s
        expect(form).to include('name="weekdays[]"').and include("Mon").and include("Sun")
        expect(form).to include('name="from_hour"').and include('name="to_hour"')
        # The whole point of the ticket: one submit, not four messages.
        expect(form.scan(/<button|type="submit"/).size).to eq(1)
      end

      it "takes clubs, weekdays and both ends of the range in one step" do
        sign_in(user_id: 42)

        submit
        # A successful submit lands on the confirm screen; the list is one
        # more click on from there.
        get "/watches"

        expect(listed).to include("Padel Club 2").and include("Mon, Fri · 19:00–22:00")
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
  describe "the health endpoint" do
    it "answers without a session" do
      get "/up"

      expect(last_response.status).to eq(200)
    end
  end
end
