require "json"

# Answers from recorded copies of the real Supabase responses for 2026-10-12:
# the active court list, and the RPC's booked rows for each court that day.
class FakePadelhubHttp
  attr_reader :requests

  def initialize(courts: nil, availability: nil)
    recorded = JSON.parse(File.read("spec/fixtures/padelhub_availability.json"))
    @courts = courts || recorded["courts"]
    @availability = availability || recorded["availability"]
    @requests = []
  end

  def get_json(url, params = {}, headers: {})
    @requests << { url:, params:, headers: }
    @courts
  end

  def post_json(url, body = {}, headers: {})
    @requests << { url:, body:, headers: }
    @availability.fetch(body["p_court_id"], [])
  end
end

RSpec.describe Booking::Adapters::Padelhub do
  let(:http) { FakePadelhubHttp.new }
  let(:club) do
    Booking::Club.new(
      slug: "padelhub",
      name: "PadelHub",
      adapter: "padelhub",
      settings: {
        "booking_url" => "https://www.padelhub.ge/booking",
        "price" => "40–70 GEL",
        "opening_hours" => { "from" => "08:00", "to" => "01:00" },
        "courts" => 3,
        "court_labels" => { "court_padel_closed_2" => "Indoor 2" }
      }
    )
  end
  let(:one_day) { Date.new(2026, 10, 12)..Date.new(2026, 10, 12) }
  let(:before_the_day) { Booking::Clock.local_to_utc("2026-10-11 12:00") }
  let(:indoor_2) { "bce555f2-8568-498b-b6cc-55ca1ef71d16" }

  def fetch(range = one_day, now: before_the_day)
    described_class.new(club, http:, clock: Struct.new(:now).new(now)).fetch(range)
  end

  def hours(slots, court) = slots.select { _1.court_ref == court }.map { _1.local_starts_at.hour }

  # Seventeen starts a day on three padel courts, less the twelve booked rows
  # recorded that day.
  it "returns the day's grid minus what is booked" do
    expect(fetch.size).to eq((17 * 3) - 12)
  end

  it "leaves out the hours a confirmed booking holds" do
    expect(hours(fetch, indoor_2)).not_to include(18, 19, 20, 21)
    expect(hours(fetch, indoor_2)).to include(17, 22)
  end

  # Pickleball shares the courts table and the RPC, and is no use to anyone
  # looking for a padel court.
  it "asks only about the padel courts" do
    fetch

    asked = http.requests.filter_map { _1.dig(:body, "p_court_id") }
    expect(asked).not_to include("154545c2-e962-4d85-8e1a-9bf5bcfa4721")
    expect(asked.size).to eq(3)
  end

  # The club already opened one more court after it was first looked at, so
  # the list is read from the source rather than pinned.
  it "watches whatever padel courts the source lists" do
    expect(fetch.map(&:court_ref).uniq.size).to eq(3)
  end

  it "prints the court under the label config gives it" do
    expect(fetch.find { _1.court_ref == indoor_2 }.court_label).to eq("Indoor 2")
  end

  it "sends the publishable key the site itself sends" do
    fetch

    expect(http.requests).to all(include(headers: include("apikey" => described_class::ANON_KEY)))
  end

  # The site counts a payment in progress as taken, and a cancelled row as
  # nothing at all — the July client's two-hour rule is gone from it.
  describe "what counts as taken" do
    let(:http) do
      FakePadelhubHttp.new(availability: {
        indoor_2 => [
          { "time_slot" => "10:00", "status" => "confirmed", "is_payment_hold" => true },
          { "time_slot" => "11:00", "status" => "cancelled", "is_payment_hold" => false }
        ]
      })
    end

    it "holds an hour while its payment is pending" do
      expect(hours(fetch, indoor_2)).not_to include(10)
    end

    it "frees an hour whose booking was cancelled" do
      expect(hours(fetch, indoor_2)).to include(11)
    end
  end

  # The grid's last start is 00:00, and it belongs to the night of the date
  # asked about — the next calendar day.
  it "files the midnight start on the following day" do
    midnight = fetch.find { _1.court_ref == indoor_2 && _1.local_starts_at.hour.zero? }

    expect(midnight.local_date).to eq(Date.new(2026, 10, 13))
    expect(midnight.starts_at).to eq(Time.utc(2026, 10, 12, 20, 0))
  end

  # Subtracting bookings from a grid hands back the hours already gone too.
  it "drops hours that have already started" do
    slots = fetch(now: Booking::Clock.local_to_utc("2026-10-12 15:30"))

    expect(slots.map { _1.local_starts_at.hour }.uniq).to all(satisfy { _1 >= 16 || _1.zero? })
  end

  it "stops at the club's max_days" do
    week = Date.new(2026, 10, 12)..Date.new(2026, 10, 18)
    capped = club.with(settings: club.settings.merge("max_days" => 2))
    described_class.new(capped, http:, clock: Struct.new(:now).new(before_the_day)).fetch(week)

    dates = http.requests.filter_map { _1.dig(:body, "p_booking_date") }.uniq
    expect(dates).to eq(%w[2026-10-12 2026-10-13])
  end

  # Inverted, an empty or broken answer reads as every hour free — the loudest
  # false alarm this adapter could raise. Both are refusals, not data.
  describe "when the source misbehaves" do
    it "fails the tick when no padel court is listed" do
      http = FakePadelhubHttp.new(courts: [])

      expect { described_class.new(club, http:).fetch(one_day) }
        .to raise_error(Booking::Adapters::SourceUnavailable, /no padel courts/)
    end

    it "fails the tick when the RPC answers with something other than a list" do
      http = FakePadelhubHttp.new
      def http.post_json(*, **) = { "code" => "PGRST202", "message" => "Could not find the function" }

      expect { described_class.new(club, http:).fetch(one_day) }
        .to raise_error(Booking::Adapters::SourceUnavailable, /expected a list of bookings/)
    end
  end
end
