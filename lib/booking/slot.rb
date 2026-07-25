require "time"

module Booking
  # A bookable hour on a court, as an adapter saw it. Presence of a Slot means
  # "free right now" — adapters return only what is available, so the differ can
  # work by set difference.
  Slot = Data.define(:club_slug, :court_ref, :court_label, :starts_at, :ends_at, :price, :deeplink) do
    def initialize(club_slug:, court_ref:, starts_at:, ends_at:, court_label: nil, price: nil, deeplink: nil)
      super(
        club_slug: club_slug.to_s,
        court_ref: court_ref.to_s,
        court_label: (court_label || court_ref).to_s,
        starts_at: starts_at.getutc,
        ends_at: ends_at.getutc,
        price:,
        deeplink:
      )
    end

    # Synthesised because clubs rarely hand out stable slot ids. Anything that
    # changes this string is treated as a different slot, which is why the court
    # component goes through normalisation first.
    def key = [club_slug, CourtName.normalize(court_ref), starts_at.iso8601].join("|")

    def local_date = Clock.local_date(starts_at)

    def local_starts_at = Clock.to_local(starts_at)

    def duration_minutes = ((ends_at - starts_at) / 60).round
  end
end
