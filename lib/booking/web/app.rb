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

        # Memoised per request: every watch on the screen asks for it.
        def club_names = @club_names ||= settings.repos.clubs.enabled.to_h { [_1.slug, _1.name] }

        def watch_clubs(watch) = Messages.clubs_phrase(watch, club_names)

        # Reads as both the class and the label, so the two cannot drift apart.
        def watch_kind(watch) = watch.dated? ? "dated" : "standing"

        # The form renders from the same lists Submission validates against, so
        # the two cannot answer differently about what was on offer.
        def weekday_choices = MONDAY_FIRST.map { [_1, Messages::DAY_NAMES[_1]] }

        def start_hours = START_HOURS
        def end_hours = END_HOURS

        def clock(hour) = Messages.clock(hour * 60)

        def profile(slug) = settings.club_profiles[slug]

        # "indoor + covered" beside a club's name, or nothing for a club
        # without a Profile.
        def cover_tag(slug)
          covers = profile(slug)&.covers.to_a

          Messages.cover_tag(covers) if covers.any?
        end

        # Memoised per request: every club row on the screen asks for it.
        def favourites = @favourites ||= settings.repos.favourites.for_user(visitor_id)

        def favourite?(slug) = favourites.include?(slug)

        def enabled_slugs = settings.repos.clubs.enabled.map(&:slug)

        # A first visit has no submission to remember, so it starts from the
        # clubs this person has starred — the ones they would tick anyway.
        # Days and hours start blank: nothing to guess them from.
        def picked_club?(slug) = @submitted ? @submitted.picked_club?(slug) : favourite?(slug)
        def picked_day?(day) = !!@submitted&.picked_day?(day)
        def picked_hour?(hour, which) = @submitted&.public_send(which) == hour

        # The Slots screen asks this before drawing a Watch button, so it
        # never offers a tap the route would only refuse.
        def askable?(at) = TappedHour.askable?(at, horizon:)

        # Tapping means "tell me about this hour", so an existing watch on it is
        # woken rather than duplicated. Two watches on one hour would mean two
        # messages about it, which the notifications index cannot prevent
        # because it dedupes per watch — and doing nothing at all would answer
        # with a success the person has no way of seeing.
        def ask_about(tapped)
          existing = settings.repos.watches.for_user(visitor_id).find { tapped.asked_by?(_1) }
          return settings.repos.watches.create(user_id: visitor_id, **tapped.to_watch) unless existing

          settings.repos.watches.set_active(existing.id, true) unless existing.active?
        end

        # A Dated watch names its one day; a Standing one names the weekdays it
        # keeps coming back on. Reading either tells you which it is before the
        # badge next to it does.
        def watch_when(watch)
          days = watch.dated? ? day_label(watch.date) : Messages.days_phrase(watch.weekdays)

          "#{days} · #{Messages.time_range(watch)}"
        end

        def day_label(date) = date.strftime("%a %-d %b")

        def weekday_short(date) = Messages::DAY_NAMES[date.wday]

        def date_label(date) = date.strftime("%b %-d")

        # The list of Grid Tables the drill-down draws from. Built once per
        # request rather than per screen so the Dates counts, the Clubs sub-
        # lines and the Slots rows all read the same snapshot — a poll that
        # finishes mid-render cannot change what the person sees on one page.
        def horizon_tables
          @horizon_tables ||= begin
            clubs = settings.repos.clubs.enabled
            slots = settings.repos.slots.all
            horizon.to_h { [_1, Grid.build(clubs:, slots:, date: _1)] }
          end
        end

        # The Forecast by the instant each hour starts, read once per request
        # for the same reason the tables are.
        def forecast = @forecast ||= settings.repos.forecast.hours.to_h { [_1.starts_at.to_i, _1] }

        def weather_at(starts_at) = forecast[starts_at.to_i]

        # The Forecast over the hours a date's page draws that are still to
        # come — this morning's rain is no reason to book a roof tonight. Nil
        # where the Forecast has nothing to say, so nothing is drawn.
        def outlook(table, now: Clock.now)
          hours = table.columns.select { _1 + 3600 > now }.filter_map { weather_at(_1) }

          Weather::Outlook.new(hours:) if hours.any?
        end

        # Every court of the club in the open, as far as its Profile says. A
        # club without a Profile is not assumed to be either.
        def open_air?(slug)
          covers = profile(slug)&.covers.to_a

          covers.any? && covers.all? { |cover, _| cover == "outdoor" }
        end

        def any_free?(table) = table.rows.any? { |row| row.cells.any?(&:free?) }

        # One dict per horizon date, in the shape the Dates template reads.
        # A day with anything free names the number of clubs and the number
        # of hours; a day with nothing shows "fully booked" and dims itself.
        def dates_view
          horizon_tables.map do |date, table|
            open_clubs = table.rows.count { |row| row.cells.any?(&:free?) }
            free_cells = table.rows.sum { |row| row.cells.count(&:free?) }
            any_free = open_clubs.positive?

            {
              date: date.to_s,
              weekday: weekday_short(date),
              date_label: date_label(date),
              today: date == horizon.first,
              any_free:,
              weather: outlook(table)&.icon,
              headline: any_free ? "#{open_clubs} #{open_clubs == 1 ? "club" : "clubs"}" : "fully booked",
              sub: any_free ? "#{free_cells} #{free_cells == 1 ? "slot" : "slots"}" : nil
            }
          end
        end

        # One dict per Club on the selected date. Clubs with anything free
        # come first, then the fully-booked ones — dimmed rather than hidden,
        # so the eye reads "we did look" rather than "the club is gone".
        # Within each half, Favourites lead: they are the rows the eye is
        # hunting for — unless rain is likely, when the clubs entirely in the
        # open sink below the rest of their half, favourite or not.
        def clubs_view(date)
          table = horizon_tables.fetch(date)
          wet = !!outlook(table)&.wet?
          rows = table.rows.map do |row|
            free_cells = row.cells.select(&:free?)
            any_free = free_cells.any?
            earliest = free_cells.first
            sub =
              if any_free
                "from #{hour_label(earliest.starts_at)}:00 · #{free_cells.size} #{free_cells.size == 1 ? "slot" : "slots"} left"
              else
                "fully booked"
              end
            {
              slug: row.club_slug,
              name: row.club_name,
              any_free:,
              favourite: favourite?(row.club_slug),
              rained_off: wet && open_air?(row.club_slug),
              cover: cover_tag(row.club_slug),
              sub:
            }
          end

          # The index breaks ties, because Ruby's sort_by is not stable and
          # the rows already arrive in an order worth keeping.
          rows.each_with_index.sort_by { |c, i| [c[:any_free] ? 0 : 1, c[:rained_off] ? 1 : 0, c[:favourite] ? 0 : 1, i] }.map(&:first)
        end

        # One dict per hour on the selected club-and-date. "Watching" is
        # queried once per screen from the user's own list, so a slot that
        # already has a Dated watch on it renders as such.
        def slots_view(date, row)
          watching = watched_hours(date, row.club_slug)

          row.cells.map do |cell|
            starts_at = cell.starts_at
            hour = hour_label(starts_at).to_i
            time = "#{format("%02d", hour)}:00 – #{format("%02d", hour + 1)}:00"
            watching_this = watching.include?(Clock.to_local(starts_at).hour * 60 + Clock.to_local(starts_at).min)
            state = cell.free? ? "free" : watching_this ? "watching" : "taken"

            {
              time:,
              starts_at: starts_at.iso8601,
              free: cell.free?,
              askable: !cell.free? && askable?(starts_at),
              watching: watching_this,
              weather: weather_at(starts_at),
              state:,
              deeplink: cell.deeplink
            }
          end
        end

        # The minutes-of-day this person has an active, not-yet-expired dated
        # watch on for a given (date, club). The Slots screen renders those
        # as "watching" rather than as a fresh Watch button.
        def watched_hours(date, club_slug)
          settings.repos.watches.for_user(visitor_id).each_with_object(Set.new) do |w, out|
            next unless w.dated? && w.date == date && w.active? && !w.expired?
            next unless w.club_slugs.include?(club_slug)

            out << w.from_minute
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
        # screen instead, where every star is one tap away again.
        def back_to_clubs
          date = parse_date(params[:date])
          redirect(to(date ? "/date/#{date}" : "/"))
        end

        # One dict per watched Club for the directory: Favourites first, then
        # by name — nothing here is free or taken, so there is no other order
        # worth keeping.
        def directory_view
          clubs = settings.repos.clubs.enabled.sort_by { [favourite?(_1.slug) ? 0 : 1, _1.name] }

          clubs.map do |club|
            found = profile(club.slug)
            covers = found&.covers.to_a
            {
              slug: club.slug,
              name: club.name,
              favourite: favourite?(club.slug),
              sub: [found&.area, (Messages.cover_summary(covers) if covers.any?)].compact.join(" · ")
            }
          end
        end

        # The query a link back to Share needs to keep its clubs narrowed.
        def share_query(filter)
          query = filter.to_params

          query.empty? ? "" : "?#{Rack::Utils.build_nested_query(query)}"
        end

        def visible_watches
          settings.repos.watches.for_user(visitor_id).reject(&:expired?)
        end

        # The whole screen, so a refusal can re-render it without the route
        # having to remember what the GET assembles.
        def watches_screen
          @watches = visible_watches
          erb :watches, layout: :layout
        end

        def watch_new_screen(refusals = [])
          @refusals = refusals
          @clubs = settings.repos.clubs.enabled
          erb :watch_new, layout: :layout
        end

        # Reads back the watch that was just created, in the same voice the
        # rest of the screens use: a Standing one names its days, a Dated one
        # names its date.
        def confirm_summary(watch)
          clubs = watch_clubs(watch)
          when_line = watch_when(watch)

          "#{clubs} · #{when_line}"
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
        @clubs = clubs_view(date)
        @outlook = outlook(horizon_tables.fetch(date))
        erb :clubs, layout: :layout
      end

      # The hours a single club sells on one date, tapped from the Clubs
      # screen. Free hours link out; taken hours that are still ahead offer
      # a one-tap Watch.
      get "/date/:date/club/:slug" do
        require_visitor!

        date = parse_date(params[:date])
        redirect(to("/")) if date.nil?

        table = horizon_tables.fetch(date)
        row = table.rows.find { _1.club_slug == params[:slug] }
        halt(404) unless row

        @date = date.to_s
        @weekday = weekday_short(date)
        @date_label = date_label(date)
        @club_slug = row.club_slug
        @club_name = row.club_name
        @slots = slots_view(date, row)
        erb :slots, layout: :layout
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
        clubs = settings.repos.clubs.enabled
        @date = date.to_s
        @weekday = weekday_short(date)
        @date_label = date_label(date)
        @clubs = clubs
        @filter = ClubFilter.from(params, watched_slugs: clubs.map(&:slug), favourites:)
        # The hours stay the whole table's, not the narrowed one's: switching
        # clubs should not throw away a span the group already agreed on.
        @span = HourSpan.from(params, date:, columns: table.columns)
        @sheet = Rundown.build(table: @filter.narrow(table), clubs:, window: @span.window)
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

        @club = settings.repos.clubs.enabled.find { _1.slug == params[:slug] }
        halt(404) unless @club

        @profile = profile(@club.slug)
        date = parse_date(params[:date])
        @back = date ? "/date/#{date}/club/#{@club.slug}" : "/clubs"
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

        @summary = confirm_summary(watch)
        erb :confirm, layout: :layout
      end

      # The main scenario, and deliberately the shortest route in the file:
      # an hour is gone, and you want to be told when it is not. Everything
      # the watch needs is already in the Cell that was tapped.
      post "/watches/dated" do
        require_visitor!

        tapped = TappedHour.from(params, watched_slugs: enabled_slugs, horizon:)
        halt(422) unless tapped

        ask_about(tapped)

        # Back to the Slots screen it was tapped on, so the newly-watched
        # hour renders as "Watching" without a second click. The page is not
        # always the hour's own date: one after midnight is drawn under the
        # evening it belongs to.
        page_date = parse_date(params[:date]) || horizon.first
        redirect(to("/date/#{page_date}/club/#{tapped.club_slug}"))
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
