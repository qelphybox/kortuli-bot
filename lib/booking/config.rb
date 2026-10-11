require "rufus-scheduler"

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
    # The web signs its session cookies with a key derived from the token (see
    # Web::Session.for_token), so it needs nothing more for that. It does build
    # the feedback pill's deeplink and so needs the bot's public @handle, and
    # it opens the dashboard to the owner alone, so it needs to know who that is.
    REQUIRED_FOR_WEB = (REQUIRED + %w[BOT_USERNAME OWNER_TELEGRAM_ID]).freeze

    # Empty counts as missing: `KEY=` in a .env or an unset variable expanded by
    # Kamal both arrive as "", and a blank token boots a process that can only
    # fail later and further from the cause.
    def missing_environment(required = REQUIRED) = required.select { ENV[_1].to_s.empty? }

    def web_port = Integer(ENV.fetch("PORT", "8080"))

    def database_url = ENV.fetch("DATABASE_URL", "sqlite://data/booking.db")

    def telegram_token = ENV.fetch("TELEGRAM_TOKEN")

    # Where each process keeps a searchable copy of its log and the file it
    # touches to say it is alive. On the data mount in production, because
    # that is the one directory all three containers share.
    def log_dir = ENV.fetch("LOG_DIR", "data/log")

    # The Telegram user_id that receives forwarded feedback, and the one
    # person the web shows its dashboard to. Fails loud on boot rather than
    # treating an unset value as "nobody home"; see ADR-0002.
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

    # The longest a healthy gap between two ticks can be, in seconds — what the
    # dashboard measures a club's last Poll against.
    def poll_every_seconds = Rufus::Scheduler.parse_duration(poll_interval).to_i + poll_jitter

    def clubs_file = ENV.fetch("CLUBS_FILE", "config/clubs.yml")

    # Written by `rake sapadelo:import`; read by the web alone.
    def club_profiles_file = ENV.fetch("CLUB_PROFILES_FILE", "config/club_profiles.yml")

    def http_timeout = Integer(ENV.fetch("HTTP_TIMEOUT", "15"))

    # Padel Academy shows its schedule only to a signed-in member, so polling
    # it needs an account. Optional: without one that club fails its tick and
    # says why, and every other club carries on.
    def padel_academy_credentials
      email = ENV["PADEL_ACADEMY_EMAIL"].to_s
      password = ENV["PADEL_ACADEMY_PASSWORD"].to_s
      { email:, password: } unless email.empty? || password.empty?
    end

    # Clubs run on shared hosting, not Amazon. Announcing who we are and how to
    # complain is cheaper than being banned by IP in week two.
    def user_agent
      ENV.fetch("USER_AGENT", "padel-slot-watcher/0.1 (personal use; contact: #{ENV.fetch("CONTACT_EMAIL", "unset")})")
    end
  end
end
