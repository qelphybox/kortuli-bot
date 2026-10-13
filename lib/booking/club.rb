require "json"

module Booking
  # Carried per club because the concept asks for a per-club interval, but not
  # yet read by anything: one global interval drives a sequential pass over
  # every club. Four minutes is the polite end of the 3–5 the concept suggests.
  DEFAULT_POLL_INTERVAL_SECONDS = 240

  # Where every club was before there was a second city, and so what a club
  # that does not say is taken to be in.
  DEFAULT_CITY = "Tbilisi"

  # A club as configured, plus the one piece of state the poller keeps about it.
  Club = Data.define(:slug, :name, :adapter, :settings, :poll_interval_seconds, :enabled, :observed_through) do
    def initialize(slug:, name:, adapter:, settings: {}, poll_interval_seconds: DEFAULT_POLL_INTERVAL_SECONDS, enabled: true, observed_through: nil)
      settings = JSON.parse(settings) if settings.is_a?(String)
      super(
        slug: slug.to_s,
        name: name.to_s,
        adapter: adapter.to_s,
        settings: settings.transform_keys(&:to_s),
        poll_interval_seconds:,
        enabled:,
        observed_through:
      )
    end

    # The cities these clubs are in, each once: the default first, because
    # it is where most people are and what they saw before there was a
    # choice, then the rest by name so the order does not move as clubs come
    # and go.
    def self.cities(clubs) = clubs.map(&:city).uniq.sort_by { [_1 == DEFAULT_CITY ? 0 : 1, _1] }

    def enabled? = !!enabled

    # The City a club is in — an attribute of the club, not of anything that
    # names it: a Watch names clubs, so it is in whichever cities they are.
    # See ADR-0003.
    def city
      named = settings["city"].to_s.strip
      named.empty? ? DEFAULT_CITY : named
    end

    def court_aliases = settings.fetch("court_aliases", {})

    def opening_hours = OpeningHours.parse(settings["opening_hours"])

    # Set only for a club whose source names its courts. Its absence is what
    # makes a club hour-level, so there is nothing to default it to.
    def court_count = settings["courts"]

    def court_level? = !court_count.nil?

    # Adapters ask the club, rather than reading `court_aliases` and applying it
    # themselves — otherwise every new adapter has to remember §8a exists.
    def canonical_court(ref) = CourtName.canonical(ref, aliases: court_aliases)
  end
end
