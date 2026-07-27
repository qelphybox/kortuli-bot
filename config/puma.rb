# One worker, a handful of threads. The load is one person tapping around a
# grid, and the store is a SQLite file on the same disk — forking workers would
# multiply connections to it for no gain.
threads 1, Integer(ENV.fetch("WEB_THREADS", "5"))
port Integer(ENV.fetch("PORT", "8080"))
# Load-bearing beyond Puma itself: Puma exports this as RACK_ENV, which is what
# Sinatra reads to decide it is in production — and that is what puts `Secure`
# on the session cookie. Serving this app through anything else would need to
# set RACK_ENV itself.
environment ENV.fetch("RACK_ENV", "production")

# Docker collects stdout; a pidfile would only be something to leave behind.
quiet false
