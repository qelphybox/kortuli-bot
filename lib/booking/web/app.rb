require "sinatra/base"

module Booking
  module Web
    # The mini app. Thin on purpose, in the same way Telegram::Handlers is:
    # routes decide who is asking and what to render, and nothing else lives
    # here.
    class App < Sinatra::Base
      COOKIE = "kortuli_session".freeze

      set :views, File.expand_path("views", __dir__)
      set :public_folder, File.expand_path("public", __dir__)
      # Injected at boot by config.ru, and by the specs. Deliberately not read
      # from Config at load time: requiring this file must not demand a token,
      # or the poller could not load the library.
      #
      # `visitor_sessions` rather than `sessions` because Sinatra owns that
      # name — assigning to it switches on Rack's session middleware, which
      # this app does not use and which would ask for a secret of its own.
      set :telegram_token, nil
      set :visitor_sessions, nil
      set :repos, nil
      # The bot's public @handle, used to build the feedback pill's deeplink
      # into the bot chat. Injected rather than read from Config so the app is
      # renderable in specs without touching ENV.
      set :bot_username, nil
      # Each club's Profile by slug, loaded once at boot from the file
      # `rake sapadelo:import` writes. Static, so it is handed over rather
      # than kept in the database: nothing at runtime ever changes it.
      set :club_profiles, {}
      # The one person the dashboard opens for (the same OWNER_TELEGRAM_ID
      # that feedback is forwarded to), and what it reads. Injected like the
      # rest, so specs can stand both in.
      set :owner_id, nil
      set :dashboard, nil
      # Sinatra's own session middleware is not used — ours is one signed
      # cookie and nothing else — and its default error page leaks the app's
      # internals, so both stay off.
      set :show_exceptions, false
      set :logging, false
      # Sinatra 4 refuses unknown Host headers. That belongs to kamal-proxy
      # here: it is the only thing the outside world can reach, and it forwards
      # nothing whose Host is not the app's. Narrowing it a second time in here
      # buys nothing and costs a deploy — the proxy health-checks the container
      # by its *container id*, so a permitted-hosts list rejects the one
      # request that decides whether a release goes live.
      set :host_authorization, { permitted_hosts: [] }

      # Cheap cache-buster for static assets: mtime at boot, one integer, same
      # across the process's lifetime. Telegram's in-app webview caches CSS
      # and JS by URL and does not consult validators — a deploy that changes
      # only styles leaves every existing session on the old file until the
      # user manually clears the cache. Appending `?v=…` makes the URL new
      # for every deploy without asking Sinatra to compute anything per
      # request.
      ASSET_VERSION = [
        File.mtime(File.expand_path("public/app.css", __dir__)),
        File.mtime(File.expand_path("public/app.js", __dir__))
      ].max.to_i.to_s.freeze

      BYTE_UNITS = %w[B KB MB GB TB].freeze

      # The ways a date's clubs can be narrowed, beside "all of them".
      CLUB_FILTERS = %w[covered favourites].freeze

      # The screens the city switch is drawn on, and so the only places it
      # sends a person back to. Anything else lands on the dates: the path
      # arrives from the page, and a redirect to wherever it says is a
      # redirect anywhere.
      CITY_SWITCH_BACK = %r{\A/(?:clubs|watches/new)?\z}

      helpers Icons

      helpers do
        def visitor_id = settings.visitor_sessions.user_id(request.cookies[COOKIE])

        def asset_url(path) = "#{path}?v=#{ASSET_VERSION}"

        # The feedback pill's deeplink into the bot chat. `start=feedback`
        # arrives at the bot as `/start feedback`, which the handler answers
        # with the feedback prompt — the pill is a one-tap invitation to a
        # conversation, not a "please write /feedback" instruction card. See
        # ADR-0002.
        def feedback_url = "https://t.me/#{settings.bot_username}?start=feedback"

        def bot_url = "https://t.me/#{settings.bot_username}"

        # Telegram's own share sheet: pick a chat, and the text lands in its
        # input ready to send. No inline mode and no Bot API call — the client
        # does all of it. `url` is required by the endpoint, so it carries the
        # bot, which is also the honest answer to "where is this from?".
        # Percent-encoded rather than form-encoded: a `+` for a space is not
        # decoded back by every client.
        def share_url(text)
          "https://t.me/share/url?url=#{ERB::Util.url_encode(bot_url)}&text=#{ERB::Util.url_encode(text)}"
        end

        # The clipboard carries what the share sheet would, plus the bot link
        # the sheet adds on its own — it is headed for WhatsApp as often as not.
        def copy_text(text) = "#{text}\n\nvia #{bot_url}"

        def h(text) = Rack::Utils.escape_html(text)

        def require_visitor!
          redirect(to("/start")) unless visitor_id

          # Every signed-in screen is a Visit, unless it is the owner's: the
          # person who runs the bot opens it more than anybody, and would
          # drown the very count they are reading.
          settings.repos.visits.record(visitor_id, on: Clock.local_date(Clock.now)) unless owner?
        end

        def owner? = !settings.owner_id.nil? && visitor_id == settings.owner_id

        # Not 403, for the reason own_watch! gives: to anybody else the
        # dashboard does not exist.
        def require_owner!
          require_visitor!
          halt(404) unless owner?
        end

        def bytes(count)
          return "—" if count.nil?

          power = count < 1024 ? 0 : [Math.log(count, 1024).floor, BYTE_UNITS.size - 1].min
          power.zero? ? "#{count} B" : format("%.1f %s", count.fdiv(1024**power), BYTE_UNITS[power])
        end

        def percent(ratio) = "#{(ratio * 100).round}%"

        def ago(time, now: Clock.now)
          return "never" if time.nil?

          seconds = (now - time).to_i
          return "just now" if seconds < 5

          [[86_400, "d"], [3600, "h"], [60, "m"], [1, "s"]].each do |size, unit|
            return "#{seconds / size}#{unit} ago" if seconds >= size
          end
        end

        # The log line, escaped, with every occurrence of the search phrase
        # marked. Escaping first and then marking the escaped phrase keeps the
        # markup ours: nothing from the line can open a tag.
        def highlight(line, query)
          escaped = h(line)
          return escaped if query.to_s.strip.empty?

          escaped.gsub(/#{Regexp.escape(h(query.strip))}/i) { "<mark>#{_1}</mark>" }
        end

        # The dates the poller actually knows about. Anything outside this
        # would draw a page nobody has polled, which reads as a club that shut
        # down rather than as a question we cannot answer.
        def horizon
          today = Clock.local_date(Clock.now)

          (0...Config.horizon_days).map { today + _1 }
        end

        def parse_date(raw)
          date = Date.iso8601(raw.to_s)

          horizon.include?(date) ? date : nil
        rescue Date::Error
          nil
        end

        def hour_label(starts_at) = format("%02d", Clock.to_local(starts_at).hour)

        # The id arrives from the page, so ownership is checked rather than
        # assumed: the session says who is asking, never what is theirs. Not
        # 403 — that would confirm the watch exists to somebody who cannot see
        # it, and there is nothing they could do with the knowledge anyway.
        def own_watch!(id)
          require_visitor!
          watch = settings.repos.watches.find(Integer(id.to_s, exception: false))
          halt(404) unless watch && watch.user_id == visitor_id

          watch
        end

        def set_active!(id, active)
          settings.repos.watches.set_active(own_watch!(id).id, active)
          redirect(to("/watches"))
        end

        # Memoised per request: every watch on the screen asks for it. Every
        # city's, because a person's Watches are listed whatever city they
        # are looking at.
        def club_names = @club_names ||= enabled_clubs.to_h { [_1.slug, _1.name] }

        def watch_clubs(watch) = Messages.clubs_phrase(watch, club_names)

        # The form renders from the same lists Submission validates against, so
        # the two cannot answer differently about what was on offer.
        def weekday_choices = MONDAY_FIRST.map { [_1, Messages::DAY_NAMES[_1]] }

        def start_hours = START_HOURS
        def end_hours = END_HOURS

        def clock(hour) = Messages.clock(hour * 60)

        def profile(slug) = settings.club_profiles[slug]

        # Memoised per request: every club row on the screen asks for it.
        def favourites = @favourites ||= settings.repos.favourites.for_user(visitor_id)

        def favourite?(slug) = favourites.include?(slug)

        # Every city's: a star, a watch or a club's own page names its club by
        # slug, and the slug already says which city it is in.
        def enabled_slugs = enabled_clubs.map(&:slug)

        # Every City with an enabled club, the default first.
        def cities = @cities ||= Club.cities(enabled_clubs)

        # Only worth drawing when there is somewhere else to go.
        def city_switch? = cities.size > 1

        # The City whose clubs this person is shown: the one they last picked,
        # while it still has a club to show; otherwise the default, or
        # whichever city does have clubs. Memoised per request, like the
        # tables it decides.
        def current_city
          @current_city ||= begin
            picked = settings.repos.preferences.city(visitor_id)

            [picked, DEFAULT_CITY].find { cities.include?(_1) } || cities.first || DEFAULT_CITY
          end
        end

        # The clubs the dates, a date's list, Share, the directory and the
        # new-watch form are drawn from.
        def city_clubs = @city_clubs ||= enabled_clubs.select { _1.city == current_city }


        # A first visit has no submission to remember, so it starts from the
        # clubs this person has starred — the ones they would tick anyway.
        # Days and hours start blank: nothing to guess them from.
        def picked_club?(slug) = @submitted ? @submitted.picked_club?(slug) : favourite?(slug)
        def picked_day?(day) = !!@submitted&.picked_day?(day)
        def picked_hour?(hour, which) = @submitted&.public_send(which) == hour

        # A Dated watch names its one day; a Standing one names the weekdays it
        # keeps coming back on.
        def watch_days(watch) = watch.dated? ? day_label(watch.date) : Messages.days_phrase(watch.weekdays)

        def day_label(date) = date.strftime("%a %-d %b")

        def weekday_short(date) = Messages::DAY_NAMES[date.wday]

        def date_label(date) = date.strftime("%b %-d")

        # The list of Grid Tables the drill-down draws from. Built once per
        # request rather than per screen so the Dates counts, the Clubs sub-
        # lines and the Slots rows all read the same snapshot — a poll that
        # finishes mid-render cannot change what the person sees on one page.
        #
        # The current city's clubs only: one city's rows are what every screen
        # drawn from these shows.
        def horizon_tables
          @horizon_tables ||= horizon.to_h { [_1, Grid.build(clubs: city_clubs, slots: free_slots, date: _1)] }
        end

        def free_slots = @free_slots ||= settings.repos.slots.all

        # One club's own table for a date, whatever city it is in — its hours
        # and its Game are reached by slug, from a link that may have been
        # made while another city was picked.
        def club_table(date, club) = Grid.build(clubs: [club], slots: free_slots, date:)

        # A City's Forecast by the instant each hour starts, read once per
        # request for the same reason the tables are. The current city's
        # unless a club's own screen says otherwise.
        def forecast(city = current_city)
          @forecasts ||= {}
          @forecasts[city] ||= Weather.by_hour(settings.repos.forecast.hours(city))
        end

        def weather_at(starts_at, city = current_city) = forecast(city)[starts_at.to_i]

        # The Forecast over the hours a date's page draws that are still to
        # come — this morning's rain is no reason to book a roof tonight. Nil
        # where the Forecast has nothing to say, so nothing is drawn.
        def outlook(table, city: current_city, now: Clock.now)
          hours = table.columns.select { _1 + 3600 > now }.filter_map { weather_at(_1, city) }

          Weather::Outlook.new(hours:) if hours.any?
        end

        # Every court of the club in the open, as far as its Profile says. A
        # club without a Profile is not assumed to be either.
        def open_air?(slug)
          covers = profile(slug)&.covers.to_a

          covers.any? && covers.all? { |cover, _| cover == "outdoor" }
        end

        # At least one court under a roof — what "Covered" narrows a day to.
        def roofed?(slug) = profile(slug)&.covers.to_a.any? { |cover, _| cover != "outdoor" }

        # What a date's clubs are narrowed to: everything, the ones with a
        # roof, or the Favourites. Anything else is everything.
        def club_filter = CLUB_FILTERS.include?(params[:only]) ? params[:only] : nil

        def filter_clubs(clubs, only)
          case only
          when "covered" then clubs.select { _1[:roofed] }
          when "favourites" then clubs.select { _1[:favourite] }
          else clubs
          end
        end

        # The price a club declares in config, "80 GEL" or "40–70 GEL".
        def club_price(slug) = enabled_club(slug)&.settings&.fetch("price", nil)

        # The same price split for a big number and a small unit: ["80", "GEL"].
        def price_parts(slug)
          price = club_price(slug) or return nil
          amount, unit = price.split(" ", 2)

          [amount, unit]
        end

        # A club's courts, said in one tile: "8 outdoor courts" when they are
        # all alike, "5 courts" when they are not, nothing without a Profile.
        def courts_stat(slug)
          covers = profile(slug)&.covers.to_a
          return nil if covers.empty?

          count = covers.sum { _2 }
          noun = count == 1 ? "court" : "courts"
          [count, covers.size == 1 ? "#{covers.first.first} #{noun}" : noun]
        end

        # An hour's Forecast said small enough for a tile: "☂ 30% · 17°" when
        # rain is a question, just the temperature when it is not.
        def hour_weather(hour)
          temperature = ("#{hour.temperature.round}°" if hour.temperature)
          rain = (["☂", ("#{hour.rain_chance}%" if hour.rain_chance)].compact.join(" ") if hour.wet? || hour.damp?)

          [rain, temperature].compact.join(" · ")
        end

        # Two letters a club is recognised by in a list: "KT" for Kus Tba
        # Padel, "GR" for GymBreeze Radio City, "P2" for a "Padel Club 2"
        # (a number is what tells it apart), "PH" for PadelHub.
        def initials(name)
          words = name.split
          return "#{words.first[0]}#{words.last}".upcase if words.size > 1 && words.last.match?(/\A\d+\z/)
          return "#{words[0][0]}#{words[1][0]}".upcase if words.size > 1

          capitals = name.scan(/[[:upper:]]/)
          (capitals.size >= 2 ? capitals.first(2).join : name[0, 2]).upcase
        end

        def any_free?(table) = table.rows.any? { |row| row.cells.any?(&:free?) }

        # Every Club's last Poll by slug, read once per request like the
        # tables.
        def last_polls = @last_polls ||= settings.repos.polls.all

        # Nothing we hold about the club can be believed as "taken": its last
        # Poll could not read the source, or there has not been one. A club
        # with no free Cell is then unknown rather than fully booked.
        def no_data?(slug)
          poll = last_polls[slug]

          poll.nil? || poll.outcome == "failed"
        end

        # When the newest Poll that read one of the current City's clubs
        # finished. Nil before any has, so nothing is claimed.
        def city_updated_at = city_clubs.filter_map { last_polls[_1.slug] }.select(&:ok?).map(&:polled_at).max

        # One dict per horizon date, in the shape the Dates template reads.
        # A day with anything free names the number of clubs and the number
        # of hours; a day with nothing says "fully booked" and dims itself.
        # `share` is the day's free hours against the busiest day's, for the
        # bar under each row — relative, because "126 of how many?" has no
        # honest answer when clubs keep different hours.
        def dates_view
          days = horizon_tables.map do |date, table|
            open_clubs = table.rows.count { |row| row.cells.any?(&:free?) }
            free_cells = table.rows.sum { |row| row.cells.count(&:free?) }

            {
              date: date.to_s,
              weekday: weekday_short(date),
              date_label: date_label(date),
              today: date == horizon.first,
              any_free: open_clubs.positive?,
              weather: outlook(table)&.icon,
              open_clubs:,
              free_cells:,
              clubs_label: count_label(open_clubs, "club"),
              slots_label: count_label(free_cells, "slot")
            }
          end
          busiest = [days.map { _1[:free_cells] }.max.to_i, 1].max

          days.each { _1[:share] = (_1[:free_cells] * 100.0 / busiest).round }
        end

        def count_label(count, noun) = "#{count} #{count == 1 ? noun : "#{noun}s"}"

        # The week as a row of tabs over a date's clubs: one tap to the next
        # day without going back, and a dot where rain is likely.
        def day_strip(current)
          horizon_tables.map do |date, table|
            sky = outlook(table)
            {
              date: date.to_s,
              weekday: weekday_short(date),
              day: date.day,
              current: date == current,
              wet: !!sky && (sky.wet? || sky.damp?)
            }
          end
        end

        # One dict per Club on the selected date. Clubs with anything free
        # come first, then the fully-booked ones — dimmed rather than hidden,
        # so the eye reads "we did look" rather than "the club is gone" —
        # and last the ones we could not read, which are not booked, only
        # unknown. Within each part, Favourites lead: they are the rows the
        # eye is hunting for — unless rain is likely, when the clubs entirely
        # in the open sink below the rest of their part, favourite or not.
        def clubs_view(date)
          table = horizon_tables.fetch(date)
          wet = !!outlook(table)&.wet?
          rows = table.rows.map do |row|
            free_cells = row.cells.select(&:free?)
            any_free = free_cells.any?
            earliest = free_cells.first
            {
              slug: row.club_slug,
              name: row.club_name,
              any_free:,
              no_data: !any_free && no_data?(row.club_slug),
              free_count: free_cells.size,
              favourite: favourite?(row.club_slug),
              rained_off: wet && open_air?(row.club_slug),
              roofed: roofed?(row.club_slug),
              covers: profile(row.club_slug)&.covers.to_a.map(&:first),
              sub: [("from #{hour_label(earliest.starts_at)}:00" if earliest), club_price(row.club_slug)].compact.join(" · ")
            }
          end

          # The index breaks ties, because Ruby's sort_by is not stable and
          # the rows already arrive in an order worth keeping.
          part = ->(c) { if c[:any_free] then 0 elsif c[:no_data] then 2 else 1 end }
          rows.each_with_index.sort_by { |c, i| [part[c], c[:rained_off] ? 1 : 0, c[:favourite] ? 0 : 1, i] }.map(&:first)
        end

        # One dict per hour on the selected club-and-date, under the sky of the
        # city the club is in.
        def slots_view(date, row, city)
          row.cells.map do |cell|
            starts_at = cell.starts_at
            hour = hour_label(starts_at).to_i

            {
              time: "#{format("%02d", hour)}:00 – #{format("%02d", hour + 1)}:00",
              label: "#{format("%02d", hour)}:00",
              # Ticked to share as a Game. Counted from the page's midnight,
              # so an hour after it comes out as 24 rather than 0. An hour
              # already over has nothing left to tell anybody about.
              hour: HourSpan.offset(date, starts_at),
              pickable: starts_at + 3600 > Clock.now,
              free: cell.free?,
              weather: weather_at(starts_at, city),
              state: cell.free? ? "free" : "taken"
            }
          end
        end

        # The id arrives from the page, so it is checked against what is on
        # offer rather than stored as typed — a star on a club nobody watches
        # would be a row that never shows anywhere.
        def own_club!(slug)
          require_visitor!
          halt(404) unless enabled_slugs.include?(slug.to_s)

          slug.to_s
        end

        # Back to the Clubs screen it was tapped on, so the star turns over
        # in place. A date that is not on offer any more lands on the Dates
        # screen instead, where every star is one tap away again. A star on a
        # club's Profile turns over there, keeping the date it was reached
        # from.
        def back_to_clubs
          date = parse_date(params[:date])
          return redirect(to("/clubs/#{params[:slug]}#{"?date=#{date}" if date}")) if params[:back] == "profile"

          redirect(to(date ? "/date/#{date}" : "/"))
        end

        # One dict per watched Club in the current city for the directory:
        # Favourites first, then by name — nothing here is free or taken, so
        # there is no other order worth keeping.
        def directory_view
          clubs = city_clubs.sort_by { [favourite?(_1.slug) ? 0 : 1, _1.name] }

          clubs.map do |club|
            found = profile(club.slug)
            covers = found&.covers.to_a
            {
              slug: club.slug,
              name: club.name,
              initials: initials(club.name),
              roofed: roofed?(club.slug),
              favourite: favourite?(club.slug),
              sub: [found&.area, (Messages.cover_summary(covers) if covers.any?)].compact.join(" · ")
            }
          end
        end

        # Memoised per request: every club card on a date asks for its price.
        def enabled_clubs = @enabled_clubs ||= settings.repos.clubs.enabled

        def enabled_club(slug) = enabled_clubs.find { _1.slug == slug }

        # The Game a span at a club makes, carrying the public link that
        # describes it — the one the group gets, and the one a calendar
        # points back to.
        def game_at(club, span)
          found = profile(club.slug)

          Game.new(
            club_slug: club.slug, club_name: club.name, starts_at: span.starts_at, ends_at: span.ends_at,
            price: club.settings["price"], place: found&.address || found&.area, maps_url: found&.maps_url,
            booking_url: club.settings["booking_url"], card_url: url(game_path(club.slug, span))
          )
        end

        # Hours counted from the date's midnight, as HourSpan counts them, so a
        # game from 23:00 to 01:00 is `23-25` under the evening it belongs to.
        def game_path(slug, span) = "/game/#{slug}/#{span.date}/#{span.from}-#{span.to}"

        # The wettest hour the game touches, as a freed slot's message says —
        # over the club's own city, which need not be the one picked.
        def game_weather(game, club) = Weather.worst(forecast(club.city), game.starts_at, game.ends_at)

        # The query a link back to Share needs to keep its clubs narrowed.
        def share_query(filter)
          query = filter.to_params

          query.empty? ? "" : "?#{Rack::Utils.build_nested_query(query)}"
        end

        def visible_watches
          @visible_watches ||= settings.repos.watches.for_user(visitor_id).reject(&:expired?)
        end

        # The number on the Watches tab, wherever the tabs are drawn.
        def watches_count = visible_watches.size

        # The whole screen, so a refusal can re-render it without the route
        # having to remember what the GET assembles.
        def watches_screen
          @watches = visible_watches
          erb :watches, layout: :layout
        end

        def watch_new_screen(refusals = [])
          @refusals = refusals
          @clubs = city_clubs
          erb :watch_new, layout: :layout
        end

      end

      # kamal-proxy holds a deploy open until this answers, so it must never
      # depend on a session or on the database being reachable.
      get "/up" do
        "ok"
      end

      # Exists only to run the script that posts initData back to us: Telegram
      # delivers it in the URL fragment, which browsers never send upstream.
      get "/start" do
        erb :start, layout: :layout
      end

      post "/auth" do
        user_id = InitData.verify(params[:init_data], token: settings.telegram_token)
        halt(401, "not telegram") unless user_id

        response.set_cookie(
          COOKIE,
          value: settings.visitor_sessions.issue(user_id),
          path: "/",
          httponly: true,
          # Off outside production only so the app can be driven over plain
          # HTTP locally; Telegram will not open it that way regardless.
          secure: settings.production?,
          same_site: :lax,
          max_age: Session::LIFETIME_SECONDS
        )
        # The page reloads itself once this returns; there is nothing to render.
        status 204
      end

      # The home screen: one row per day of the horizon, with a headline
      # count of clubs and hours that are open.
      get "/" do
        require_visitor!

        @dates = dates_view
        @updated_at = city_updated_at
        @watches_count = visible_watches.size
        @owner = owner?
        erb :dates, layout: :layout
      end

      # The clubs open on one date. Reached from a Dates row; sends on to a
      # Slots screen when a club is tapped.
      get "/date/:date" do
        require_visitor!

        date = parse_date(params[:date])
        redirect(to("/")) if date.nil?

        @date = date.to_s
        @weekday = weekday_short(date)
        @date_label = date_label(date)
        @strip = day_strip(date)
        @only = club_filter
        all = clubs_view(date)
        @open_count = all.count { _1[:any_free] }
        @clubs = filter_clubs(all, @only)
        @outlook = outlook(horizon_tables.fetch(date))
        erb :clubs, layout: :layout
      end

      # The hours a single club sells on one date, tapped from the Clubs
      # screen: which are free, and the weather over each. The club's booking
      # page is one link in the header — every Cell would point at the same
      # page anyway.
      get "/date/:date/club/:slug" do
        require_visitor!

        date = parse_date(params[:date])
        redirect(to("/")) if date.nil?

        club = enabled_club(params[:slug])
        halt(404) unless club

        table = club_table(date, club)
        row = table.rows.first

        @date = date.to_s
        @weekday = weekday_short(date)
        @date_label = date_label(date)
        @club_slug = row.club_slug
        @club_name = row.club_name
        @area = profile(row.club_slug)&.area
        @booking_url = club.settings["booking_url"]
        @slots = slots_view(date, row, club.city)
        @free_hours = row.cells.count { _1.free? && _1.starts_at + 3600 > Clock.now }
        @price = price_parts(row.club_slug)
        @courts = courts_stat(row.club_slug)
        @outlook = outlook(table, city: club.city)
        # Whom the rain is news for, when the Profile says some court is open.
        @open_courts = profile(row.club_slug)&.covers.to_a.any? { |cover, _| cover == "outdoor" }
        erb :slots, layout: :layout
      end

      # Hours this person booked at the club, as one message for whoever they
      # play with. Reached by ticking hours on the club's screen — any hours,
      # free or not, because the Grid may not have seen the booking yet — and
      # adjusted here with the two pickers. A span that is not on offer goes
      # back to the hours to tick again.
      get "/date/:date/club/:slug/game" do
        require_visitor!

        date = parse_date(params[:date])
        redirect(to("/")) if date.nil?

        club = enabled_club(params[:slug])
        halt(404) unless club

        row = club_table(date, club).rows.first
        @span = HourSpan.pick(params, date:, columns: row.cells.map(&:starts_at))
        redirect(to("/date/#{date}/club/#{club.slug}")) unless @span

        @date = date.to_s
        @weekday = weekday_short(date)
        @date_label = date_label(date)
        @club = club
        @game = game_at(club, @span)
        @weather = game_weather(@game, club)
        @text = Messages.game(@game, weather: @weather)
        @event = @game.to_event
        erb :game, layout: :layout
      end

      # A Game as the group sees it: the link in the message. Open to anybody
      # who has it, because the people it is sent to need not use the bot —
      # and everything on it is either in the URL already or public: the club,
      # its pin, the Forecast. With `.ics` on the end it is the event itself,
      # for every calendar that is not Google's.
      #
      # Not limited to the Booking horizon: a link in a chat outlives the
      # week it was sent in, and nothing on it goes stale but the Forecast,
      # which simply stops being drawn.
      get %r{/game/([a-z0-9-]+)/(\d{4}-\d{2}-\d{2})/(\d{1,2})-(\d{1,2})(\.ics)?} do |slug, raw_date, from, to, ics|
        club = enabled_club(slug)
        date = begin
          Date.iso8601(raw_date)
        rescue Date::Error
          nil
        end
        halt(404) unless club && date

        span = HourSpan.pick({ from:, to: }, date:, columns: club.opening_hours.starts_on(date))
        halt(404) unless span

        @game = game_at(club, span)
        @event = @game.to_event

        if ics
          content_type "text/calendar; charset=utf-8"
          # Inline, so iOS offers to add it rather than to save a file.
          headers "Content-Disposition" => %(inline; filename="padel-#{slug}-#{span.date}.ics")
          Calendar.ics(@event)
        else
          @weather = game_weather(@game, club)
          erb :game_card, layout: :layout
        end
      end

      # One date's free courts as one message, to send to whoever you play
      # with. The whole day and every club by default; `from` and `to` narrow
      # it to the hours the group can actually make, and `only` to the
      # Favourites or to the clubs ticked by hand. Reached from the Clubs
      # screen.
      get "/date/:date/share" do
        require_visitor!

        date = parse_date(params[:date])
        redirect(to("/")) if date.nil?

        table = horizon_tables.fetch(date)
        clubs = city_clubs
        @date = date.to_s
        @weekday = weekday_short(date)
        @date_label = date_label(date)
        @clubs = clubs
        @filter = ClubFilter.from(params, watched_slugs: clubs.map(&:slug), favourites:)
        # The hours stay the whole table's, not the narrowed one's: switching
        # clubs should not throw away a span the group already agreed on.
        @span = HourSpan.from(params, date:, columns: table.columns)
        @sheet = Rundown.build(table: @filter.narrow(table), clubs:, window: @span.window, forecast:)
        @text = Messages.rundown(@sheet)
        erb :share, layout: :layout
      end

      # Every watched club and what it is like — the courts' covers and the
      # neighbourhood, one tap from the rest. Reached from the home screen.
      get "/clubs" do
        require_visitor!

        @clubs = directory_view
        erb :directory, layout: :layout
      end

      # One club's Profile: courts and their covers, a pin, Listed hours,
      # prices. Reached from the directory, or from a club's hours on a date —
      # `date` says which, so the back arrow returns where the tap came from.
      get "/clubs/:slug" do
        require_visitor!

        @club = enabled_club(params[:slug])
        halt(404) unless @club

        @profile = profile(@club.slug)
        @date = parse_date(params[:date])
        @back = @date ? "/date/#{@date}/club/#{@club.slug}" : "/clubs"
        erb :club, layout: :layout
      end

      # A star on a Clubs row. Post-redirect-get like the watch actions, so a
      # refresh does not tap it a second time.
      post "/favourites/:slug" do
        settings.repos.favourites.add(visitor_id, own_club!(params[:slug]))
        back_to_clubs
      end

      post "/favourites/:slug/delete" do
        settings.repos.favourites.remove(visitor_id, own_club!(params[:slug]))
        back_to_clubs
      end

      # The city switch. Kept per person rather than carried in the URL,
      # because it decides every screen's clubs and every link between them
      # would have to remember to pass it on — see ADR-0003.
      # Post-redirect-get back to the screen it was pressed on, which now
      # draws the new city.
      post "/city" do
        require_visitor!
        # Checked against the cities that have clubs, for the reason
        # own_club! checks a slug: a city nothing is in would be a row that
        # only ever reads as the default.
        halt(404) unless cities.include?(params[:city].to_s)

        settings.repos.preferences.choose_city(visitor_id, params[:city].to_s)
        back = params[:back].to_s
        redirect(to(back.match?(CITY_SWITCH_BACK) ? back : "/"))
      end

      get "/watches" do
        require_visitor!

        watches_screen
      end

      # The owner's view of the running thing: the three processes, every
      # club's last Poll, the database, the disk under it, and the most recent
      # lines that report trouble.
      get "/admin" do
        require_owner!

        @now = Clock.now
        @dashboard = settings.dashboard
        @problems = @dashboard.logs.call(problems: true, limit: 8).lines
        erb :admin, layout: :layout
      end

      # Search across the three processes' logs, newest first. A plain
      # phrase rather than a pattern: a regex typed into a phone is a typo
      # waiting to happen, and an expensive one waiting to be found.
      get "/admin/logs" do
        require_owner!

        @query = params[:q].to_s[0, 200]
        @process = params[:process].to_s
        @only_problems = params[:problems] == "1"
        @result = settings.dashboard.logs.call(query: @query, process: @process, problems: @only_problems)
        erb :admin_logs, layout: :layout
      end

      # The Watch form is its own screen now — the Manage list points at it
      # rather than carrying the form on the same page.
      get "/watches/new" do
        require_visitor!

        watch_new_screen
      end

      post "/watches" do
        require_visitor!

        @submitted = Submission.from(params, watched_slugs: enabled_slugs)
        refusals = @submitted.refusals

        # Re-rendered rather than redirected, so the reason arrives attached to
        # the submission that earned it — and so the choices survive being
        # refused, which redirecting would throw away.
        halt(422, watch_new_screen(refusals)) if refusals.any?

        watch = settings.repos.watches.create(user_id: visitor_id, **@submitted.to_watch)
        # Post-redirect-get: a refresh on the confirm page re-reads the same
        # watch rather than creating a second one.
        redirect(to("/watches/created?id=#{watch.id}"))
      end

      # The moment after a watch is created. The id in the URL lets a
      # refresh re-render the same card rather than making a second watch,
      # and belongs-to is checked so an id in somebody else's inbox does
      # nothing.
      get "/watches/created" do
        require_visitor!

        watch = settings.repos.watches.find(Integer(params[:id].to_s, exception: false))
        redirect(to("/watches")) unless watch && watch.user_id == visitor_id

        @watch = watch
        erb :confirm, layout: :layout
      end

      # Post-redirect-get throughout, so a watch is never paused twice by a
      # refresh, and the screen a person lands on is the list they changed.
      post "/watches/:id/pause" do
        set_active!(params[:id], false)
      end

      post "/watches/:id/resume" do
        set_active!(params[:id], true)
      end

      post "/watches/:id/delete" do
        settings.repos.watches.delete(own_watch!(params[:id]).id)
        redirect(to("/watches"))
      end
    end
  end
end
