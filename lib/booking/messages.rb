module Booking
  # Every user-facing string lives here. English only for now — the mechanism
  # for choosing a language is deliberately absent, but keeping the strings in
  # one place means adding it later is a new file, not an excavation.
  module Messages
    DAY_NAMES = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

    module_function

    def escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

    def slot_freed(slot, club_name)
      lines = ["🎾 <b>#{escape(slot.court_label)}</b> just freed up", "#{escape(club_name)} · #{when_phrase(slot)}"]
      lines << escape(slot.price) if slot.price
      lines << escape(slot.deeplink) if slot.deeplink
      lines.join("\n")
    end

    def when_phrase(slot)
      starts = slot.local_starts_at
      ends = Clock.to_local(slot.ends_at)
      "#{DAY_NAMES[starts.wday]} #{starts.day} #{starts.strftime("%b")}, #{starts.strftime("%H:%M")}–#{ends.strftime("%H:%M")}"
    end

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

        Evening courts in Tbilisi get taken a day or two ahead and only come back when somebody cancels. This watches for those cancellations and pings you the moment one happens.

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
  end
end
