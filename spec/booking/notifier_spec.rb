RSpec.describe Booking::Notifier do
  subject(:notifier) { described_class.new(notifications:, transport:, clubs: { "reservio-demo" => "Demo Club" }) }

  let(:db) { Booking::DB.connect("sqlite:/") }
  let(:notifications) { Booking::Repo::Notifications.new(db) }
  let(:transport) { FakeTransport.new }

  class FakeTransport
    attr_reader :sent

    def initialize(failing_for: []) = (@sent = []; @failing_for = failing_for)

    def send_message(chat_id:, text:)
      raise StandardError, "blocked" if @failing_for.include?(chat_id)

      @sent << { chat_id:, text: }
    end
  end

  def candidate(watch_id: 1, user_id: 42, at: "2026-08-01 19:00")
    watch = Booking::Watch.new(
      id: watch_id, user_id:, club_slugs: ["reservio-demo"], weekdays: [6],
      from_minute: 0, to_minute: 1440, active: true
    )
    Booking::Matcher::Candidate.new(watch:, slot: slot(at:, price: "50 GEL"))
  end

  it "sends one message per candidate" do
    notifier.deliver([candidate(watch_id: 1, user_id: 42), candidate(watch_id: 2, user_id: 99)])

    expect(transport.sent.map { _1[:chat_id] }).to contain_exactly(42, 99)
  end

  it "reports how many it actually sent" do
    expect(notifier.deliver([candidate])).to eq(1)
  end

  it "describes the slot in the message" do
    notifier.deliver([candidate])

    text = transport.sent.first[:text]
    expect(text).to include("Court 1")
    expect(text).to include("Demo Club")
    expect(text).to include("19:00")
    expect(text).to include("https://example.test/book")
  end

  describe "with the Forecast" do
    subject(:notifier) do
      described_class.new(notifications:, transport:, clubs: { "reservio-demo" => "Demo Club" }, forecast:, logger: said.method(:<<))
    end

    let(:forecast) { Booking::Repo::Forecast.new(db) }
    let(:said) { [] }

    def forecast_hour(at, chance:)
      Booking::Weather::Hour.new(starts_at: Booking::Clock.local_to_utc(at), rain_chance: chance, rain_mm: 0.0,
                                 code: 61, temperature: 14.2, day: false)
    end

    it "says whether it will rain on the hour that freed up" do
      forecast.replace([forecast_hour("2026-08-01 19:00", chance: 80), forecast_hour("2026-08-01 20:00", chance: 0)], city: "Tbilisi")
      notifier.deliver([candidate])

      expect(transport.sent.first[:text].lines.map(&:chomp)).to include("🌧 Rain 80% · 14°")
    end

    # A dry evening in Tbilisi says nothing about the court in Batumi.
    it "reads the sky over the city the club is in" do
      forecast.replace([forecast_hour("2026-08-01 19:00", chance: 0)], city: "Tbilisi")
      forecast.replace([forecast_hour("2026-08-01 19:00", chance: 80)], city: "Batumi")
      notifier = described_class.new(notifications:, transport:, clubs: { "reservio-demo" => "Demo Club" },
                                     cities: { "reservio-demo" => "Batumi" }, forecast:)
      notifier.deliver([candidate])

      expect(transport.sent.first[:text].lines.map(&:chomp)).to include("🌧 Rain 80% · 14°")
    end

    it "sends the message without weather where the Forecast does not reach" do
      forecast.replace([forecast_hour("2026-08-05 19:00", chance: 80)], city: "Tbilisi")
      notifier.deliver([candidate])

      expect(transport.sent.first[:text]).not_to include("°")
    end

    # The weather is a courtesy; the message is the job.
    it "still sends when the Forecast cannot be read" do
      broken = Object.new.tap { |o| def o.hours(_city) = raise(Sequel::DatabaseError, "locked") }
      notifier = described_class.new(notifications:, transport:, forecast: broken, logger: said.method(:<<))

      expect(notifier.deliver([candidate])).to eq(1)
      expect(said.first).to start_with("notify: forecast unreadable")
    end
  end

  describe "not saying the same thing twice" do
    it "stays silent when the same slot comes round again" do
      notifier.deliver([candidate])
      notifier.deliver([candidate])

      expect(transport.sent.size).to eq(1)
    end

    it "still tells a second watcher about the same slot" do
      notifier.deliver([candidate(watch_id: 1, user_id: 42)])
      notifier.deliver([candidate(watch_id: 2, user_id: 99)])

      expect(transport.sent.size).to eq(2)
    end
  end

  describe "when Telegram refuses a message" do
    let(:transport) { FakeTransport.new(failing_for: [42]) }

    it "still delivers to everybody else in the batch" do
      notifier.deliver([candidate(watch_id: 1, user_id: 42), candidate(watch_id: 2, user_id: 99)])

      expect(transport.sent.map { _1[:chat_id] }).to eq([99])
    end

    it "leaves the slot eligible to be retried rather than muting it forever" do
      notifier.deliver([candidate(watch_id: 1, user_id: 42)])

      expect(notifications.sent?(watch_id: 1, slot_key: candidate.slot.key)).to be(false)
    end
  end
end
