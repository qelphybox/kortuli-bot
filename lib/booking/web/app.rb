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
    end
  end
end
