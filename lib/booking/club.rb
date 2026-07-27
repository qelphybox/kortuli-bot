require "json"

module Booking
  # Carried per club because the concept asks for a per-club interval, but not
  # yet read by anything: one global interval drives a sequential pass over
  # every club. Four minutes is the polite end of the 3–5 the concept suggests.
  DEFAULT_POLL_INTERVAL_SECONDS = 240

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

    def enabled? = !!enabled

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
