require "uri"

module Booking
  # One event, in the two shapes a phone knows how to add to a calendar:
  # Google Calendar's own "add this" link, and an iCalendar file for
  # everything else — Apple's Calendar, Outlook, and Android apps that are not
  # Google's.
  #
  # Both carry UTC and nothing else: a calendar shows an event in whatever
  # zone its owner lives in, and only UTC means the same instant to all of
  # them.
  module Calendar
    Event = Data.define(:uid, :title, :starts_at, :ends_at, :location, :details, :url)

    # How far ahead the phone reminds you: long enough to get across Tbilisi
    # in the evening.
    REMINDER = "-PT1H".freeze

    # RFC 5545 caps a line at 75 octets, counted in bytes rather than
    # characters — an emoji is four of them.
    LINE_OCTETS = 75

    module_function

    def stamp(time) = time.getutc.strftime("%Y%m%dT%H%M%SZ")

    # Google's documented, keyless template link. It opens the event already
    # filled in, with one Save between it and the calendar.
    def google_url(event)
      query = {
        action: "TEMPLATE",
        text: event.title,
        dates: "#{stamp(event.starts_at)}/#{stamp(event.ends_at)}",
        location: event.location,
        details: event.details
      }

      "https://calendar.google.com/calendar/render?#{query.map { "#{_1}=#{URI.encode_uri_component(_2.to_s)}" }.join("&")}"
    end

    def ics(event, now: Clock.now)
      lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//kortuli//padel//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "BEGIN:VEVENT",
        "UID:#{event.uid}",
        "DTSTAMP:#{stamp(now)}",
        "DTSTART:#{stamp(event.starts_at)}",
        "DTEND:#{stamp(event.ends_at)}",
        "SUMMARY:#{text(event.title)}",
        "LOCATION:#{text(event.location)}",
        "DESCRIPTION:#{text(event.details)}",
        ("URL:#{event.url}" if event.url),
        "BEGIN:VALARM",
        "ACTION:DISPLAY",
        "DESCRIPTION:#{text(event.title)}",
        "TRIGGER:#{REMINDER}",
        "END:VALARM",
        "END:VEVENT",
        "END:VCALENDAR"
      ]

      lines.compact.map { fold(_1) }.join("\r\n") + "\r\n"
    end

    # Commas and semicolons separate values in iCalendar, so a street address
    # left as it is would arrive as three of them.
    def text(value) = value.to_s.gsub(/[\\;,]/) { "\\#{_1}" }.gsub("\n", "\\n")

    # A long line goes on over the next ones, each starting with a space — and
    # is never cut through the middle of a character.
    def fold(line)
      chunks = [+""]
      line.each_char do |char|
        limit = chunks.size == 1 ? LINE_OCTETS : LINE_OCTETS - 1
        chunks << +"" if chunks.last.bytesize + char.bytesize > limit
        chunks.last << char
      end

      chunks.join("\r\n ")
    end
  end
end
