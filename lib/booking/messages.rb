module Booking
  # Every user-facing string lives here. English only for now — the mechanism
  # for choosing a language is deliberately absent, but keeping the strings in
  # one place means adding it later is a new file, not an excavation.
  module Messages
    DAY_NAMES = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

    module_function

    def escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

    # `weather` is the Forecast's hour for the slot, where there is one: the
    # first thing anybody wonders about an open court an hour from now.
    def slot_freed(slot, club_name, weather: nil)
      lines = ["🎾 <b>#{escape(slot.court_label)}</b> just freed up", "#{escape(club_name)} · #{when_phrase(slot)}"]
      lines << weather_tag(weather) if weather
      lines << escape(slot.price) if slot.price
      lines << escape(slot.deeplink) if slot.deeplink
      lines.join("\n")
    end

    def when_phrase(slot)
      starts = slot.local_starts_at
      ends = Clock.to_local(slot.ends_at)
      "#{DAY_NAMES[starts.wday]} #{starts.day} #{starts.strftime("%b")}, #{starts.strftime("%H:%M")}–#{ends.strftime("%H:%M")}"
    end

    # Plain text rather than HTML: it leaves through Telegram's share sheet or
    # the clipboard, and neither carries markup. Links survive anyway — every
    # client turns a bare URL into one.
    def rundown(sheet)
      return "#{rundown_heading(sheet)}\n\nNothing free." if sheet.empty?

      blocks = sheet.entries.map do |entry|
        [
          [entry.club_name, entry.price].compact.join(" · "),
          entry.runs.map { "#{local_clock(_1.starts_at)}–#{local_clock(_1.ends_at)}" }.join(", "),
          entry.link
        ].compact.join("\n")
      end
      blocks << "Fully booked: #{sheet.booked.join(", ")}" if sheet.booked.any?
      heading = [rundown_heading(sheet), (weather_brief(sheet.outlook) if sheet.outlook)].compact.join("\n")

      [heading, *blocks].join("\n\n")
    end

    def rundown_heading(sheet)
      date = sheet.date
      day = "#{DAY_NAMES[date.wday]} #{date.day} #{date.strftime("%b")}"
      day = "#{day}, #{local_clock(sheet.window.begin)}–#{local_clock(sheet.window.end)}" if sheet.window

      "🎾 Free padel courts · #{day}"
    end

    # --- A Game -------------------------------------------------------------

    # What the group gets when somebody has booked: where, when, whether it
    # will rain on it, what it costs, the pin, and the link that puts it in a
    # calendar. Plain text for the reason the Rundown is — it leaves through
    # the share sheet or the clipboard, and neither carries markup.
    def game(game, weather: nil)
      place = ["📍", game.place, game.maps_url].compact
      [
        "🎾 Court booked · #{game.club_name}",
        game_when(game),
        weather && weather_tag(weather),
        game.price && "💸 #{game.price} an hour",
        (place.join(" ") if place.size > 1),
        game.card_url && "📅 Add to calendar: #{game.card_url}"
      ].compact.join("\n")
    end

    # "Tue 14 Oct, 19:00–21:00": the date the game starts on, by the clock —
    # an hour after midnight is the next day's, whatever page it was ticked on.
    def game_when(game)
      starts = Clock.to_local(game.starts_at)

      "#{DAY_NAMES[starts.wday]} #{starts.day} #{starts.strftime("%b")}, #{local_clock(game.starts_at)}–#{local_clock(game.ends_at)}"
    end

    def game_title(game) = "🎾 Padel · #{game.club_name}"

    # The calendar event's notes: what you would want to hand over at the
    # desk, and the way back to everything else.
    def game_details(game)
      [
        game.price && "#{game.price} an hour",
        game.maps_url && "Map: #{game.maps_url}",
        game.booking_url && "Booking page: #{game.booking_url}"
      ].compact.join("\n")
    end

    # The Slots screen's button, before and after anything is ticked. Without
    # JS it is always the first; with it, the second until a tick arrives.
    def game_pick = "Share my game"

    def game_pick_none = "Tick the hours you booked"

    def game_to_google = "Google Calendar ↗"

    def game_to_ics = "Apple & other calendars"

    def local_clock(utc_time) = Clock.to_local(utc_time).strftime("%H:%M")

    def time_range(watch) = "#{clock(watch.from_minute)}–#{clock(watch.to_minute)}"

    def clock(minute_of_day) = format("%02d:%02d", minute_of_day / 60, minute_of_day % 60)

    def days_phrase(weekdays)
      days = weekdays.to_a.sort
      return "every day" if days.size == 7

      # Rotate so the list reads Monday-first, as a European calendar would.
      days.sort_by { (_1 + 6) % 7 }.map { DAY_NAMES[_1] }.join(", ")
    end

    # The bot's whole vocabulary now: it says this, and then only speaks again
    # when something is Freed.
    def welcome
      <<~TEXT.strip
        🎾 <b>Padel slot watcher</b>

        Evening padel courts in Georgia get taken a day or two ahead and only come back when somebody cancels. This watches for those cancellations and pings you the moment one happens.

        Open the app to see the week and to say which hours you want watching. It does not book or pay for anything — you get a link and take it from there.
      TEXT
    end

    # Both the menu button and the greeting's button, so the two ways in cannot
    # end up named differently.
    def open_app = "Open the app"

    # A watch outlives a club being switched off, and the slug is a better
    # answer than a blank line.
    def clubs_phrase(watch, club_names) = watch.club_slugs.map { club_names.fetch(_1, _1) }.sort.join(", ")

    def pick_at_least_one_club = "Pick at least one club first."

    def pick_at_least_one_day = "Pick at least one day first."

    # Not "invalid range": the point is that such a watch would sit in the list
    # looking like cover while never being able to match anything.
    def pick_a_later_end = "The end of the range has to be after its start, or nothing can match."

    # Only reachable by a stale page or a hand-made post — the screen offers a
    # fixed list — but a reason is still owed.
    def pick_hours_on_offer = "Pick both hours from the list."

    # The form has its own screen now, so this points down at the button
    # that opens it.
    def no_watches_in_app = "No watches yet — the button below makes one."

    # Sent when the app's Contact pill hands somebody off to the bot, and when
    # `/feedback` is typed by hand. Spells out three things at once: any format
    # is welcome (that is the reason feedback lives in the bot chat rather than
    # in an in-app textarea, see ADR-0002), no reply is promised, and the
    # message does reach a person.
    def feedback_prompt
      "Write anything — text, photo, video, voice — I'll read it. " \
        "No promise of a reply, but every message gets to the owner."
    end

    # Reply sent after each forwarded feedback message. Random from a pool
    # rather than a fixed string, so a person who writes three thoughts in a
    # row does not read the same sentence three times and start to wonder if
    # the bot heard them at all. Half of the phrases proactively spell out the
    # one-way contract; the other half stay short.
    FEEDBACK_ACKS = [
      "Got it, thanks.",
      "Thanks — noted and passed to the owner.",
      "Received. Will be read.",
      "Thanks. Write again any time.",
      "Copy that.",
      "Thanks, filed.",
      "Got it. The owner will see this.",
      "Received — no reply promised, but read for sure.",
      "Thanks. Added to the pile.",
      "Got it. Send more if you think of more."
    ].freeze

    def feedback_ack = FEEDBACK_ACKS.sample

    # Prefix on the bot's own message just before the forwarded edit lands in
    # the owner's chat. Reads as "the message below is an edit, not a fresh
    # one" — matters when the same person sends "wrong price at 19:00" and
    # then changes it to "20:00".
    def feedback_edited = "↑ edited"

    # The pill's copy is a hint about which kind of feedback the screen is
    # best placed to catch. Kept per-screen rather than a single generic line
    # so a person on Slots sees the invitation their frustration matches.
    def feedback_pill_dates = "Ideas or bugs? Tell us"

    def feedback_pill_clubs = "Missing a club? Tell us"

    def feedback_pill_slots = "Times look wrong? Tell us"

    # The Share screen's own copy. Kept here for the same reason as the rest:
    # the screen and its specs read one string.
    def share_send = "Send to a chat"

    def share_copy = "Copy text"

    def share_copied = "Copied"

    def share_nothing = "Nothing free here — pick a wider span or more clubs."

    def share_all_clubs = "All"

    def share_favourites = "Favourites"

    def share_pick_clubs = "Pick"

    # Asked for Favourites before starring any. Points at where the stars are
    # rather than apologising: every club is shown in the meantime.
    def share_no_favourites = "No favourites yet — star clubs on the day's list. Showing every club for now."

    # Over the week: how long ago the City's newest good Poll finished, so a
    # quiet morning reads as quiet rather than as a poller that has stopped.
    def updated_ago(seconds)
      minutes = seconds.to_i / 60
      if minutes < 1 then "Updated just now"
      elsif minutes < 60 then "Updated #{minutes} min ago"
      elsif minutes < 1440 then "Updated #{minutes / 60} h ago"
      else "Updated #{minutes / 1440} d ago"
      end
    end

    # A screen reader hears the star as the action it takes, not as a glyph.
    def favourite_add = "Add to favourites"

    def favourite_remove = "Remove from favourites"

    # --- The Forecast --------------------------------------------------------

    # One line over a date's clubs: when it will rain, if it will.
    def weather_outlook(outlook)
      if outlook.wet? || outlook.damp? then "#{outlook.icon} #{weather_headline(outlook)}"
      else ["🌤 #{weather_headline(outlook)}", temperature_range(outlook)].compact.join(" · ")
      end
    end

    # The same line without its icon, for a screen that draws its own.
    def weather_headline(outlook)
      if outlook.wet? then "Rain likely #{weather_runs(outlook.wet_runs)}"
      elsif outlook.damp? then "Showers possible #{weather_runs(outlook.damp_runs)}"
      else "No rain expected"
      end
    end

    # The outlook with how warm it gets even when it rains: a message headed
    # for a chat has no hour-by-hour marks below it to read that off.
    def weather_brief(outlook)
      return weather_outlook(outlook) unless outlook.wet? || outlook.damp?

      [weather_outlook(outlook), temperature_range(outlook)].compact.join(" · ")
    end

    def temperature_range(outlook)
      low, high = outlook.temperatures

      "#{low.round}–#{high.round}°" if low
    end

    # Said whenever the list has been reordered for it, so the order does not
    # look like a mistake.
    def weather_roofed_first = "Clubs with a roof come first."

    # Beside one hour: "🌧 Rain 70% · 14°", "🌦 30% · 16°", "☀️ 21°".
    def weather_tag(hour)
      chance = ("#{hour.rain_chance}%" if hour.rain_chance)
      temperature = ("#{hour.temperature.round}°" if hour.temperature)
      said =
        if hour.wet? then ["Rain", chance].compact.join(" ")
        elsif hour.damp? then chance
        end

      [hour.icon, [said, temperature].compact.join(" · ")].join(" ").strip
    end

    def weather_runs(runs) = runs.map { "#{local_clock(_1)}–#{local_clock(_2)}" }.join(", ")

    # --- A Club's Profile ---------------------------------------------------

    # "2 indoor · 3 covered": every court counted, under its Cover.
    def cover_summary(covers) = covers.map { |cover, count| "#{count} #{cover}" }.join(" · ")

    def cover_label(cover) = cover.to_s.capitalize

    # "Every day", "Mon–Fri", "Sat": the days one run of Listed hours covers.
    def day_run(first, last)
      return "Every day" if first == "mon" && last == "sun"

      first == last ? first.capitalize : "#{first.capitalize}–#{last.capitalize}"
    end

    # "40 GEL · 11:00–18:00", "60 GEL · Sat, Sun", "from 40 GEL": one rule off
    # a club's price list, per court and per hour.
    def price_line(price)
      amount = "#{"from " if price["from_price"]}#{price["gel"]} GEL"
      when_parts = []
      when_parts << price["days"].map(&:capitalize).join(", ") if price["days"]
      when_parts << "#{price["from"]}–#{price["to"]}" if price["from"] && price["to"]

      [amount, *when_parts].join(" · ")
    end

    def profile_missing = "No details for this club yet — the booking page is the place to look."

    # Said under every Profile, because none of it is ours: it is what the club
    # told a directory, and a directory can be behind.
    def profile_source(checked_on)
      as_of = checked_on ? ", as of #{checked_on.day} #{checked_on.strftime("%b")}" : ""

      "Courts, hours and prices are the club's own listing on sapadelo.com#{as_of} — " \
        "check with the club before you rely on them. The day's free hours come from its booking system."
    end
  end
end
