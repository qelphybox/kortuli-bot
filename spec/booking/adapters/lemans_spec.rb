require "json"

# Answers from a recorded copy of the real /api/availability response, so the
# parsing stays pinned to what the club actually sends.
class FakeLemansHttp
  attr_reader :requests

  def initialize(payload: nil)
    @requests = []
    @payload = payload
  end

  def get_json(url, params = {})
    @requests << { url:, params: }
    @payload || JSON.parse(File.read("spec/fixtures/lemans_availability.json"))
  end
end

RSpec.describe Booking::Adapters::Lemans do
  subject(:adapter) { described_class.new(club, http:, clock:) }

  let(:http) { FakeLemansHttp.new }
  let(:clock) { Struct.new(:now).new(Booking::Clock.local_to_utc("2026-10-10 12:00")) }
  let(:club) do
    Booking::Club.new(
      slug: "lemans-padel",
      name: "Lemans Padel",
      adapter: "lemans",
      settings: {
        "booking_url" => "https://lemanspadel.ge/book-padel/",
        "price" => "70 GEL",
        "max_days" => 14,
        "courts" => 4
      }
    )
  end
  # The recorded day: everything open in the morning, 17:00–19:00 sold out,
  # one or two courts left through the evening, and 00:00 and 01:00 filed by
  # the source on the day after.
  let(:one_day) { Date.new(2026, 10, 11)..Date.new(2026, 10, 11) }

  def free_at(hour, date: Date.new(2026, 10, 11))
    adapter.fetch(one_day).count { _1.local_date == date && _1.local_starts_at.hour == hour }
  end

  it "asks for a whole day of hour-long bookings in one request" do
    adapter.fetch(one_day)

    expect(http.requests).to eq([{ url: "https://booking.lemanspadel.ge/api/availability",
                                   params: { "date" => "2026-10-11", "duration" => 60 } }])
  end

  # The count is what makes this a court-level club: a cell can say 2/4.
  it "returns one slot per court the club says is free" do
    expect(free_at(8)).to eq(4)
    expect(free_at(12)).to eq(2)
    expect(free_at(16)).to eq(1)
  end

  it "leaves out the hours nobody can book" do
    expect([17, 18, 19].map { free_at(_1) }).to eq([0, 0, 0])
  end

  # The Grid matches a Cell on an exact hourly start; an 08:30 slot would
  # match nothing on screen and still raise notifications.
  it "drops the starts on the half hour" do
    expect(adapter.fetch(one_day).map { _1.local_starts_at.min }.uniq).to eq([0])
  end

  # The cancellation worth sending: one court left, then two. Watched by the
  # hour, as Kus Tba is, this would raise nothing.
  it "frees a slot when one more court comes back in an hour that had one" do
    one_left = described_class.new(club, http: FakeLemansHttp.new(payload: day_with(21 => 1)), clock:).fetch(one_day)
    two_left = described_class.new(club, http: FakeLemansHttp.new(payload: day_with(21 => 2)), clock:).fetch(one_day)

    result = Booking::Differ.new.diff(previous: one_left, current: two_left, known_through: one_day.last)

    expect(result.became_available.size).to eq(1)
  end

  # The count says how many, never which — so the slot does not pretend.
  it "calls the court 'a court', not a number it does not have" do
    expect(adapter.fetch(one_day).map(&:court_label).uniq).to eq(["A court"])
  end

  it "files the hours past midnight on the date they fall on" do
    expect(free_at(0, date: Date.new(2026, 10, 12))).to eq(3)
    expect(free_at(1, date: Date.new(2026, 10, 12))).to eq(4)
  end

  it "normalises the club's local time into UTC at the boundary" do
    first = adapter.fetch(one_day).min_by(&:starts_at)

    # 08:00 in Tbilisi (+04:00) is 04:00 UTC.
    expect(first.starts_at).to eq(Time.utc(2026, 10, 11, 4, 0))
  end

  it "carries the club's price and booking page" do
    slot = adapter.fetch(one_day).first

    expect(slot.price).to eq("70 GEL")
    expect(slot.deeplink).to eq("https://lemanspadel.ge/book-padel/")
    expect(slot.duration_minutes).to eq(60)
  end

  # The API answers for any date, including past ones, with a full free grid.
  it "leaves out hours that have already started" do
    late = Struct.new(:now).new(Booking::Clock.local_to_utc("2026-10-11 20:30"))
    hours = described_class.new(club, http:, clock: late).fetch(one_day).map { _1.local_starts_at.hour }.uniq

    expect(hours).to eq([21, 22, 23, 0, 1])
  end

  # Far dates read entirely free because nobody can have booked them yet;
  # they would never transition, so they are never asked about.
  it "asks about no more days than the club is configured to look ahead" do
    short = Booking::Club.new(**club.to_h, settings: club.settings.merge("max_days" => 2))
    described_class.new(short, http:, clock:).fetch(Date.new(2026, 10, 11)..Date.new(2026, 10, 17))

    expect(http.requests.size).to eq(2)
  end

  # A refusal answers 200 with an error body. Read literally, that is every
  # court in the club sold out at once.
  it "treats an error body as an unreadable source, not as a full day" do
    refused = described_class.new(club, http: FakeLemansHttp.new(payload: { "error" => "Invalid parameters" }), clock:)

    expect { refused.fetch(one_day) }.to raise_error(Booking::Adapters::SourceUnavailable)
  end

  it "is registered under its adapter name" do
    expect(Booking::Adapters.build(club, http:)).to be_a(described_class)
  end

  def day_with(free_by_hour)
    slots = free_by_hour.map do |hour, count|
      { "start" => format("%02d:00", hour), "start_datetime" => format("2026-10-11 %02d:00:00", hour),
        "available" => count.positive?, "available_courts" => count }
    end

    { "date" => "2026-10-11", "slots" => slots }
  end
end
