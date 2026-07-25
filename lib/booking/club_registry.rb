require "yaml"

module Booking
  # Clubs are declared in a file and mirrored into the database on boot, so the
  # source of truth stays in version control rather than in hand-typed rows.
  module ClubRegistry
    def self.sync_from_config!(clubs_repo, path = Config.clubs_file)
      raise Error, "no clubs file at #{path}" unless File.exist?(path)

      entries = YAML.safe_load_file(path) || []
      entries.map do |entry|
        clubs_repo.upsert(
          slug: entry.fetch("slug"),
          name: entry.fetch("name"),
          adapter: entry.fetch("adapter"),
          settings: entry.fetch("settings", {}),
          poll_interval_seconds: entry.fetch("poll_interval_seconds", DEFAULT_POLL_INTERVAL_SECONDS),
          enabled: entry.fetch("enabled", true)
        )
      end
    end
  end
end
