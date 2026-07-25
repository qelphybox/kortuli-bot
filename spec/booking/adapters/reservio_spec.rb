require "json"

# Answers from recorded copies of the real Reservio responses, so the parsing
# stays pinned to what the service actually sends.
class FakeHttp
  attr_reader :requests

  def initialize(pages: nil)
    @requests = []
    @pages = pages
  end

  def get_json(url, params = {})
    @requests << { url:, params: }
    return fixture("reservio_resources") if url.include?("/resources")
    return @pages.shift if @pages

    fixture("reservio_booking_slots")
  end

  def fixture(name) = JSON.parse(File.read("spec/fixtures/#{name}.json"))
end

RSpec.describe Booking::Adapters::Reservio do
  subject(:adapter) { described_class.new(club, http:) }

  let(:http) { FakeHttp.new }
  let(:club) do
    Booking::Club.new(
      slug: "padel-club-2",
      name: "Padel Club 2",
      adapter: "reservio",
      settings: {
        "business_id" => "4ead107e-6791-4f9b-95d9-3588bffe0794",
        "service_id" => "1b9d8011-d73e-4810-bba8-4098b7ad536b",
        "booking_url" => "https://padel-club2.reservio.com/",
        "price" => "50 GEL"
      }
    )
  end
  let(:window) { Date.new(2026, 8, 1)..Date.new(2026, 8, 7) }

  it "returns one slot per record the service reports as free" do
    expect(adapter.fetch(window).size).to eq(6)
  end

  # §8a: a club that retypes a court name splits one court's identity in two,
  # and the differ reads the split as "everything got booked, everything freed".
  # Only a human-supplied mapping can put the halves back together, so the ref
  # must already be canonical by the time it leaves the adapter.
  context "when the club config maps one court onto another" do
    let(:club) { super().with(settings: super().settings.merge("court_aliases" => { COURT_ID => "Court 1" })) }

    COURT_ID = "2cb9d25d-f436-4f3f-b2a4-eefdc1ffb62e".freeze

    it "hands the poller the mapped ref, not the one the service sent" do
      refs = adapter.fetch(window).map(&:court_ref)

      expect(refs).to include("Court 1")
      expect(refs).not_to include(COURT_ID)
    end
  end

  it "normalises the club's local time into UTC at the boundary" do
    first = adapter.fetch(window).first

    # 08:00 in Tbilisi (+04:00) is 04:00 UTC.
    expect(first.starts_at).to eq(Time.utc(2026, 8, 1, 4, 0))
    expect(first.starts_at.utc?).to be(true)
    expect(first.local_date).to eq(Date.new(2026, 8, 1))
  end

  it "keeps the duration the service advertises" do
    expect(adapter.fetch(window).first.duration_minutes).to eq(59)
  end

  it "identifies a court by Reservio's stable id, not by its printed name" do
    first = adapter.fetch(window).first

    expect(first.court_ref).to eq("2cb9d25d-f436-4f3f-b2a4-eefdc1ffb62e")
    expect(first.court_label).to eq("Court#1")
  end

  it "carries the club's configured price and booking link" do
    first = adapter.fetch(window).first

    expect(first.price).to eq("50 GEL")
    expect(first.deeplink).to eq("https://padel-club2.reservio.com/")
  end

  it "stamps every slot with the club it came from" do
    expect(adapter.fetch(window).map(&:club_slug).uniq).to eq(["padel-club-2"])
  end

  it "asks only for the window it was given" do
    adapter.fetch(window)
    slots_request = http.requests.find { _1[:url].include?("booking-slots") }

    expect(slots_request[:params]).to include(
      "filter[from]" => "2026-08-01",
      "filter[to]" => "2026-08-07",
      "filter[serviceId]" => "1b9d8011-d73e-4810-bba8-4098b7ad536b"
    )
  end

  describe "pagination" do
    def page(records:, total:, next_url: nil, shift: 0)
      body = JSON.parse(File.read("spec/fixtures/reservio_booking_slots.json"))
      data = body["data"].first(records).each_with_index.map do |record, i|
        # Distinct start times so the page really does carry distinct slots.
        record.merge("attributes" => record["attributes"].merge(
          "start" => "2026-08-01T#{10 + shift + i}:00:00+04:00",
          "end" => "2026-08-01T#{10 + shift + i}:59:00+04:00"
        ))
      end
      body.merge("data" => data, "meta" => { "total" => total }, "links" => { "next" => next_url })
    end

    describe "when the service genuinely pages" do
      let(:http) do
        FakeHttp.new(pages: [
          page(records: 3, total: 6, next_url: "https://api.reservio.com/v2/next-page"),
          page(records: 3, total: 6, shift: 3)
        ])
      end

      it "keeps following next links until it holds the whole result set" do
        expect(adapter.fetch(window).size).to eq(6)
      end

      it "follows the link verbatim rather than rebuilding the query" do
        adapter.fetch(window)

        expect(http.requests.map { _1[:url] }).to include("https://api.reservio.com/v2/next-page")
      end
    end

    describe "when the service hands back everything and still offers a next link" do
      # Reservio really does this: page[limit] and page[offset] are ignored, the
      # full set comes back, and `links.next` is populated anyway. Following it
      # re-downloads the same slots and doubles the snapshot.
      let(:http) do
        FakeHttp.new(pages: [
          page(records: 6, total: 6, next_url: "https://api.reservio.com/v2/next-page"),
          page(records: 6, total: 6)
        ])
      end

      it "stops once it already holds every record the service counted" do
        expect(adapter.fetch(window).size).to eq(6)
      end

      it "does not spend a second request on the bogus link" do
        adapter.fetch(window)

        expect(http.requests.count { _1[:url].include?("booking-slots") || _1[:url].include?("next-page") }).to eq(1)
      end
    end

    it "never lets the same slot into a snapshot twice" do
      duplicated = JSON.parse(File.read("spec/fixtures/reservio_booking_slots.json"))
      duplicated["data"] = duplicated["data"].first(2) + duplicated["data"].first(2)
      duplicated["meta"] = { "total" => 4 }
      http = FakeHttp.new(pages: [duplicated])

      slots = described_class.new(club, http:).fetch(window)

      expect(slots.size).to eq(2)
      expect(slots.map(&:key).uniq.size).to eq(2)
    end
  end

  describe "when a court appears that the resources endpoint does not know" do
    let(:http) do
      FakeHttp.new(pages: [{
        "data" => [{
          "type" => "timeSlot",
          "attributes" => { "start" => "2026-08-01T19:00:00+04:00", "end" => "2026-08-01T20:00:00+04:00" },
          "relationships" => { "resource" => { "data" => { "id" => "brand-new-court" } } }
        }],
        "links" => { "next" => nil }
      }])
    end

    it "still reports the slot, falling back to the raw id for a label" do
      slot = adapter.fetch(window).first

      expect(slot.court_ref).to eq("brand-new-court")
      expect(slot.court_label).to eq("brand-new-court")
    end
  end
end
