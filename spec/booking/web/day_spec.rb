require "rack/test"
require "tmpdir"

# The day screens — the week, a date's clubs, one club's hours — on what
# their redesign added: how fresh the week is, a club we could not read told
# apart from a fully booked one, and whom the rain falls on. Set up as the
# app spec is: Clubs and Slots stood in for, everything the web reads or
# writes besides them real over an in-memory database.
RSpec.describe Booking::Web::App do
  include Rack::Test::Methods

  DayRepos = Struct.new(:clubs, :slots, :watches, :favourites, :forecast, :visits, :preferences, :polls, :notifications, :day_opens)
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
                 forecast, Booking::Repo::Visits.new(db), Booking::Repo::Preferences.new(db), polls,
                 Booking::Repo::Notifications.new(db), Booking::Repo::DayOpens.new(db))
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

  def cards = last_response.body.scan(%r{<a class="day-club".*?</a>}m)

  def card(name) = cards.find { _1.include?(%(<span class="day-club__name">#{name}</span>)) }.to_s

  def folded(name) = last_response.body.scan(%r{<a class="fold__club".*?</a>}m).find { _1.include?(">#{name}<") }.to_s

  def club_names_in_order = last_response.body.scan(%r{<span class="(?:day-club|fold)__name">([^<]+)</span>}).flatten

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

    # Every day as good as any other: today wears a badge, and nothing more.
    it "draws every day as an equal row, today with a badge" do
      get "/"

      expect(last_response.body.scan(/<a class="day-row[" ]/).size).to eq(Booking::Config.horizon_days)
      expect(last_response.body.scan('class="today-badge"').size).to eq(1)
      expect(last_response.body).not_to include('class="hero')
    end

    it "draws each day's bar as a value rather than a style" do
      get "/"

      expect(last_response.body).to include(%(<progress class="meter-bar" max="100" value="100" aria-hidden="true">))
      expect(last_response.body).not_to include('style="width')
    end
  end

  # Over the week, only when a watch has fired and the slot is still free.
  describe "a watch that fired" do
    let(:watches) { Booking::Repo::Watches.new(db) }
    let(:notifications) { Booking::Repo::Notifications.new(db) }
    let(:free_slots) { [slot(club: "gldani", at: "#{day} 18:00"), slot(club: "gldani", at: "#{day} 21:00")] }

    def banner = last_response.body[%r{<section class="hit".*?</section>}m].to_s

    def told(slot, user_id: 42, at: ago(4 * 60))
      watch = watches.create(user_id:, club_slugs: ["gldani"], weekdays: [day.wday], from_minute: 18 * 60, to_minute: 22 * 60)
      notifications.claim(watch_id: watch.id, slot_key: slot.key, at:)
    end

    it "shows the slot big, with the club, the watch it matched and the way to book" do
      told(free_slots.first)
      get "/"

      expect(banner).to include("Slot opened").and include("4 min ago")
      expect(banner).to include("#{Booking::Messages::DAY_NAMES[day.wday]} · 18:00–19:00")
      expect(banner).to include("Padel Gldani").and include("covered + outdoor · 80 GEL/h")
      expect(banner).to include("Matches your watch: #{Booking::Messages::DAY_NAMES[day.wday]} · 18:00–22:00")
      expect(banner).to include('data-external href="https://example.test/book"')
      expect(banner).to include(%(href="/date/#{day}/club/gldani">All hours))
    end

    it "is gone once the slot is taken again" do
      told(slot(club: "gldani", at: "#{day} 19:00"))
      get "/"

      expect(banner).to be_empty
    end

    it "is nobody else's" do
      told(free_slots.first, user_id: 7)
      get "/"

      expect(banner).to be_empty
    end

    it "shows the soonest, and the rest as a count" do
      told(free_slots.last, at: ago(60))
      told(free_slots.first, at: ago(600))
      get "/"

      expect(banner).to include("18:00–19:00").and include("10 min ago")
      expect(banner).to include('<a class="hit__more" href="/watches">+1 more</a>')
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

    # Lemans was read and has nothing; Padel Academy could not be read.
    it "folds a club with nothing free, saying so, and one it could not read, saying that" do
      get "/date/#{day}?hours=any"

      expect(folded("Lemans Padel")).to include("nothing today")
      expect(folded("Padel Academy")).to include("no data")
    end

    it "says the same for a club that has never been polled" do
      db[:polls].where(club_slug: "academy").delete
      get "/date/#{day}?hours=any"

      expect(folded("Padel Academy")).to include("no data")
    end

    # What a failed Poll left behind is still the last thing we read.
    it "still shows the free hours a club had before its Poll failed" do
      polls.record("gldani", outcome: "failed", summary: "", at: ago(30))
      get "/date/#{day}?hours=18"

      expect(card("Padel Gldani")).to include(%(<span class="day-club__n">1h</span>))
    end

    it "folds the clubs in the order the list would have them, favourites first" do
      Booking::Repo::Favourites.new(db).add(42, "academy")
      get "/date/#{day}?hours=18"

      expect(club_names_in_order).to eq(["Padel Gldani", "Padel Academy", "Lemans Padel"])
    end

    # One link, the whole card, to the club's hours; the star lives there.
    it "makes the whole card one link to the club's hours" do
      get "/date/#{day}?hours=18"

      expect(card("Padel Gldani")).to start_with(%(<a class="day-club" href="/date/#{day}/club/gldani?hours=18">))
      expect(card("Padel Gldani")).not_to include("<form")
    end

    it "names the covers and the area beside a club with a Profile" do
      get "/date/#{day}?hours=18"

      expect(card("Padel Gldani")).to include('<span class="tag tag--covered">covered</span>').and include("Gldani · 80 GEL")
    end

    # Each opening is kept — the day, how far ahead, the hour — so the
    # week can one day lead with the day somebody plays on.
    describe "kept, to learn which days people play on" do
      def opens = db[:day_opens].select_map(%i[user_id date days_ahead booked_at shared_at])

      it "keeps each opening, but not a tap on its strip of hours" do
        get "/date/#{day}"
        header "X-Day-Swap", "1"
        get "/date/#{day}?hours=20"

        expect(opens).to eq([[42, day, 1, nil, nil]])
      end

      it "credits a Book tapped to the latest opening of that date" do
        get "/date/#{day}"
        post "/date/#{day}/booked"

        expect(last_response.status).to eq(204)
        expect(opens.first[3]).not_to be_nil
      end

      it "credits a Game shared, once" do
        get "/date/#{day}"
        get "/date/#{day}/club/gldani/game?hours[]=18"
        first = opens.first[4]
        get "/date/#{day}/club/gldani/game?hours[]=18"

        expect(first).not_to be_nil
        expect(opens.first[4]).to eq(first)
      end
    end

    describe "under the forecast" do
      def hour(at, chance:, temperature: 15)
        Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc(at), rain_chance: chance, rain_mm: 0.0,
                                   code: 3, temperature:, day: true)
      end

      def hint = last_response.body[%r{<(?:a|div) class="day-hint.*?</(?:a|div)>}m].to_s

      # Rain from 30%: a Wet hour is 50, but choosing between courts is not
      # calling the evening off.
      it "marks an hour rainy from a three-in-ten chance" do
        forecast.replace((8..23).map { hour(format("%s %02d:00", day, _1), chance: { 18 => 30, 19 => 20 }.fetch(_1, 0)) }, city: "Tbilisi")
        get "/date/#{day}"

        expect(last_response.body).to match(/class="hour-chip is-rainy"[^>]*data-hour="18"/)
        expect(last_response.body).not_to match(/class="hour-chip is-rainy"[^>]*data-hour="19"/)
      end

      # Lemans is indoors, and has the evening; Gldani is a favourite with a
      # court in the open and a roof over the other.
      describe "with rain over the evening" do
        let(:free_slots) do
          [slot(club: "gldani", at: "#{day} 18:00"), slot(club: "gldani", at: "#{day} 19:00"),
           slot(club: "lemans", at: "#{day} 18:00"), slot(club: "lemans", at: "#{day} 19:00")]
        end

        before do
          forecast.replace((8..23).map { hour(format("%s %02d:00", day, _1), chance: (17..22).cover?(_1) ? 70 : 0) }, city: "Tbilisi")
        end

        it "names a favourite with a roof that has the hours, in blue" do
          Booking::Repo::Favourites.new(db).add(42, "gldani")
          get "/date/#{day}"

          expect(hint).to start_with('<a class="day-hint day-hint--rain"')
          expect(hint).to include("Rain 17:00–23:00.").and include("Padel Gldani (your favourite, covered) has the whole 18:00–20:00 free.")
          expect(hint).to include(">Book<")
        end

        # Both have a roof; Lemans comes first by name.
        it "names the first roof when no favourite stays dry" do
          get "/date/#{day}"

          expect(hint).to start_with(%(<a class="day-hint day-hint--roof" href="/date/#{day}/club/lemans">))
          expect(hint).to include("Nearest roof: Lemans Padel, has the whole 18:00–20:00 free.").and include(">See<")
        end
      end

      it "names the first favourite with the hours free on a dry day" do
        Booking::Repo::Favourites.new(db).add(42, "gldani")
        get "/date/#{day}?hours=18"

        expect(hint).to start_with(%(<a class="day-hint day-hint--dry" href="/date/#{day}/club/gldani?hours=18">))
        expect(hint).to include("<strong>Padel Gldani</strong> has the whole 18:00–19:00 free.")
      end

      it "says the favourites have nothing, and how many other clubs do" do
        Booking::Repo::Favourites.new(db).add(42, "lemans")
        get "/date/#{day}?hours=18"

        expect(hint).to start_with('<div class="day-hint day-hint--none">')
        expect(hint).to include("No slots at your favourites 18:00–19:00.").and include("1 other club has.")
      end

      it "says nothing without a favourite on a dry day" do
        get "/date/#{day}?hours=18"

        expect(hint).to be_empty
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

    it "names the club's area, covers and price beside the date" do
      get "/date/#{day}/club/gldani"

      expect(last_response.body).to include(%(<div class="bar__sub">#{Booking::Messages::DAY_NAMES[day.wday]} · #{day.strftime("%b %-d")} · Gldani · covered + outdoor · 80 GEL/h</div>))
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
