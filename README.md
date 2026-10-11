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

The Telegram layer is thin on purpose:
[`Handlers`](lib/booking/telegram/handlers.rb) returns a *reply* rather than
calling the API, so the whole conversation is testable without a token or a
network. It is a short file, because the bot no longer builds anything — a
watch is made in the app, and there is exactly one code path that writes one.
The mini app under [lib/booking/web/](lib/booking/web/) follows the same rule
and is driven end to end by `Rack::Test`.

Everything runs as **three processes** built from one image, sharing one SQLite
file and nothing else:

| Process | Entrypoint | Job |
|---|---|---|
| **bot** | [bin/bot](bin/bot) | Long-polls Telegram, greets, and sets the menu button. The only one that never touches the database. |
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
cp .env.example .env   # then fill in TELEGRAM_TOKEN
bundle exec rake seed
bundle exec bin/bot      # and, in their own shells:
bundle exec bin/poller
bundle exec bin/web
```

Each entrypoint asks only for what it uses: `bin/web` needs `BOT_USERNAME`,
`bin/bot` needs `APP_URL`, `BOT_USERNAME` and
`OWNER_TELEGRAM_ID`. Only the token is shared. Locally the mini app comes up
on `http://localhost:8080`, where it will redirect you to `/start` and then
tell you to open it from Telegram — the signed payload it needs only exists
inside a Telegram client. `APP_URL` has to be the deployed HTTPS one even
when you are running the bot locally: Telegram will not open a `web_app`
button over plain HTTP.

Poll once in the foreground, without starting the bot — the quickest way to see
whether an adapter still works:

```bash
bundle exec rake poll
```

Refreshing every club's Profile — courts and their covers, the pin, Listed
hours and prices — from sapadelo.com. It reads the clubs that name their page
there (`settings.sapadelo` in [config/clubs.yml](config/clubs.yml)) and
rewrites [config/club_profiles.yml](config/club_profiles.yml); review the diff
and commit it. Nothing at runtime talks to sapadelo:

```bash
bundle exec rake sapadelo:import
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

The star beside each club on a date's list makes it a **Favourite**: one
tap, kept per person. Favourites lead their half of that list, and come
already ticked on the form that creates a standing watch.

A date's **Share** button turns it into one message for whoever you play
with: every club with something free, its free hours folded into stretches
(`18:00–20:00, 22:00–23:00`), its price and its booking link, and the clubs
that are fully booked named at the end. A switch narrows it to your
Favourites or to clubs you tick by hand, and two pickers to the hours the
group can make — counted from that date's midnight, so a span can run to
02:00. Both live in the URL, so changing one keeps the other. Asking for
Favourites with none starred, or ticking nothing, shows every club rather than
an empty message. It leaves through Telegram's own share sheet
(`t.me/share/url`, no inline mode, no Bot API call) or the clipboard, for
every other messenger.

Tapping an hour that is **gone** asks to be told when it comes back: one tap,
no form, a watch on exactly that club and that hour. Hours that have already
started, and hours past the booking horizon, are drawn without a button —
nothing can free them up any more, or nobody has polled them.

**Clubs**, linked from the home screen, is every watched club whatever it has
free: its neighbourhood and how many courts sit indoors, under a roof, or in
the open. A club opens its **Profile** — each court and its cover, a button
that drops the pin in Google Maps, the hours and prices it lists, a phone
number and the booking page. The same screen is one tap away as **Info** on a
club's hours for a date, and the day's list of clubs names the covers beside
each one, which is the first thing anybody asks when it rains. Profiles come
from the clubs' own listings on sapadelo.com and say so; they are for reading,
and the Grid still draws from declared Opening hours. Padel Club 2 is not
listed there and has none.

Its second screen is **Watches**: everything you have asked to be told about,
with pause, resume and delete. A standing watch names the weekdays it keeps
coming back on; a dated one — the kind a tapped hour makes — names its single
day and says `Dated`. Pausing
stops a watch matching without losing it, and a dated watch drops off the list
once its hour has gone by — nothing reaps it, it simply stops mattering.

The same screen creates one: tick the clubs, tick the days, pick both ends of
an hour range, submit once. A watch that could never fire — no clubs, no days,
or an end that is not after its start — is refused with the reason and hands
back everything you picked, rather than being stored where it would sit in the
list looking like cover.

The **chat** is where you are told, not where you ask. `/start` greets you
with a button that opens the app; after that the bot speaks on its own only
when something you asked about has freed up. Writing anything else to the bot
sends it to the owner as feedback: `/feedback` and the app's "Tell us" pill
prompt for it, but the bot forwards any private message it does not recognise
as a command — text, photo, voice, whatever comes. See
[ADR-0002](docs/adr/0002-feedback-goes-back-through-the-bot.md) for why this
surface exists at all when watches are made in the app. In a group it says
nothing: Telegram refuses to open a mini app from there, so a greeting could
only be a dead end, and forwarding a message from a shared room would leak
the ack back into it.

The app itself is reachable from Telegram's menu button, which the bot sets for
itself every time it boots.

## Deploying

Docker on a VPS, driven by [Kamal](https://kamal-deploy.org). The config is
[config/deploy.yml](config/deploy.yml); the image goes to GHCR.

Every push to `main` deploys itself:
[.github/workflows/deploy.yml](.github/workflows/deploy.yml) runs the specs and
then `kamal setup` from a runner — `deploy` plus a bootstrap that installs
Docker only where it is missing, so a fresh server needs nothing but the SSH
key. It can also be started by hand from the Actions tab.

[.kamal/secrets](.kamal/secrets) is committed and holds no values — only the
names Kamal reads, each taken from the environment. The workflow fills that
environment from these repository secrets. The registry needs none: the image
goes to GHCR under the run's own `GITHUB_TOKEN`.

| Secret | What it is |
| --- | --- |
| `TELEGRAM_TOKEN` | from @BotFather |
| `CONTACT_EMAIL` | goes into the poller's User-Agent |
| `SSH_PRIVATE_KEY` | a key the server accepts for `root`; the host key is scanned on each run |
| `PADEL_ACADEMY_EMAIL`, `PADEL_ACADEMY_PASSWORD` | optional — the member login Padel Academy's schedule sits behind; handed to the poller alone |

From a laptop it is the same command, with those two exported in your shell
instead, plus `KAMAL_REGISTRY_PASSWORD`, which needs **`write:packages`**:

```bash
gh auth refresh -h github.com -s write:packages
export KAMAL_REGISTRY_PASSWORD=$(gh auth token)
```

SSH is just your own agent and `known_hosts`. First time on a fresh server, from a laptop:

```bash
bundle exec kamal setup
```

After that, by hand:

```bash
bundle exec kamal deploy
```

```bash
bundle exec kamal app logs -f
```

Three things about this deploy are worth knowing, because all three are
load-bearing:

**`web` is the primary role.** Kamal only puts a proxy in front of the primary
role by default, and of the three only the mini app has a port — `bot` and
`poller` serve nothing and say so with `proxy: false`. A non-primary role that
merely omits `proxy` gets none at all, silently.

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
`@BotFather`. The menu button that opens it is *not* one of them — the bot sets
that for itself on every boot from `APP_URL`, and says so in the log:

```
telegram: menu button -> https://kortuli-tgapp.qelphybox.space
```

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

- **Seven sources, ten clubs.** Padel Club 2 (Reservio), Kus Tba Padel
  (`turtle-booking`), GymBreeze (three locations), Padelbade (Book & Go, two),
  PadelHub (Supabase), Padel Academy (its own API, behind a member login) and
  Lemans Padel (its own API, open)
  — a venue with several locations is several clubs, because they sit in
  different parts of town. `tbilisipadel.com` runs BookingPress, which needs its
  own adapter; the reconnaissance is done and lives in `docs/research/`, and
  the remaining Tbilisi clubs are planned in `docs/coverage-plan.md`.
  Everything above the adapter is club-agnostic, so that is a new file in
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
- **Snapshots are not kept.** Current state plus a transition log, not full
  history — enough for "when do evening slots free up?", not enough to replay an
  arbitrary past moment.
