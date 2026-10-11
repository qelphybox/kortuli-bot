module Booking
  # One pass over every enabled club: fetch, diff, persist, match, notify.
  #
  # Clubs are polled one after another rather than in parallel — with a handful
  # of clubs there is nothing to gain, and being gentle with somebody else's
  # shared hosting matters more than finishing the tick a second sooner.
  class Poller
    def initialize(repos:, notifier:, http:, horizon_days: Config.horizon_days,
                   adapter_factory: Adapters.method(:build), differ: Differ.new,
                   matcher: Matcher.new, logger: nil)
      @repos = repos
      @notifier = notifier
      @http = http
      @horizon_days = horizon_days
      @adapter_factory = adapter_factory
      @differ = differ
      @matcher = matcher
      @logger = logger || Booking.default_logger
    end

    def tick(now: Clock.now)
      @repos.clubs.enabled.each { poll(_1, now:) }
    end

    private

    def poll(club, now:)
      window = window_for(now)
      fetched = @adapter_factory.call(club, http: @http).fetch(window)
      previous = @repos.slots.snapshot(club.slug)
      result = @differ.diff(previous:, current: fetched, known_through: club.observed_through)

      return report(club, :suspect, "suspect response (#{result.reason}) — snapshot kept", now:) unless result.ok?

      commit(club, fetched, window, result)
      sent = notify(result.became_available, now:)
      report(club, :ok, "#{fetched.size} free, +#{result.became_available.size} freed, " \
                        "-#{result.became_taken.size} taken, #{sent} sent#{held_back(result)}", now:)
    rescue Adapters::SourceUnavailable => e
      # The club's site is the least reliable part of the system, so an
      # unreachable one is an ordinary event: skip it and keep the other clubs.
      report(club, :failed, "failed — #{e.message}", now:)
    end

    # Said twice on purpose: once to the log, as a line, and once to the
    # club's row, where the dashboard reads it without parsing the line.
    def report(club, outcome, summary, now:)
      log("poll #{club.slug}: #{summary}")
      @repos.polls.record(club.slug, outcome:, summary:, at: now)
    end

    def commit(club, fetched, window, result)
      @repos.slots.replace(club.slug, fetched)
      # Only a poll we believed advances the horizon. Moving it after a suspect
      # response would mark days as "seen" that we never really read.
      @repos.clubs.observed_through!(club.slug, window.last)
      @repos.events.record(club_slug: club.slug, kind: :became_available, slots: result.became_available)
      @repos.events.record(club_slug: club.slug, kind: :became_taken, slots: result.became_taken)
    end

    def notify(freed, now:)
      return 0 if freed.empty?

      @notifier.deliver(@matcher.match(events: freed, watches: @repos.watches.active, now:))
    end

    # Worth saying out loud: silence caused by a guard looks exactly like
    # silence caused by nothing happening.
    def held_back(result)
      return "" if result.suppressed_days.empty?

      " (held back #{result.suppressed_days.join(", ")} — arrived as a whole day)"
    end

    def window_for(now)
      today = Clock.local_date(now)
      today..(today + @horizon_days - 1)
    end

    def log(line) = @logger.call(line)
  end
end
