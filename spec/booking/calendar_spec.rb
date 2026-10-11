RSpec.describe Booking::Calendar do
  let(:event) do
    Booking::Calendar::Event.new(
      uid: "kus-tba-padel-20261014T150000Z-2h@kortuli",
      title: "🎾 Padel · Kus Tba Padel",
      starts_at: Booking::Clock.local_to_utc("2026-10-14 19:00"),
      ends_at: Booking::Clock.local_to_utc("2026-10-14 21:00"),
      location: "GymBreeze, 64 Egnate Ninoshvili St; Chugureti",
      details: "80 GEL an hour\nMap: https://www.google.com/maps/search/?api=1&query=41.7,44.75",
      url: "https://app.example/game/kus-tba-padel/2026-10-14/19-21"
    )
  end

  describe "Google's link" do
    def query = URI.decode_www_form(URI(described_class.google_url(event)).query).to_h

    # Tbilisi is UTC+4: 19:00 there is 15:00 everywhere a calendar counts.
    it "carries the event in UTC, so every calendar puts it at the same instant" do
      expect(query).to include("action" => "TEMPLATE", "dates" => "20261014T150000Z/20261014T170000Z")
    end

    it "carries the title, the place and the notes as they are" do
      expect(query).to include("text" => event.title, "location" => event.location, "details" => event.details)
    end

    # A `+` for a space is not read back as one by every client.
    it "encodes spaces as %20" do
      expect(described_class.google_url(event)).to include("Padel%20%C2%B7%20Kus")
      expect(described_class.google_url(event)).not_to include("+")
    end
  end

  describe "the iCalendar file" do
    let(:ics) { described_class.ics(event, now: Time.utc(2026, 10, 11, 12)) }
    # Folded lines put back together, the way a calendar reads them.
    let(:unfolded) { ics.gsub("\r\n ", "") }

    it "ends every line the way the standard says, CRLF" do
      expect(ics).to end_with("END:VCALENDAR\r\n")
      expect(ics.delete("\r\n").include?("\n")).to be(false)
    end

    it "is one event, in UTC, with a reminder an hour ahead" do
      expect(unfolded).to include("DTSTART:20261014T150000Z\r\nDTEND:20261014T170000Z")
      expect(unfolded).to include("UID:kus-tba-padel-20261014T150000Z-2h@kortuli")
      expect(unfolded).to include("BEGIN:VALARM").and include("TRIGGER:-PT1H")
    end

    # Commas and semicolons separate values in iCalendar; left bare, an
    # address arrives as three of them.
    it "escapes what iCalendar would read as structure" do
      expect(unfolded).to include("LOCATION:GymBreeze\\, 64 Egnate Ninoshvili St\\; Chugureti")
      expect(unfolded).to include("DESCRIPTION:80 GEL an hour\\nMap: https://")
    end

    it "folds a long line at 75 octets, never through a character" do
      long = described_class.ics(event.with(details: "🎾" * 60), now: Time.utc(2026, 10, 11, 12))

      expect(long.split("\r\n").map(&:bytesize).max).to be <= 75
      expect(long.split("\r\n").all?(&:valid_encoding?)).to be(true)
      expect(long.gsub("\r\n ", "")).to include("DESCRIPTION:#{"🎾" * 60}\r\n")
    end
  end
end
