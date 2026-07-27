module Booking
  # Environment is read here and nowhere else. No product-name prefixes on the
  # keys: the project is renameable without a sweep through the deployment.
  module Config
    module_function

    # Without these a process cannot start, so each entrypoint asks before
    # booting rather than letting an ENV.fetch blow up somewhere deeper. All
    # three need the token: the bot to poll, the poll loop to send, and the web
    # to verify the signature Telegram puts on initData.
    REQUIRED = %w[TELEGRAM_TOKEN].freeze
    # The web additionally signs its own session cookies. Deliberately its own
    # secret rather than something derived from the token, so it can be rotated
    # — logging everyone out — without touching the bot.
    REQUIRED_FOR_WEB = (REQUIRED + %w[SESSION_SECRET]).freeze

    def missing_environment(required = REQUIRED) = required.reject { ENV[_1] }

    def session_secret = ENV.fetch("SESSION_SECRET")

    # The hostname Telegram was told to open. Used to narrow Sinatra's host
    # check; unset means "accept anything", which is what the specs want.
    def app_host = ENV["APP_HOST"]

    def web_port = Integer(ENV.fetch("PORT", "8080"))

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
