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
    # The bot additionally needs somewhere to point its menu button and its
    # greeting. Without a URL it has nothing to say: the app is the only place a
    # Watch is made, so a bot that cannot open it is not worth starting.
    # OWNER_TELEGRAM_ID is where user-written feedback gets forwarded; a bot
    # that silently drops it is worse than one that refuses to start (see
    # ADR-0002). BOT_USERNAME is checked at boot too so both the web deeplink
    # and the bot boot fail together on a misconfigured handle.
    REQUIRED_FOR_BOT = (REQUIRED + %w[APP_URL OWNER_TELEGRAM_ID BOT_USERNAME]).freeze
    # The web additionally signs its own session cookies. Deliberately its own
    # secret rather than something derived from the token, so it can be rotated
    # — logging everyone out — without touching the bot. It also builds the
    # feedback pill's deeplink and so needs the bot's public @handle.
    REQUIRED_FOR_WEB = (REQUIRED + %w[SESSION_SECRET BOT_USERNAME]).freeze

    def missing_environment(required = REQUIRED) = required.reject { ENV[_1] }

    def session_secret = ENV.fetch("SESSION_SECRET")

    def web_port = Integer(ENV.fetch("PORT", "8080"))

    def database_url = ENV.fetch("DATABASE_URL", "sqlite://data/booking.db")

    def telegram_token = ENV.fetch("TELEGRAM_TOKEN")

    # The Telegram user_id that receives forwarded feedback. Fails loud on boot
    # rather than treating an unset value as "nobody home"; see ADR-0002.
    def owner_id = Integer(ENV.fetch("OWNER_TELEGRAM_ID"))

    # The bot's public @handle (without the @), used to build the mini app's
    # "Contact" deeplink into the bot chat.
    def bot_username = ENV.fetch("BOT_USERNAME")

    # Where the mini app is served — the same host the proxy holds a
    # certificate for. Telegram opens `web_app` buttons over HTTPS only.
    def app_url = ENV.fetch("APP_URL")

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
