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

      helpers do
        def visitor_id = settings.visitor_sessions.user_id(request.cookies[COOKIE])

        def require_visitor!
          redirect(to("/start")) unless visitor_id
        end

        # The dates the poller actually knows about. Anything outside this
        # would draw a grid nobody has polled, which reads as a club that shut
        # down rather than as a question we cannot answer.
        def horizon
          today = Clock.local_date(Clock.now)

          (0...Config.horizon_days).map { today + _1 }
        end

        def requested_date(raw)
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

        # Nothing is picked until something has been refused; a first visit has
        # no submission to remember.
        def picked_club?(slug) = !!@submitted&.picked_club?(slug)
        def picked_day?(day) = !!@submitted&.picked_day?(day)
        def picked_hour?(hour, which) = @submitted&.public_send(which) == hour

        # The whole screen, so a refusal can re-render it without the route
        # having to remember what the GET assembles.
        def watches_screen(refusals = [])
          @refusals = refusals
          @watches = settings.repos.watches.for_user(visitor_id).reject(&:expired?)
          @clubs = settings.repos.clubs.enabled
          erb :watches, layout: :layout
        end

        # A Dated watch names its one day; a Standing one names the weekdays it
        # keeps coming back on. Reading either tells you which it is before the
        # badge next to it does.
        def watch_when(watch)
          days = watch.dated? ? day_label(watch.date) : Messages.days_phrase(watch.weekdays)

          "#{days} · #{Messages.time_range(watch)}"
        end

        def day_label(date) = date.strftime("%a %-d %b")
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

      get "/" do
        require_visitor!

        @dates = horizon
        @date = requested_date(params[:date])
        # Bounce rather than quietly substituting today, so the address bar and
        # the screen never disagree about which day is on show.
        redirect(to("/")) if params[:date] && @date.nil?
        @date ||= @dates.first

        @table = Grid.build(clubs: settings.repos.clubs.enabled, slots: settings.repos.slots.all, date: @date)
        erb :grid, layout: :layout
      end

      get "/watches" do
        require_visitor!

        watches_screen
      end

      post "/watches" do
        require_visitor!

        @submitted = Submission.from(params, watched_slugs: settings.repos.clubs.enabled.map(&:slug))
        refusals = @submitted.refusals

        # Re-rendered rather than redirected, so the reason arrives attached to
        # the submission that earned it — and so the choices survive being
        # refused, which redirecting would throw away.
        halt(422, watches_screen(refusals)) if refusals.any?

        settings.repos.watches.create(user_id: visitor_id, **@submitted.to_watch)
        redirect(to("/watches"))
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
