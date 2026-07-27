# Puma's entrypoint. The wiring the app deliberately does not do for itself
# lives here: requiring the library must never demand a token or a secret, or
# the other two processes could not load it.
require_relative "lib/booking/boot"

Booking::Boot.call(Booking::Config::REQUIRED_FOR_WEB)

app = Booking::Web::App
app.set :telegram_token, Booking::Config.telegram_token
app.set :visitor_sessions, Booking::Web::Session.new(secret: Booking::Config.session_secret)
# Read-only from here: the poller owns everything the grid displays.
app.set :repos, Booking::App.repos

Booking.default_logger.call("boot: web on :#{Booking::Config.web_port}")

run app
