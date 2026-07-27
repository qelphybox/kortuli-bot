# Padel slot watcher

A Telegram bot that watches Tbilisi padel clubs for cancellations and messages you
when a court in your window frees up.

Evening slots go a day or two ahead and only come back when somebody cancels.
There is no single place that shows the whole grid, so the only way to catch a
cancellation today is to keep refreshing somebody else's booking site. This does
that for you.

It does **not** book and does **not** pay — you get a message with a link, and
take it from there.

See [docs/INIT_CONCEPT.md](docs/INIT_CONCEPT.md) for the product thinking behind it.

## How it fits together

Five loosely coupled parts, in the order data moves through them:

| Part | File | Job |
|---|---|---|
| **Adapter** | [lib/booking/adapters/](lib/booking/adapters/) | One per club. `fetch(date_range) -> [Slot]`, returning only what is *free*. |
| **Differ** | [lib/booking/differ.rb](lib/booking/differ.rb) | Last snapshot vs this one → `became_available` / `became_taken`. |
| **Matcher** | [lib/booking/matcher.rb](lib/booking/matcher.rb) | Freed slots × active watches → who should hear about it. |
| **Notifier** | [lib/booking/notifier.rb](lib/booking/notifier.rb) | Sends each slot to each watcher exactly once. |
| **Poller** | [lib/booking/poller.rb](lib/booking/poller.rb) | Drives the four above, one club after another. |

The Telegram layer is thin on purpose: [`Handlers`](lib/booking/telegram/handlers.rb)
returns *replies* rather than calling the API, and the step-by-step watch builder
is a pure state machine in [`Wizard`](lib/booking/telegram/wizard.rb). Both are
fully testable without a token or a network. The mini app under
[lib/booking/web/](lib/booking/web/) follows the same rule and is driven end to
end by `Rack::Test`.

Everything runs as **three processes** built from one image, sharing one SQLite
file and nothing else:

| Process | Entrypoint | Job |
|---|---|---|
| **bot** | [bin/bot](bin/bot) | Long-polls Telegram and answers commands. |
| **poller** | [bin/poller](bin/poller) | Owns club config, walks every club on a schedule, sends notifications. |
| **web** | [bin/web](bin/web) | Serves the Telegram Mini App over Puma. |

Splitting them means deploying a screen no longer interrupts polling.
[ADR-0001](docs/adr/0001-poller-is-a-process-not-a-queue.md) records why the
poll loop stayed a scheduler rather than becoming job-queue work.

Two of the three write to the database — the poller writes slots and club
state, the web writes watches. WAL and a busy timeout make that safe across
processes as well as threads, because the containers share a kernel and a
filesystem. It is the one genuinely new operational risk in this shape.

## Getting it running

```bash
bundle install
cp .env.example .env   # then fill in TELEGRAM_TOKEN and OWNER_TELEGRAM_ID
bundle exec rake seed
bundle exec bin/bot      # and, in their own shells:
bundle exec bin/poller
bundle exec bin/web
```

Only `bin/web` needs `SESSION_SECRET`; the other two ignore it. Locally the mini
app comes up on `http://localhost:8080`, where it will redirect you to `/start`
and then tell you to open it from Telegram — the signed payload it needs only
exists inside a Telegram client.

Poll once in the foreground, without starting the bot — the quickest way to see
whether an adapter still works:

```bash
bundle exec rake poll
```

Adding another Reservio club — this prints the ids to paste into
[config/clubs.yml](config/clubs.yml):

```bash
bundle exec rake "discover:reservio[padel-club2]"
```

## Using it

The **mini app** shows the week: one row per club, one column per hour, one
page per date. A free hour links out to that club's booking page; an hour
outside a club's opening hours is left blank rather than drawn as taken. Clubs
whose source names the court say how many of them are free (`2/4`); the rest
can only say that something is (`✓`).

Its second screen is **Watches**: everything you have asked to be told about,
with pause, resume and delete. A standing watch names the weekdays it keeps
coming back on; a dated one names its single day and says `Dated`. Pausing
stops a watch matching without losing it, and a dated watch drops off the list
once its hour has gone by — nothing reaps it, it simply stops mattering.
Creating a watch is still the chat wizard's job for now.

In the chat, for now:

- `/watch` — build a watch: clubs → days → hours
- `/list` — your watches, with pause and delete buttons
- `/help` — what the bot does

## Deploying

Docker on a VPS, driven by [Kamal](https://kamal-deploy.org). The config is
[config/deploy.yml](config/deploy.yml); the image goes to GHCR.

Put the real values in `.kamal/secrets` (gitignored — see
[.kamal/secrets.example](.kamal/secrets.example)). `KAMAL_REGISTRY_PASSWORD` is
a GitHub token with **`write:packages`**; the one `gh auth` holds does not have
that scope.

First time on a fresh server:

```bash
bundle exec kamal setup
```

After that, every deploy is:

```bash
bundle exec kamal deploy
```

```bash
bundle exec kamal app logs -f
```

Three things about this deploy are worth knowing, because all three are
load-bearing:

**`bot` is the primary role, not `web`.** Kamal insists on knowing which role
gates a deploy and would otherwise hunt for one called `web`. Of the three only
the mini app has a port; `bot` and `poller` serve nothing and say so with
`proxy: false`.

**TLS is `kamal-proxy`'s job.** It obtains and renews the certificate over
HTTP-01, so the hostname must already resolve to the server before the first
deploy — otherwise the challenge cannot complete and the deploy stalls on
certificate issuance. There is no certbot and no renewal cron to forget about.

**A deploy briefly runs two containers.** Kamal starts the replacement, waits
for it to look healthy, and only then stops the old one — but Telegram allows a
single long-poller per token and answers the second with `409`. So the new
process waits the conflict out instead of exiting; if it exited, the old one
would never be stopped and the deploy would block on a container that could
never become healthy. `Telegram::Runner` is where that lives. Expect the bot to
be unresponsive for roughly ten seconds mid-deploy.

Two steps happen outside the repository and cannot be automated from it: point
a DNS A record at the server, and register the mini app's URL once with
`@BotFather`.

The database is a bind mount at `/srv/kortuli-bot/data` on the host, created
with the right ownership by [.kamal/hooks/pre-deploy](.kamal/hooks/pre-deploy).
Back it up by copying `booking.db` off that path.

Poll once against a live server, which is the fastest way to tell a broken
adapter from a quiet week:

```bash
bundle exec kamal app exec 'bundle exec rake poll'
```

The log is the health check. Every tick prints one line per club:

```
poll padel-club-2: 388 free, +2 freed, -1 taken, 1 sent
poll padel-club-2: failed — timeout
poll padel-club-2: suspect response (empty_response) — snapshot kept
poll padel-club-2: 388 free, +0 freed, -0 taken, 0 sent (held back 2026-08-03 — arrived as a whole day)
```

If that line stops appearing, or `free` sits at zero for hours, the adapter has
broken — which looks exactly like "no cancellations happened" from the outside.
Check it before concluding nobody wants the product.

## The parts that will bite

Four things break a naive version of this, all handled and all covered by tests:

**A new day opening looks like a hundred cancellations.** Clubs extend the
booking window overnight. The differ only reports a freed slot for a date it has
already polled — tracked as `observed_through` on the club, *not* as "dates in
the last snapshot", because a sold-out day leaves no trace in a snapshot that
holds only free slots.

**…and the horizon alone does not catch all of it.** A club whose own window is
shorter than ours opens a day *inside* the polled horizon, and a source
recovering from a bad answer dumps a whole grid at once. Both look identical
from the differ: one date gaining a day's worth of slots in a single tick. More
than `MAX_FREED_PER_DAY` on one date is therefore held back, and the log says
which date and why. Real cancellations arrive a few at a time and pass through.

**A 500 looks like the whole club emptying out.** An empty response after a
healthy one is treated as a bad poll: no events, and the previous snapshot is
kept. Overwriting it would make the next successful poll look like mass
cancellation.

**Sites lie about pagination.** Reservio ignores `page[limit]`/`page[offset]`,
returns the entire result set, and still advertises a `next` link. Following it
downloads everything twice. The adapter trusts `meta.total` and de-duplicates by
slot key.

**A club's day does not end at midnight.** Kus Tba Padel books until 02:00 and
lists 23:00, 00:00 and 01:00 under the *previous* date. Taken literally, a
Tuesday 01:00 slot answers a Monday watch. The adapter rolls the day over when
the hour goes backwards, rather than hardcoding an opening time. GymBreeze
closes at 01:00 and has the same shape, but dates those hours correctly itself —
so check before porting the workaround; applying it there would shift every
late slot a day forward.

**A booking window is not the same as an answer.** Both Kus Tba and GymBreeze
answer for any date they are asked about, including ones past the window their
own widget offers — and everything out there reads free, because nobody can
reserve it yet. Those slots would never transition, so both adapters clamp the
range to a `max_days` from settings rather than trusting `HORIZON_DAYS`.

**Timezones.** Everything is UTC inside. Local time (Asia/Tbilisi) exists at
exactly two edges: adapters parsing a club's clock, and messages printing one.

## Known limits

This is an MVP, deliberately:

- **Three sources, four clubs.** Padel Club 2 (Reservio), Kus Tba Padel
  (`turtle-booking`) and GymBreeze, whose two locations are configured as two
  clubs because they sit at opposite ends of town. The concept also named
  `tbilisipadel.com`, but it runs BookingPress, which needs its own adapter and
  its own reconnaissance — neither is done. Everything above the adapter is
  club-agnostic, so that is a new file in
  [lib/booking/adapters/](lib/booking/adapters/) and a line in `REGISTRY`.
- **Kus Tba and GymBreeze are watched by the hour, not by the court.** Both
  report whether *some* court is free that hour, so a notification says "a
  court" rather than "Court 3", and a cancellation raises an event only when it
  reopens an hour that was sold out. For Kus Tba that is a choice: its API will
  name the court, but only one hour per request — 110 per poll against 7, and
  the measurements are at the top of
  [lib/booking/adapters/kustba.rb](lib/booking/adapters/kustba.rb). For
  GymBreeze it is not: passing `court_id` is answered with "no longer supported,
  use location_id".
- **GymBreeze prices are printed as a range.** They move with the hour and the
  weekday (40 GEL midday, 60 either side at Ninoshvili). The real rates are
  published at `/facilities/locations/<id>/`, so computing one per slot is a
  second request away if the range ever proves too vague.
- **One language.** English, hardcoded. Strings are all in
  [`Messages`](lib/booking/messages.rb) so adding a second is a new file, not an
  excavation.
- **No rate limit per user.** The unique index on `notifications` stops repeats
  about the *same* slot; nothing caps the count of *different* slots per hour.
- **No alerting.** A broken adapter shows up in the log, not in your inbox.
- **`poll_interval_seconds` per club is stored but not used.** One global
  interval drives a sequential pass over all clubs — deliberate, so a handful of
  clubs on shared hosting never get hit in parallel.
- **Wizard drafts live in memory.** A restart mid-form means tapping `/watch`
  again.
- **Snapshots are not kept.** Current state plus a transition log, not full
  history — enough for "when do evening slots free up?", not enough to replay an
  arbitrary past moment.
