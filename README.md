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
fully testable without a token or a network.

Everything runs in **one process**: the Telegram loop on the main thread, the
poll loop on a rufus-scheduler thread, one SQLite file between them.

## Getting it running

```bash
bundle install
cp .env.example .env   # then fill in TELEGRAM_TOKEN and OWNER_TELEGRAM_ID
bundle exec rake seed
bundle exec bin/bot
```

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

- `/watch` — build a watch: clubs → days → hours
- `/list` — your watches, with pause and delete buttons
- `/help` — what the bot does

## Deploying

A VPS with systemd. [deploy/booking-bot.service](deploy/booking-bot.service) is
the unit; adjust `User` and `WorkingDirectory`, then:

```bash
sudo systemctl enable --now booking-bot && journalctl -u booking-bot -f
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

Back up by copying `data/booking.db`.

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

**Timezones.** Everything is UTC inside. Local time (Asia/Tbilisi) exists at
exactly two edges: adapters parsing a club's clock, and messages printing one.

## Known limits

This is an MVP, deliberately:

- **One club, not two.** Only Padel Club 2 (Reservio) ships. The concept named
  `tbilisipadel.com` as the second, but it runs BookingPress, which needs its own
  adapter and its own reconnaissance — neither is done. Everything above the
  adapter is club-agnostic, so that is a new file in
  [lib/booking/adapters/](lib/booking/adapters/) and a line in `REGISTRY`.
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
