require "json"

# Answers from recorded copies of the real tRPC responses, taken on the
# evening of 2026-10-13: the court list, and `getBookedSlots` for all three
# courts on the 13th, 14th and 15th. The 13th was busy from 20:00 on; the
# 14th held two bookings; the 15th none.
class FakePadelgldaniHttp
  attr_reader :requests

  def initialize(courts: nil, booked: {})
    recorded = JSON.parse(File.read("spec/fixtures/padelgldani_booked_slots.json", encoding: "UTF-8"))
    @courts = courts || recorded["courts"]
    # Recorded batches are courts 1, 2, 3 in that order; kept per court so a
    # test can ask about fewer.
    @booked = recorded["booked"].transform_values { |batch| batch.each_with_index.to_h { |call, i| [i + 1, call.dig("result", "data", "json")] } }
    booked.each { |date, by_court| (@booked[date] ||= {}).merge!(by_court) }
    @requests = []
  end

  def get_json(url, params = {})
    @requests << { url:, params: }
    return @courts if url.end_with?("/courts.list")

    JSON.parse(params["input"]).values.map do |call|
      { "result" => { "data" => { "json" => @booked.fetch(call.dig("json", "date"), {}).fetch(call.dig("json", "courtId"), []) } } }
    end
  end

  def booked_requests = requests.reject { _1[:url].end_with?("/courts.list") }

  def dates_asked = booked_requests.map { JSON.parse(_1[:params]["input"]).values.map { |call| call.dig("json", "date") }.uniq }
end

RSpec.describe Booking::Adapters::Padelgldani do
  let(:http) { FakePadelgldaniHttp.new }
  let(:club) do
    Booking::Club.new(
      slug: "padel-gldani",
      name: "Padel Gldani",
      adapter: "padelgldani",
      settings: {
        "booking_url" => "https://padelgldani.ge/booking",
        "price" => "50–70 GEL",
        "opening_hours" => { "from" => "08:00", "to" => "02:00" },
        "courts" => 3,
        "max_days" => 14
      }
    )
  end
  let(:one_day) { Date.new(2026, 10, 13)..Date.new(2026, 10, 13) }
  let(:before_the_day) { Booking::Clock.local_to_utc("2026-10-12 12:00") }

  def fetch(range = one_day, now: before_the_day)
    described_class.new(club, http:, clock: Struct.new(:now).new(now)).fetch(range)
  end

  def hours(slots, court) = slots.select { _1.court_ref == court }.map { _1.local_starts_at.hour }

  # Eighteen starts a day, 08:00 to 01:00, on three courts — less eleven
  # booked hours that night: three on court 1, four each on courts 2 and 3.
  it "returns the day's grid minus what is booked" do
    expect(fetch.size).to eq((18 * 3) - 11)
  end

  it "leaves out every hour a booked interval covers" do
    expect(hours(fetch, "3")).not_to include(20, 21, 22, 23)
    expect(hours(fetch, "3")).to include(19, 0, 1)
  end

  # 23:00–01:00 is one row; the hour after midnight is inside it.
  it "reads an interval across midnight as one span" do
    expect(hours(fetch, "1")).not_to include(23, 0)
    expect(hours(fetch, "1")).to include(1)
  end

  # The site's own rule, and the reason a day costs two dates: the 14th's
  # answer carried a 00:00 row dated the 13th on court 1 and one dated the
  # 14th on court 2. Both are the 13th's midnight.
  describe "the night after midnight" do
    it "takes the hours before 08:00 from the next date's answer" do
      expect(hours(fetch, "2")).not_to include(0)
      expect(hours(fetch, "2")).to include(1)
    end

    it "does not count them against the date they are filed under" do
      next_day = Date.new(2026, 10, 14)..Date.new(2026, 10, 14)

      expect(hours(fetch(next_day), "2")).to include(0)
      expect(hours(fetch(next_day), "1")).not_to include(20)
    end

    it "files the 01:00 start on the following calendar day" do
      late = fetch.find { _1.court_ref == "3" && _1.local_starts_at.hour == 1 }

      expect(late.local_date).to eq(Date.new(2026, 10, 14))
      expect(late.starts_at).to eq(Time.utc(2026, 10, 13, 21, 0))
    end
  end

  # tRPC batches: three courts, one request — and each date once a tick,
  # though every day reads its own date and the next.
  it "asks about every court of a date in one request, and each date once" do
    fetch(Date.new(2026, 10, 13)..Date.new(2026, 10, 14))

    expect(http.dates_asked).to eq([["2026-10-13"], ["2026-10-14"], ["2026-10-15"]])
    expect(http.booked_requests.first[:url])
      .to end_with("/bookings.getBookedSlots,bookings.getBookedSlots,bookings.getBookedSlots")
    expect(JSON.parse(http.booked_requests.first[:params]["input"]).values.map { _1.dig("json", "courtId") }).to eq([1, 2, 3])
  end

  # The source names its courts, so this is a court-level club.
  it "names the court each slot is on" do
    expect(fetch.map(&:court_ref).uniq).to contain_exactly("1", "2", "3")
  end

  it "prints the court's name without the Georgian cover after it" do
    expect(fetch.find { _1.court_ref == "1" }.court_label).to eq("Croco Court I")
    expect(fetch.find { _1.court_ref == "3" }.court_label).to eq("Court III")
  end

  it "links each slot to its own court's booking page" do
    expect(fetch.find { _1.court_ref == "2" }.deeplink).to eq("https://padelgldani.ge/booking?court=2")
  end

  # The site exempts only the visitor's own payment hold; anyone else's hold,
  # or a booking awaiting payment, keeps the hour off the grid.
  it "holds an hour while someone's payment is pending" do
    hold = { "startTime" => "10:00", "endTime" => "11:00", "bookingDate" => "2026-10-13", "isHold" => true,
             "expiresAt" => "2026-10-13T06:10:00.000Z", "sessionId" => "abc", "isPending" => true }
    http = FakePadelgldaniHttp.new(booked: { "2026-10-13" => { 3 => [hold] } })
    slots = described_class.new(club, http:, clock: Struct.new(:now).new(before_the_day)).fetch(one_day)

    expect(hours(slots, "3")).not_to include(10)
  end

  # Under maintenance a court answers with nothing booked; inverted, that is a
  # whole day of hours nobody can buy.
  it "leaves out a court the site is not selling" do
    courts = JSON.parse(File.read("spec/fixtures/padelgldani_booked_slots.json", encoding: "UTF-8"))["courts"]
    courts.first.dig("result", "data", "json").last["status"] = "maintenance"
    http = FakePadelgldaniHttp.new(courts:)
    slots = described_class.new(club, http:, clock: Struct.new(:now).new(before_the_day)).fetch(one_day)

    expect(slots.map(&:court_ref).uniq).to contain_exactly("1", "2")
    expect(JSON.parse(http.booked_requests.first[:params]["input"]).size).to eq(2)
  end

  # Subtracting bookings from a grid hands back the hours already gone too.
  it "drops hours that have already started" do
    slots = fetch(now: Booking::Clock.local_to_utc("2026-10-13 15:30"))

    expect(slots.map { _1.local_starts_at.hour }.uniq).to all(satisfy { _1 >= 16 || _1 <= 1 })
  end

  it "stops at the club's max_days" do
    capped = club.with(settings: club.settings.merge("max_days" => 2))
    described_class.new(capped, http:, clock: Struct.new(:now).new(before_the_day)).fetch(Date.new(2026, 10, 13)..Date.new(2026, 10, 19))

    expect(http.dates_asked.flatten).to eq(%w[2026-10-13 2026-10-14 2026-10-15])
  end

  # Inverted, an empty or broken answer reads as every hour free — the loudest
  # false alarm this adapter could raise. All of these are refusals, not data.
  describe "when the source misbehaves" do
    it "fails the tick when no court is selling" do
      http = FakePadelgldaniHttp.new(courts: [{ "result" => { "data" => { "json" => [] } } }])

      expect { described_class.new(club, http:).fetch(one_day) }
        .to raise_error(Booking::Adapters::SourceUnavailable, /no bookable courts/)
    end

    it "fails the tick when a call in the batch answers with an error" do
      http = FakePadelgldaniHttp.new
      def http.get_json(url, params = {})
        return super unless url.include?("getBookedSlots")

        [{ "result" => { "data" => { "json" => [] } } },
         { "error" => { "json" => { "message" => "Too many requests", "code" => -32_029 } } },
         { "result" => { "data" => { "json" => [] } } }]
      end

      expect { described_class.new(club, http:).fetch(one_day) }
        .to raise_error(Booking::Adapters::SourceUnavailable, /expected 3 tRPC results/)
    end

    it "fails the tick when a court's answer is not a list" do
      http = FakePadelgldaniHttp.new(booked: { "2026-10-13" => { 2 => { "startTime" => "20:00" } } })

      expect { described_class.new(club, http:).fetch(one_day) }
        .to raise_error(Booking::Adapters::SourceUnavailable, /expected a list of bookings for court 2/)
    end
  end
end
