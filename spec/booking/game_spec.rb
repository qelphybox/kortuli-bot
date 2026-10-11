RSpec.describe Booking::Game do
  def game(**overrides)
    described_class.new(
      club_slug: "kus-tba-padel", club_name: "Kus Tba Padel",
      starts_at: Booking::Clock.local_to_utc("2026-10-14 19:00"), ends_at: Booking::Clock.local_to_utc("2026-10-14 21:00"),
      price: "80 GEL", place: "Turtle Lake",
      maps_url: "https://www.google.com/maps/search/?api=1&query=41.7,44.75",
      booking_url: "https://kustba.example/book/",
      card_url: "https://app.example/game/kus-tba-padel/2026-10-14/19-21",
      **overrides
    )
  end

  def wet_hour = Booking::Weather::Hour.new(starts_at: game.starts_at, rain_chance: 70, rain_mm: 1.0, code: 61, temperature: 14.2, day: false)

  describe "as the message the group gets" do
    it "says where, when, what the sky does, what it costs, the pin and the calendar link" do
      expect(Booking::Messages.game(game, weather: wet_hour)).to eq(<<~TEXT.strip)
        🎾 Court booked · Kus Tba Padel
        Wed 14 Oct, 19:00–21:00
        🌧 Rain 70% · 14°
        💸 80 GEL an hour
        📍 Turtle Lake https://www.google.com/maps/search/?api=1&query=41.7,44.75
        📅 Add to calendar: https://app.example/game/kus-tba-padel/2026-10-14/19-21
      TEXT
    end

    # Padel Club 2 has no Profile, and before the first fetch there is no
    # Forecast: a line with nothing to say is left out rather than guessed.
    it "leaves out what it does not know" do
      text = Booking::Messages.game(game(price: nil, place: nil, maps_url: nil))

      expect(text).to eq(<<~TEXT.strip)
        🎾 Court booked · Kus Tba Padel
        Wed 14 Oct, 19:00–21:00
        📅 Add to calendar: https://app.example/game/kus-tba-padel/2026-10-14/19-21
      TEXT
    end

    it "keeps the pin when the Profile has no street to name" do
      expect(Booking::Messages.game(game(place: nil))).to include("📍 https://www.google.com/maps/")
    end

    # Ticked under Tuesday evening, but whoever reads it plays on Wednesday.
    it "dates a game after midnight by the day it starts on" do
      late = game(starts_at: Booking::Clock.local_to_utc("2026-10-15 00:00"), ends_at: Booking::Clock.local_to_utc("2026-10-15 02:00"))

      expect(Booking::Messages.game_when(late)).to eq("Thu 15 Oct, 00:00–02:00")
    end
  end

  describe "as a calendar event" do
    it "is the hours booked, at the club, with what to hand over at the desk" do
      event = game.to_event

      expect(event.title).to eq("🎾 Padel · Kus Tba Padel")
      expect([event.starts_at, event.ends_at]).to eq([game.starts_at, game.ends_at])
      expect(event.location).to eq("Kus Tba Padel, Turtle Lake")
      expect(event.details).to include("80 GEL an hour").and include("Map: https://www.google.com/maps/")
      expect(event.url).to eq(game.card_url)
    end

    # Adding the same game twice should update it, not double it.
    it "has the same identity however many times it is built" do
      expect(game.to_event.uid).to eq(game.to_event.uid)
      expect(game.to_event.uid).not_to eq(game(ends_at: game.ends_at + 3600).to_event.uid)
    end
  end
end
