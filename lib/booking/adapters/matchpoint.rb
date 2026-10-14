require "date"
require "json"
require "time"

module Booking
  module Adapters
    # Padel Island runs TPC MatchPoint, a Spanish ASP.NET WebForms product, at
    # booking.padelisland.ge. Its court grid, `/Booking/Grid.aspx`, opens for
    # anyone: no login, no Turnstile (that sits on the login form only), and
    # the page's own script reads it from `/booking/srvc.aspx/ObtenerCuadro`,
    # a JSON ScriptService — so do we, the way that script does.
    #
    # The site's robots.txt has disallowed `/Booking/` and `/Services/` since
    # at least 2026-07-30, and still did on 2026-10-14; IIS paths are
    # case-blind, so `/booking/srvc.aspx` falls under the first. We read it
    # anyway, at the same low rate as every club, because it is the grid
    # every anonymous visitor's browser loads — the reasoning is docs/adr/0004.
    #
    # Every call carries a `key` the page prints into an inline script, and
    # the key is good only inside the `ASP.NET_SessionId` that came with it.
    # The server also wants a `Referer` from its own grid. Get any of the
    # three wrong and it does not refuse: it answers 200 with an empty grid,
    # `Id: 0` — the same thing it says about a date past its horizon. So an
    # answer is believed only when it names the grid and date asked about.
    #
    # One site, four venues: each is a *cuadro* (grid) on the same page, and
    # each is its own Club here, told apart by `cuadro_id`.
    #
    # The grid reports what is *taken* — `Ocupaciones`, per court, as
    # wall-clock "HH:MM" pairs on a half-hour grid — so the free hours are the
    # club's day minus those. The `/Date(ms)/` beside each pair is not to be
    # trusted: 20:00 in Tbilisi came back as 18:00 UTC, the server's own
    # Spanish clock leaking through. Only the strings are read.
    class Matchpoint
      BASE_URL = "https://booking.padelisland.ge".freeze
      GRID_PATH = "/Booking/Grid.aspx".freeze
      ROUTE = "/booking/srvc.aspx/ObtenerCuadro".freeze
      # The name of the page's global the key lives in, the same one its
      # `ajax.js` sends as `key`. Version 2.9.6 of that script, 2026-10-14.
      KEY = /hl90njda2b89k\s*=\s*'([^']+)'/
      # The venues the page's date picker switches between, id to name.
      CUADROS = /"cuadroCentroMap"\s*:\s*(\{[^}]*\})/
      # The page offers 30 days ahead (21 for Kachreti) and the server answers
      # for all of it. Evening bookings seen on 2026-10-14 reached a day or two
      # ahead; this caps what we ask for, and the horizon does the rest.
      DEFAULT_MAX_DAYS = 14
      HOUR = 3600

      Session = Data.define(:cookie, :key, :cuadro_ids) do
        def headers(base_url) = { "Cookie" => cookie, "Referer" => "#{base_url}#{GRID_PATH}" }
      end

      # Four venues share one page, and the poller builds a fresh adapter
      # every tick — scraping per adapter would open four server sessions
      # every four minutes. Kept per site, for the life of the process, and
      # thrown away the first time an answer comes back blank. A session
      # opened on 2026-10-14 still answered seven minutes later; ASP.NET's
      # default is 20 minutes idle, and a tick every four keeps it warm —
      # inferred, not measured.
      def self.sessions = @sessions ||= {}

      def initialize(club, http:, clock: Clock, sessions: self.class.sessions)
        @club = club
        @http = http
        @clock = clock
        @sessions = sessions
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @cuadro_id = Integer(club.settings.fetch("cuadro_id"))
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range)
        now = @clock.now
        horizon = nil

        date_range.to_a.first(@max_days).each_with_object([]) do |date, slots|
          # Past its horizon the server answers blank, which reads exactly like
          # a dead session; every answer says where the horizon is, so the
          # dates beyond it are never asked about.
          break slots if horizon && date > horizon

          horizon, free = read(date, grid(date), now)
          slots.concat(free)
        end.uniq(&:key)
      end

      private

      # A blank answer, inside the adapter only: it means "try a fresh
      # session", and twice means the tick has failed.
      Stale = Class.new(StandardError)
      private_constant :Stale

      def read(date, grid, now)
        [Date.strptime(grid.fetch("StrFechaMax"), "%d/%m/%Y"), grid_slots(date, grid, now)]
      rescue KeyError, TypeError, ArgumentError => e
        raise SourceUnavailable, "#{@base_url}: unreadable grid #{@cuadro_id} on #{date} — #{e.class} #{e.message}"
      end

      def grid(date)
        url = "#{@base_url}#{ROUTE}"
        asked = date.strftime("%d/%m/%Y")
        answer = signed do |session|
          body = @http.post_json(url, { "idCuadro" => @cuadro_id, "fecha" => asked, "key" => session.key }, headers: session.headers(@base_url))
          body = body["d"] if body.is_a?(Hash)
          # Blank, or about some other grid or date: the session has gone.
          raise Stale unless body.is_a?(Hash) && body["Id"] == @cuadro_id && body["StrFecha"] == asked

          body
        end
        columns = answer["Columnas"]
        # Inverted, a grid without its bookings reads as every court free all
        # day — so a missing list is a broken answer, never an empty one.
        unless columns.is_a?(Array) && columns.all? { _1.is_a?(Hash) && _1["Ocupaciones"].is_a?(Array) }
          raise SourceUnavailable, "#{url}: no courts with bookings for grid #{@cuadro_id} on #{asked}: #{answer.inspect[0, 200]}"
        end

        answer
      rescue Stale
        raise SourceUnavailable, "#{url}: a blank grid for #{@cuadro_id} on #{asked}, twice — the session, the key or the horizon"
      end

      def grid_slots(date, grid, now)
        # A day the club has shut, whole: holiday, event, weather.
        return [] if grid["FechaInhabil"]

        day_starts = minutes(grid.fetch("StrHoraInicio"))
        # The server's own fence around the day: when the venue opens and
        # shuts, and the span it will take a booking for at all. Declared
        # opening hours wider than that must not read as free time.
        from = [local(grid.fetch("StrHoraAperturaCentro")), local(grid.fetch("StrFechaHoraInicioReservas"))].max
        till = [local(grid.fetch("StrHoraCierreCentro")), local(grid.fetch("StrFechaHoraFinReservas"))].min
        starts = @club.opening_hours.starts_on(date).select { _1 > now && _1 >= from && _1 + HOUR <= till }

        grid.fetch("Columnas").flat_map do |court|
          taken = court.fetch("Ocupaciones").map { span(date, _1, day_starts) }

          # Overlap, not containment: a 22:00–23:30 booking takes the 23:00
          # hour too, since only half of it is left.
          starts.filter_map do |starts_at|
            slot(court, starts_at) unless taken.any? { |start, stop| start < starts_at + HOUR && stop > starts_at }
          end
        end
      end

      # One booking, block or season reservation as absolute instants. Its
      # "HH:MM" belongs to the business day: anything before the grid's first
      # hour is after midnight, and an end at or before its start runs past
      # it — so EXPO's 07:00–02:00 day files a 00:30 under tomorrow.
      def span(date, booking, day_starts)
        start = instant(date, booking.fetch("StrHoraInicio"), day_starts)
        stop = instant(date, booking.fetch("StrHoraFin"), day_starts)
        stop = instant(date + 1, booking.fetch("StrHoraFin"), day_starts) if stop <= start

        [start, stop]
      end

      def instant(date, time, day_starts)
        date += 1 if minutes(time) < day_starts
        Clock.local_to_utc("#{date} #{time}")
      end

      def minutes(time)
        hour, minute = time.to_s.split(":").map(&:to_i)
        (hour.to_i * 60) + minute.to_i
      end

      # "15/10/2026 7:00", the venue's wall clock.
      def local(value)
        day, month, year, hour, minute = value.to_s.scan(/\d+/).map(&:to_i)
        Clock.local_to_utc(format("%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute))
      end

      # One fresh session per blank answer; a second is an ordinary failure for
      # the tick.
      def signed
        yield session
      rescue Stale
        @sessions.delete(@base_url)
        yield session
      end

      def session
        session = @sessions[@base_url] ||= scrape
        # An unknown grid answers blank, which would only ever read as a dead
        # session. Asking about one the page does not offer is a broken config
        # or a renumbered site, not data.
        unless session.cuadro_ids.include?(@cuadro_id)
          raise SourceUnavailable, "#{@base_url}: grid #{@cuadro_id} is not on the booking page (it offers #{session.cuadro_ids.join(", ")})"
        end

        session
      end

      def scrape
        url = "#{@base_url}#{GRID_PATH}"
        page, cookie = @http.get_page(url)
        page = page.dup.force_encoding(Encoding::UTF_8)
        key = page[KEY, 1]
        cuadros = page[CUADROS, 1]
        raise SourceUnavailable, "#{url}: no grid key and venues on the page" unless key && cuadros && !cookie.empty?

        Session.new(cookie:, key:, cuadro_ids: JSON.parse(cuadros).keys.map { Integer(_1) })
      rescue JSON::ParserError, ArgumentError => e
        raise SourceUnavailable, "#{url}: unreadable venue list — #{e.class} #{e.message}"
      end

      def slot(court, starts_at)
        id = court.fetch("Id").to_s

        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(id),
          # "EXPO Park Roof", "Kachreti Court 2": the venue's own names.
          court_label: court["TextoPrincipal"].to_s.strip.then { _1.empty? ? "Court #{id}" : _1 },
          starts_at:,
          ends_at: starts_at + HOUR,
          price: @club.settings["price"],
          # `?id=` opens the grid on the venue; nothing found picks a date.
          deeplink: "#{@base_url}#{GRID_PATH}?id=#{@cuadro_id}"
        )
      end
    end
  end
end
