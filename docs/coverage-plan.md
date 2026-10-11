# Covering Tbilisi

What it takes to watch every Tbilisi padel club we can legitimately read, and
what a *new city* would cost after that.

Written 2026-07-31 from the three recon notes in `docs/research/`. Every claim
about an endpoint traces to one of them; nothing here is taken from a
directory listing.

## Where we are

Ten clubs, 44 courts, all Tbilisi: Padel Club 2 (Reservio), Kus Tba,
GymBreeze Ninoshvili, GymBreeze Radio City, GymBreeze Sport Palace,
Padelbade Krtsanisi and Padelbade Dighomi (since #10), PadelHub, Padel
Academy and Lemans Padel.

The two adapters still open below take that to **fourteen clubs and 54
courts** without touching a single club that has asked not to be read.

## Decisions this plan assumes

Taken 2026-07-31:

- **Tbilisi first, to completion.** `City` does not become a domain term in
  this round. Batumi waits, even though it is technically ready.
- **The Grid stays the first screen**, with a filter above it rather than a
  club-picker in front of it.
- **A club with no online booking is not shown at all.** Being in the app means
  being watchable.

## The inventory

Court counts from sapadelo.ge, which disagrees with every other directory and
is the only one sourced from the clubs themselves. Neither it nor the market
survey is complete — sapadelo omits Padel Club 2, which we already watch.

| Club | Courts | System | State |
|---|---|---|---|
| GymBreeze Ninoshvili | 8 | gymbreeze | watched |
| Kus Tba | 8 | kustba | watched |
| Padel Club 2 | 4 | reservio | watched |
| GymBreeze Radio City | 3 | gymbreeze | watched |
| Padelbade Krtsanisi | 5 | Book & Go | watched |
| Padelbade Dighomi | 2 | Book & Go | watched |
| Tbilisi Padel Didi Dighomi | 5 | BookingPress | **wave 2** |
| Tbilisi Padel Mtatsminda | 1 | BookingPress | **wave 2** |
| Tbilisi Padel Ilia's Garden | 1 | BookingPress | **wave 2** |
| Lemans Padel | 4 | own | watched |
| Padel Gldani | 3 | own (tRPC) | **wave 3** |
| PadelHub | 3 | own (Supabase) | watched |
| Sportscape Samgori | 4 | unknown | not researched |
| Padel Academy | 3 | own (Laravel), member login | watched |
| Padel Island Lisi / Expo | 4 | TPC MatchPoint | **excluded, see below** |
| Padelio | ? | own | broken upstream |
| GPadel Tskneti | 2 | — | dead domain |
| Vera Park | 1 | — | not open |
| GymBreeze Sport Palace | 4 | gymbreeze | watched |

## Excluded on purpose

**Padel Island (4 courts, two Tbilisi locations).** `booking.padelisland.ge`
runs TPC MatchPoint, not Padel Mates as the survey claimed. Its `robots.txt`
disallows `/Booking/` and `/Services/`, and the site is behind a login and a
Turnstile challenge. Reading it means deliberately working around a refusal the
operator wrote down. We do not do that for four courts. If those courts matter,
the move is to ask the club for access — MatchPoint serves partners on the same
backend.

**Padel Mates** — the real platform, cracked and unauthenticated, but a nearby
search centred on Tbilisi returns 309 clubs and none in Georgia. Dead end.

**GPadel Tskneti** — `gpadel.ge` is NXDOMAIN. Directories still link to it. It
also has 2 courts, not the 8 the survey reported.

**Padelio** — front end is live, but every `/api/*` path answers
`503 API_ORIGIN is not configured`, and the bundle falls back to a hard-coded
"Padelio Demo Venue". Anything a browser renders there is fabricated
client-side. Re-probe in a few months.

## Foundations

Two pieces of shared work. Both are small; both block adapters.

**F1 — `Http#post_json`.** *Done.* POST and per-request headers, POSTs on the
retry list as a decision, and a 401 raised as `Adapters::Unauthorized` — still a
`SourceUnavailable` to the poller. It also had to learn to inflate a body that
arrives still gzipped, which Supabase does. As planned:
BookingPress and PadelHub both need a JSON POST with per-request headers
(`X-WP-Nonce`, Supabase `apikey`). Keep the one failure mode: everything still
surfaces as `Adapters::SourceUnavailable`. Note the retry policy is
deliberately `methods: [:get]` — these POSTs are reads, so adding them to the
retry list is safe, but it should be a decision in the diff, not an accident.

**F2 — free-from-booked helper.** *Done*, smaller than planned: it is
`OpeningHours#starts_by_label`, the day's starts keyed by "HH:MM", and each
adapter subtracts or selects with it. Padel Academy reads through it too. As
planned: Padel Gldani and PadelHub both report what is
*taken*, while the adapter contract owes the differ only what is *free*.
`OpeningHours#starts_on(date)` already produces the exact hour grid to subtract
from, including the past-midnight rollover. One small module, used twice.

## Waves

Independent within a wave; ordered by courts-per-unit-of-work.

### Wave 1 — no foundations needed

- ~~**Book & Go** → Padelbade Krtsanisi + Dighomi, **7 courts**.~~ **Done, #10.**
  `GET https://api.bookandgo.app/api/v1/apps/58/court-bookings?date=`,
  unauthenticated, free slots only, per court, `Asia/Tbilisi` declared in the
  payload. One request returns all three Georgian locations at once, so two
  clubs cost one endpoint. The server does **not** filter past hours — the
  adapter must. Horizon 14 days for Dighomi, 22–30 for Krtsanisi.
  *Best ratio in the whole plan.* Half-hour starts turned out to be half the
  inventory and are **not** watched — the Grid matches Cells on an exact hourly
  `starts_at`, so watching them is a Grid change first. Folded into wave 4.
- ~~**Lemans Padel** → **4 courts**.~~ **Done.** `GET https://booking.lemanspadel.ge/api/availability?date=&duration=60`,
  no auth, explicit `available` boolean plus an `available_courts` count. It
  also takes `court_id` and answers for that court alone, echoing the id —
  which the recon missed — so this is a **court-level club** at four requests
  a date rather than one per start. No server-side horizon, so `max_days` is
  ours. Price is 50 on weekday starts before 17:00, 70 otherwise; the court
  list's flat `duration_prices` is wrong about that.

### Wave 2 — needs F1

- **BookingPress** → all three Tbilisi Padel locations, **7 courts**.
  `POST /wp-json/bookingpress-app/v1/form-v3/month-details` returns a whole
  month per request — cheaper per slot than anything we run today. Free slots
  only. Service ids 1 / 4 / 6, and Didi Dighomi's `remaining_capacity` makes it
  a **court-level club** like Padel Club 2. Auth is a triple scraped from the
  page per tick (`X-WP-Nonce`, `bp_v3_nonce`, and a matched
  `instanceId`/`instanceToken` pair) — no login. Expect to retry once on a
  stale nonce.

### Wave 3 — needs F1 + F2

- **Padel Gldani** → **3 courts**. Open tRPC, `bookings.getBookedSlots`,
  batched so three courts arrive in one request. Returns booked intervals →
  invert. Has a real `?court=<id>` deeplink, the only club here that does.
- ~~**PadelHub** → **3 courts**~~ **Done.** A third court opened 2026-10-05. Supabase RPC
  `POST /rest/v1/rpc/get_booking_availability` with the publishable anon key
  from the bundle. Returns booked hours per court → invert. The `bookings`
  table itself is RLS-blocked; the RPC is the intended door. Read the court
  list per tick rather than pinning UUIDs, and count only `confirmed` rows as
  taken — see `docs/research/sport-palace-padelhub-padel-academy.md`.

### Wave 4 — the Grid at twelve clubs

Twelve rows of eighteen hours does not fit a phone. The decision is: keep the
Grid as the first screen, put a filter above it. That needs a district on each
club — `settings.district` is enough, no schema change — and it is the one
piece of work here that is product design rather than plumbing. Worth its own
grilling session before anyone writes markup.

## What a new club costs, once its wave lands

1. Confirm the club is real and readable — a directory listing is not evidence.
2. If its system is already adapted: **one entry in `config/clubs.yml`**, and
   `rake seed` on boot mirrors it in. No code.
3. Otherwise: an adapter in `lib/booking/adapters/`, one line in
   `Adapters::REGISTRY`, a fixture under `spec/fixtures/`, and a spec.
4. Declare `opening_hours` and `max_days` by hand. No source reports either
   reliably — that is why `OpeningHours` exists.
5. Set `courts:` only if the source names individual courts. Its absence is
   what makes a club hour-level.

GymBreeze Sport Palace was case 2: it opened by 2026-10-10 and is watched
through one config entry.

## What a new city costs

Nothing in the code knows what a city is. `Club` has slug, name, adapter,
settings, interval, enabled (`lib/booking/club.rb`) — no location at all. So a
city is not an adapter problem, it is a domain and UI one:

1. **`City` becomes a term in `CONTEXT.md`**, and probably an ADR: does a Watch
   belong to a city, or only to the clubs a person picked? Today a Watch names
   clubs, which may mean a city is purely a filter and never a stored thing.
   That question is the whole design.
2. **A field on `Club`** — settings is enough to start.
3. **The Grid filter from Wave 4** grows a city level above district.
4. Then the clubs themselves, which are mostly cheap:
   - **Batumi**: Padel Port (4) + Padel Port New Park (2) are one Reservio
     business, `1e32bd0a-0d5c-4e30-9788-ea488e713c4d`, verified live. But its
     six courts are six *services*, where Padel Club 2 has one service and four
     resources — and `Reservio` takes a single `service_id`
     (`lib/booking/adapters/reservio.rb:18`). **Batumi needs `service_ids` as a
     list**, and that same change is what splits one business into the two
     Clubs the domain says it should be. Grand Padel (2) and Dunlop (1) are
     unresearched.
   - **Rustavi**: Padelbade Rustavi (2) is already in the Wave 1 API response —
     one config line. Higgs (3) appears to be reachable through GAMO's open
     `/en/book/availability?product_id=&date=` marketplace API, which turned out
     to have exactly one padel venue and it is this one.
   - **Kutaisi**: Love Padel is phone and Instagram only. Under the "not shown
     at all" rule, Kutaisi has nothing in it.

So the first city after Tbilisi is a domain decision plus one adapter change,
and it buys Batumi and Rustavi together.

## Known gaps in the research

- **Sportscape Samgori (4 courts)** was never researched — the survey had no
  booking URL for it and it was left out of the recon brief. It is the largest
  unexamined club in Tbilisi.
- **Padel Academy (3 courts)** is watched since 2026-10-10 through a member
  account the owner holds (`PADEL_ACADEMY_EMAIL`/`_PASSWORD`). If the club
  closes that account, the club goes dark and the log says so.
- **Nonce lifetime** for BookingPress is inferred from WordPress defaults, not
  measured. Re-scraping per tick makes it moot.
- No per-club deeplink exists for Book & Go or BookingPress. Both fall back to
  a static `booking_url`, exactly as `Gymbreeze` already does.
