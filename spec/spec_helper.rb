require "booking"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

# Build a Slot with sensible defaults; override only what the example cares about.
def slot(court: "Court 1", at: "2026-08-01 19:00", club: "reservio-demo", price: nil)
  Booking::Slot.new(
    club_slug: club,
    court_ref: court,
    court_label: court,
    starts_at: Booking::Clock.local_to_utc(at),
    ends_at: Booking::Clock.local_to_utc(at) + 3600,
    price: price,
    deeplink: "https://example.test/book"
  )
end
