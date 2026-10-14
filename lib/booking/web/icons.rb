module Booking
  module Web
    # The line icons and court drawings the screens share, as inline SVG so
    # they take the text colour they sit in and cost no request. Decorative
    # throughout: every one sits beside words that say the same thing, so
    # each is hidden from assistive tech.
    module Icons
      STROKE = %(fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round").freeze

      LINES = {
        back: [2.4, %(<path d="M15 6l-6 6 6 6"/>)],
        chevron: [2, %(<path d="M9 6l6 6-6 6"/>)],
        arrow: [2.4, %(<path d="M5 12h14M13 6l6 6-6 6"/>)],
        external: [2.4, %(<path d="M7 17L17 7M9 7h8v8"/>)],
        share: [2.2, %(<path d="M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7M16 6l-4-4-4 4M12 2v13"/>)],
        info: [2, %(<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>)],
        alert: [2.2, %(<circle cx="12" cy="12" r="9"/><path d="M12 7v6M12 16.5v.5"/>)],
        rain: [2, %(<path d="M7 15a4 4 0 0 1-.6-8A6 6 0 0 1 18 8a3.5 3.5 0 0 1-.5 7z"/><path d="M9 18l-1 2M13 18l-1 2M17 18l-1 2"/>)],
        sun: [2, %(<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>)],
        pin: [2, %(<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>)],
        calendar: [2, %(<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>)],
        send: [2.2, %(<path d="M21 4L3 11l6 2 2 6 3-4 5 4z"/><path d="M9 13l12-9"/>)],
        plus: [2.6, %(<path d="M12 5v14M5 12h14"/>)],
        bell: [2, %(<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 21h4"/>)],
        courts: [2, %(<rect x="3" y="5" width="18" height="14" rx="1"/><path d="M12 5v14M7 5v14M17 5v14M7 12h10"/>)],
        trash: [2, %(<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>)],
        search: [2, %(<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>)],
        check: [3, %(<path d="M5 12l5 5 9-10"/>)],
        close: [2.4, %(<path d="M6 6l12 12M18 6L6 18"/>)],
        locate: [2.2, %(<path d="M12 2v3M12 19v3M2 12h3M19 12h3"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2" fill="currentColor"/>)],
        gauge: [2, %(<path d="M4 15a8 8 0 1 1 16 0"/><path d="M12 15l4-5"/>)],
        list: [2.2, %(<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>)],
        clock: [2.2, %(<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>)],
        roof: [2.6, %(<path d="M3 11l9-7 9 7M6 10v9h12v-9"/>)],
        court: [2.4, %(<rect x="4" y="6" width="16" height="12" rx="1"/><path d="M12 6v12M8 6v12M16 6v12"/>)],
        map: [2.2, %(<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>)]
      }.freeze

      module_function

      def icon(name, size: 20)
        width, paths = LINES.fetch(name)

        %(<svg width="#{size}" height="#{size}" viewBox="0 0 24 24" #{STROKE} stroke-width="#{width}" aria-hidden="true">#{paths}</svg>)
      end

      def star(size: 14)
        %(<svg width="#{size}" height="#{size}" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">) +
          %(<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/></svg>)
      end

      # The mark: a tennis ball, seams and all.
      # The ring takes the text colour, so it reads on either ground; the
      # ball and its seams stay the colours of a ball.
      def ball(size: 26, outline: true)
        ring = outline ? %( class="brand__ring" stroke="currentColor" stroke-width="2") : ""

        %(<svg class="brand__ball" width="#{size}" height="#{size}" viewBox="0 0 26 26" aria-hidden="true">) +
          %(<circle cx="13" cy="13" r="#{outline ? 12 : 12.5}" fill="#D6F542"#{ring}/>) +
          %(<path d="M4 7c5 2 6 10 2 14M22 5c-4 3-5 11-1 16" fill="none" stroke="#0D1611" stroke-width="1.6"/></svg>)
      end

      # A padel court seen from above, in the ball's yellow, drawn faintly
      # behind the dark slabs. The same lines at three sizes.
      COURTS = {
        ticket: [354, 230, 'x="18" y="18" width="318" height="194"',
                 [[177, 18, 177, 212, 3], [80, 18, 80, 212, 1.5], [274, 18, 274, 212, 1.5], [80, 115, 274, 115, 1.5]]],
        profile: [300, 200, 'x="2" y="2" width="296" height="196"',
                  [[150, 2, 150, 198, 3], [60, 2, 60, 198, 2], [240, 2, 240, 198, 2], [60, 100, 240, 100, 2]]],
        splash: [390, 520, 'x="40" y="10" width="310" height="500"',
                 [[40, 260, 350, 260, 4], [40, 110, 350, 110, 2], [40, 410, 350, 410, 2], [195, 110, 195, 410, 2]]]
      }.freeze

      def court(kind, css)
        width, height, rect, lines = COURTS.fetch(kind)
        drawn = lines.map { |x1, y1, x2, y2, w| %(<line x1="#{x1}" y1="#{y1}" x2="#{x2}" y2="#{y2}" stroke="#D6F542" stroke-width="#{w}"/>) }

        %(<svg class="#{css}" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" aria-hidden="true">) +
          %(<rect #{rect} fill="none" stroke="#D6F542" stroke-width="3"/>#{drawn.join}</svg>)
      end

      # One court, as a tile on a club's Profile.
      def court_tile
        %(<svg class="court__icon" width="34" height="22" viewBox="0 0 34 22" aria-hidden="true">) +
          %(<rect x="1" y="1" width="32" height="20" rx="2" stroke-width="1.5"/>) +
          %(<line x1="17" y1="1" x2="17" y2="21" stroke-width="1.5"/><line x1="7" y1="11" x2="27" y2="11" stroke-width="1"/></svg>)
      end

      # Two roads, a pond and a pin: the drawing over a Profile's link to Google
      # Maps. Not a map of anywhere — there is no map service behind it — only
      # a picture that says "this opens a map". Coloured by the stylesheet.
      def place_art
        %(<svg class="place__art" viewBox="0 0 358 120" preserveAspectRatio="xMidYMid slice" aria-hidden="true">) +
          %(<path class="place__road" d="M0 80 C80 60 120 100 200 70 S320 40 358 60" stroke-width="10"/>) +
          %(<path class="place__road" d="M140 0 L170 120" stroke-width="6"/>) +
          %(<ellipse class="place__pond" cx="250" cy="34" rx="44" ry="18"/>) +
          %(<path class="place__pin" d="M181 76 L169.5 59.6 A15 15 0 1 1 192.5 59.6 Z"/>) +
          %(<circle class="place__dot" cx="181" cy="50" r="5"/></svg>)
      end

      # The ball with a tick through it: a Watch has been made.
      def done
        %(<svg width="132" height="132" viewBox="0 0 132 132" aria-hidden="true">) +
          %(<circle cx="66" cy="66" r="64" fill="#D6F542"/>) +
          %(<path d="M14 36c26 10 32 52 10 74M118 26c-20 16-26 58-6 82" fill="none" stroke="#0D1611" stroke-width="3" opacity="0.25"/>) +
          %(<path d="M42 68l16 16 32-36" fill="none" stroke="#0D1611" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/></svg>)
      end
    end
  end
end
