module Booking
  # Environment is read here and nowhere else. No product-name prefixes on the
  # keys: the project is renameable without a sweep through the deployment.
  module Config
    module_function

    # Without these the process cannot start, so bin/bot asks before booting
    # rather than letting an ENV.fetch blow up somewhere deeper.
    REQUIRED = %w[TELEGRAM_TOKEN].freeze

    def missing_environment = REQUIRED.reject { ENV[_1] }

    def database_url = ENV.fetch("DATABASE_URL", "sqlite://data/booking.db")

    def telegram_token = ENV.fetch("TELEGRAM_TOKEN")

    # Only this user may talk to the bot while it is a single-user experiment.
    def owner_id = ENV["OWNER_TELEGRAM_ID"]&.to_i

    def horizon_days = Integer(ENV.fetch("HORIZON_DAYS", "7"))

    def poll_interval = ENV.fetch("POLL_INTERVAL", "4m")

    # Seconds of random delay before each tick, so polls do not land on the same
    # second of every interval.
    def poll_jitter = Integer(ENV.fetch("POLL_JITTER", "30"))

    def clubs_file = ENV.fetch("CLUBS_FILE", "config/clubs.yml")

    def http_timeout = Integer(ENV.fetch("HTTP_TIMEOUT", "15"))

    # Clubs run on shared hosting, not Amazon. Announcing who we are and how to
    # complain is cheaper than being banned by IP in week two.
    def user_agent
      ENV.fetch("USER_AGENT", "padel-slot-watcher/0.1 (personal use; contact: #{ENV.fetch("CONTACT_EMAIL", "unset")})")
    end
  end
end
