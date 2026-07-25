module Booking
  # Most clubs expose no stable court id, only a display name that a manager can
  # retype at any moment. §8a of the concept splits that into two problems, and
  # they are solved in two different places, so they live as two methods here.
  module CourtName
    DECORATION = /[^[:alnum:][:space:]]/.freeze

    # The deliberate half: "Court 1" becomes "Centre Court" and no amount of
    # string tidying will ever join them again. Only a human-written map knows
    # they are one court, so this runs at the adapter — the one place that
    # still has the club, and therefore its config, in hand.
    def self.canonical(raw, aliases: {}) = aliases.fetch(raw.to_s.strip, raw.to_s)

    # The cosmetic half: case, padding and decoration drifting between polls.
    # Runs wherever a slot's identity is needed, club config or not.
    def self.normalize(raw) = raw.to_s.downcase.gsub(DECORATION, " ").split.join(" ")
  end
end
