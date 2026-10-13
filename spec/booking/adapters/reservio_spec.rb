require "json"

# Answers from recorded copies of the real Reservio responses, so the parsing
# stays pinned to what the service actually sends.
class FakeHttp
  attr_reader :requests

  # `by_service` answers each booking-slots request from a recording keyed by
  # the service it asked for — the shape of a business that sells every court
  # as its own service.
  def initialize(pages: nil, resources: "reservio_resources", by_service: nil)
    @requests = []
    @pages = pages
    @resources = resources
    @by_service = by_service.is_a?(String) ? fixture(by_service) : by_service
  end

  def get_json(url, params = {})
    @requests << { url:, params: }
    return fixture(@resources) if url.include?("/resources")
    return @pages.shift if @pages
    return @by_service.fetch(params["filter[serviceId]"]) if @by_service

    fixture("reservio_booking_slots")
  end

  def fixture(name) = JSON.parse(File.read("spec/fixtures/#{name}.json"))
end

RSpec.describe Booking::Adapters::Reservio do
  subject(:adapter) { described_class.new(club, http:) }

  let(:http) { FakeHttp.new }
  # Recorded from Padel Club 2 before it was dropped as a duplicate of
  # GymBreeze Ninoshvili. Kept: it is the other shape a business takes — one
  # service over four resources — and it still spells the single `service_id`.
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

  describe "when the source does not answer with a list" do
    it "says the source is unavailable rather than reporting an empty club" do
      http = FakeHttp.new(pages: [{ "errors" => [{ "status" => "500", "title" => "Something happened" }] }])

      expect { described_class.new(club, http:).fetch(window) }
        .to raise_error(Booking::Adapters::SourceUnavailable, /no data/)
    end

    it "says the same of a court list that is not one" do
      # Any bare array will do: a JSON:API document is always an object.
      http = FakeHttp.new(resources: "kustba_available_slots")

      expect { described_class.new(club, http:).fetch(window) }
        .to raise_error(Booking::Adapters::SourceUnavailable, %r{/resources: no data})
    end

    it "takes an empty list at its word: every court can sell out" do
      http = FakeHttp.new(pages: [{ "data" => [], "meta" => { "total" => 0 } }])

      expect(described_class.new(club, http:).fetch(window)).to eq([])
    end
  end

  it "drops a start that is not on the hour, which no Cell could hold" do
    body = JSON.parse(File.read("spec/fixtures/reservio_booking_slots.json"))
    body["data"].first["attributes"].merge!("start" => "2026-08-01T08:30:00+04:00", "end" => "2026-08-01T09:29:00+04:00")
    http = FakeHttp.new(pages: [body])

    expect(described_class.new(club, http:).fetch(window).size).to eq(5)
  end

  # Padel Port Batumi sells each of its six courts as its own service, four at
  # the original site and two at New Park, all under one business. Recorded
  # for 15 October 2026, one booking-slots answer per service.
  describe "a business that sells every court as its own service" do
    let(:http) { FakeHttp.new(resources: "reservio_padel_port_resources", by_service: "reservio_padel_port_booking_slots") }
    let(:window) { Date.new(2026, 10, 15)..Date.new(2026, 10, 21) }
    let(:club) do
      Booking::Club.new(
        slug: "padel-port",
        name: "Padel Port",
        adapter: "reservio",
        settings: {
          "business_id" => "1e32bd0a-0d5c-4e30-9788-ea488e713c4d",
          "service_ids" => PADEL_PORT_SERVICES,
          "booking_url" => "https://padel-port-batumi2.reservio.com/",
          "price" => "80 GEL"
        }
      )
    end
    let(:new_park) do
      club.with(slug: "padel-port-new-park", name: "Padel Port New Park",
                settings: club.settings.merge("service_ids" => NEW_PARK_SERVICES))
    end

    PADEL_PORT_SERVICES = %w[
      6dcc4d1f-c73b-4a35-ad3a-3ede2cb321a6
      c36479d3-8201-4d80-9822-e9c08014468b
      303f3adf-8a99-4c1f-89fe-f9a9b56a620b
      1dfea382-0fe9-42de-a3d0-36d82629b071
    ].freeze
    NEW_PARK_SERVICES = %w[24481fd5-3320-4133-b762-03f13f1b200e 09922dde-639d-4bdc-8b53-73077a57cca2].freeze

    it "reads every service it was given, and only those" do
      # 10 + 9 + 10 + 11 free on Padel Court 1–4 that day.
      expect(adapter.fetch(window).size).to eq(40)
    end

    it "asks once per service, because the filter takes a single id" do
      adapter.fetch(window)
      asked = http.requests.filter_map { _1[:params]["filter[serviceId]"] }

      expect(asked).to eq(PADEL_PORT_SERVICES)
    end

    it "names each court as the club does" do
      expect(adapter.fetch(window).map(&:court_label).uniq).to contain_exactly("Court 1", "Court 2", "Court 3", "Court 4")
    end

    it "keeps the court's stable id as its ref" do
      first = adapter.fetch(window).find { _1.court_label == "Court 1" }

      expect(first.court_ref).to eq("929c2389-5a21-444f-bb78-bdcaef2dbf3c")
    end

    it "splits one business into two clubs by the services each is given" do
      slots = described_class.new(new_park, http:).fetch(window)

      # 12 on Park Court 1, 11 on Park Court 2.
      expect(slots.size).to eq(23)
      expect(slots.map(&:court_label).uniq).to contain_exactly("Park Court 1", "Park Court 2")
      expect(slots.map(&:club_slug).uniq).to eq(["padel-port-new-park"])
    end

    it "takes the hours after midnight at their word rather than rolling them over" do
      # Listed last, after 23:00, but stamped with the date they fall on.
      late = adapter.fetch(window).select { _1.court_label == "Court 1" }.min_by(&:starts_at)

      expect(late.starts_at).to eq(Time.utc(2026, 10, 14, 20, 0))
      expect(late.local_starts_at.hour).to eq(0)
      expect(late.local_date).to eq(Date.new(2026, 10, 15))
    end

    it "is court-level: every court that is free at an hour is its own slot" do
      at_fifteen = adapter.fetch(window).select { _1.local_starts_at.hour == 15 }

      expect(at_fifteen.map(&:court_ref).uniq.size).to eq(4)
    end

    it "asks no further than the club's own window" do
      described_class.new(club.with(settings: club.settings.merge("max_days" => 3)), http:).fetch(window)
      asked = http.requests.filter_map { _1[:params]["filter[to]"] }.uniq

      expect(asked).to eq(["2026-10-17"])
    end

    it "still accepts one service under the old `service_id` spelling" do
      single = club.with(settings: club.settings.except("service_ids").merge("service_id" => PADEL_PORT_SERVICES.first))

      expect(described_class.new(single, http:).fetch(window).size).to eq(10)
    end

    it "refuses a club with no services, which would read as sold out forever" do
      empty = club.with(settings: club.settings.merge("service_ids" => []))

      expect { described_class.new(empty, http:) }.to raise_error(Booking::Error, /service_ids is empty/)
    end
  end

  # Grand Padel Batumi sells each of its two courts as three price bands, and
  # every band is its own service over its own resource. Recorded for 20
  # October 2026, one booking-slots answer per service.
  describe "a business that sells every court as several price bands" do
    let(:http) { FakeHttp.new(resources: "reservio_grand_padel_resources", by_service: "reservio_grand_padel_booking_slots") }
    let(:window) { Date.new(2026, 10, 20)..Date.new(2026, 10, 26) }
    let(:club) do
      Booking::Club.new(
        slug: "grand-padel-batumi",
        name: "Grand Padel",
        adapter: "reservio",
        settings: {
          "business_id" => "aac3b1f5-7e80-4052-bd09-adc7396cfbec",
          "service_ids" => GRAND_PADEL_BANDS.keys,
          "booking_url" => "https://grandpadelbatumi.reservio.com/",
          "price" => "50–80 GEL",
          "courts" => 2,
          "court_aliases" => GRAND_PADEL_COURTS
        }
      )
    end

    # Service => the resource it books, band by band.
    GRAND_PADEL_BANDS = {
      "adcd4ab2-597c-4173-8090-75595b5ef390" => "408fddbc-1ace-45f0-8e9b-b3b7c5e8b3c3",
      "8f38cc70-a224-40e6-81d6-b6c7e32d8344" => "242d0df6-c5b8-4f99-b8d3-5b7aa3ba4891",
      "77bc9810-6d74-406a-9568-544d0f381924" => "687ce25c-523a-462a-bb39-9446689b78a1",
      "972672c5-94ba-4d1a-bdfd-f2839a0ceeb7" => "78060f65-7b46-4caf-a15d-f8a9b150f126",
      "896c724c-6d75-405c-80ae-87e73e58eec4" => "61acffdf-fd07-4a7f-9596-a5721267c1b6",
      "9813ae70-d196-4426-8b04-480916a8d981" => "cd72f9a6-f3ba-4099-a8a3-5aa579197335"
    }.freeze
    GRAND_PADEL_COURTS = GRAND_PADEL_BANDS.values.each_with_index.to_h { |resource, i| [resource, i < 3 ? "Court A" : "Court B"] }.freeze

    it "reads all three bands of both courts" do
      # Court A: 3 + 4 + 8, Court B: 1 + 4 + 7 free that day.
      expect(adapter.fetch(window).size).to eq(27)
    end

    it "comes out as the two courts the club has, not six bands" do
      slots = adapter.fetch(window)

      expect(slots.map(&:court_ref).uniq).to contain_exactly("Court A", "Court B")
      expect(slots.map(&:court_label).uniq).to contain_exactly("Court A", "Court B")
    end

    it "joins the bands into one court's day" do
      hours = adapter.fetch(window).select { _1.court_ref == "Court A" }.map { _1.local_starts_at.hour }.sort

      expect(hours).to eq([0, 1, 8, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22])
    end

    it "makes one slot per court-hour even if two bands offer the same hour" do
      bands = FakeHttp.new.fixture("reservio_grand_padel_booking_slots")
      morning, midday = GRAND_PADEL_BANDS.keys.first(2)
      # The midday band reaching back an hour into the morning band's 12:00.
      overlap = bands[morning]["data"].last.merge("relationships" => bands[midday]["data"].first["relationships"])
      bands[midday] = bands[midday].merge("data" => [overlap] + bands[midday]["data"], "meta" => { "total" => 5 })
      http = FakeHttp.new(resources: "reservio_grand_padel_resources", by_service: bands)

      at_noon = described_class.new(club, http:).fetch(window).select { _1.court_ref == "Court A" && _1.local_starts_at.hour == 12 }

      expect(at_noon.size).to eq(1)
    end

    it "still labels a band the config does not mention by Reservio's name for it" do
      unaliased = club.with(settings: club.settings.merge("court_aliases" => {}))

      expect(described_class.new(unaliased, http:).fetch(window).map(&:court_label)).to include("Court A- 80 Gel")
    end
  end
end
