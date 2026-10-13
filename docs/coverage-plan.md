# Covering Georgia

What it takes to watch every Georgian padel club we can legitimately read.

Started 2026-07-31 as a Tbilisi plan from the recon notes in `docs/research/`;
widened to the whole country on 2026-10-13, after a sweep of every directory
(`docs/research/georgia-regional-and-samgori.md`) and a live probe of each
booking system. Every claim about an endpoint traces to a note or to a live
response; nothing here is taken from a directory listing alone.

## Where we are

Twenty clubs, 67 courts, four Cities:

- **Tbilisi** — Kus Tba, GymBreeze Ninoshvili, Radio City and Sport Palace,
  Padelbade Krtsanisi and Dighomi, PadelHub, Padel Academy, Lemans Padel,
  Tbilisi Padel Didi Dighomi, Mtatsminda and Ilia's Garden, Padel Gldani.
- **Batumi** — Padel Port, Padel Port New Park, Grand Padel Batumi.
- **Rustavi** — Padelbade Rustavi, Higgs.
- **Kutaisi** — Love Padel, AIA Padel.

Every club in Georgia with an online booking page that answers an anonymous
visitor is in. What is left out is below, with the reason.

## Decisions this plan assumes

- **Tbilisi first, to completion** (2026-07-31) — done, and then superseded
  on 2026-10-13: City is a domain term ([ADR-0003](adr/0003-city-is-a-club-attribute.md)),
  and the plan covers the country.
- **`robots.txt` alone does not exclude a club; a login or a challenge does**
  ([ADR-0004](adr/0004-robots-txt-is-not-a-refusal-a-login-is.md)). Decided
  2026-10-13, when the old rule would have emptied Batumi.
- **The Grid stays the first screen**, with a filter above it rather than a
  club-picker in front of it.
- **A club with no online booking is not shown at all.** Being in the app means
  being watchable.

## The inventory

Court counts from sapadelo.com, which disagrees with every other directory and
is the only one sourced from the clubs themselves, corrected where a club's own
system says otherwise. padelspot.ge and mypadelway.com were checked and are
not to be trusted: three of padelspot's claims and one of mypadelway's failed
verification.

**Padel Club 2 is not a club.** `padel-club2.reservio.com` is GymBreeze
Ninoshvili's own Reservio page — the same courts under a second name. It was
watched as a club of its own until 2026-10-13 and dropped then; do not add it
back when a directory or `discover:reservio` turns it up again.

| City | Club | Courts | System | State |
|---|---|---|---|---|
| Tbilisi | GymBreeze Ninoshvili | 8 | gymbreeze | watched |
| Tbilisi | Kus Tba | 8 | kustba (WordPress, turtle-booking) | watched |
| Tbilisi | GymBreeze Sport Palace | 4 | gymbreeze | watched |
| Tbilisi | GymBreeze Radio City | 3 | gymbreeze | watched |
| Tbilisi | Padelbade Krtsanisi | 5 | Book & Go, tenant 58 | watched |
| Tbilisi | Padelbade Dighomi | 2 | Book & Go, tenant 58 | watched |
| Tbilisi | Tbilisi Padel Didi Dighomi | 4 + one 1v1 | BookingPress | watched (the 1v1 court is not) |
| Tbilisi | Tbilisi Padel Mtatsminda | 1 | BookingPress | watched |
| Tbilisi | Tbilisi Padel Ilia's Garden | 1 | BookingPress | watched |
| Tbilisi | Lemans Padel | 4 | own (PHP) | watched |
| Tbilisi | Padel Gldani | 3 | own (tRPC, Manus) | watched |
| Tbilisi | PadelHub | 3 | own (Supabase) | watched |
| Tbilisi | Padel Academy | 3 | own (Laravel), member login | watched |
| Tbilisi | Sportscape Samgori | 4 | — | no online booking found |
| Tbilisi | Padel Island Lisi / Expo | 4 | TPC MatchPoint | **excluded, see below** |
| Tbilisi | Vera Park | 1 | — | not open |
| Batumi | Padel Port | 4 | Reservio | watched |
| Batumi | Padel Port New Park | 2 | Reservio (same business) | watched |
| Batumi | Grand Padel Batumi | 2 | Reservio | watched |
| Batumi | Dunlop Batumi | 1 | — | WhatsApp only |
| Rustavi | Padelbade Rustavi | 2 | Book & Go, tenant 58 | watched |
| Rustavi | Higgs | 3 | own (ASP.NET); also on GAMO | watched |
| Rustavi | PadelHipp | 3 | — | Instagram only (opened 2026-09-24) |
| Kutaisi | Love Padel | 2 | Book & Go, tenant 126 | watched |
| Kutaisi | AIA Padel | 3 active of 4 | own (Next.js) | watched |
| Gudauri, Kachreti | Padel Island (hotels) | ? | TPC MatchPoint | **excluded, see below** |
| Borjomi | Borjomi Park Padel | 3 | — | not open |
| Tskneti | GPadel | 2 | — | dead domain |
| — | Padelio | ? | own | broken upstream |

## Excluded on purpose

**Padel Island (four Georgian venues: Lisi and Expo in Tbilisi, Gudauri,
Kachreti).** `booking.padelisland.ge` runs TPC MatchPoint, and all four venues
book through its one grid. The grid sits behind a login and a Turnstile
challenge. Its `robots.txt` also disallows `/Booking/` and `/Services/`, which
on its own would not keep it out (ADR-0004); the login and the challenge do.
If those courts matter, the move is to ask the club for access — MatchPoint
serves partners on the same backend.

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

- ~~**BookingPress** → all three Tbilisi Padel locations, **7 courts**.~~
  **Done, 2026-10-13**, as six: Didi Dighomi's fifth court is a 1v1 court sold
  as its own service, and is not watched. The site moved to `tbilisipadel.ge`;
  Didi Dighomi now sells 00:00 and 01:00 under the date before. Nonces are
  scraped once and shared by the three clubs, re-scraped on a 403/400.
  `POST /wp-json/bookingpress-app/v1/form-v3/month-details` returns a whole
  month per request — cheaper per slot than anything we run today. Free slots
  only. Service ids 1 / 4 / 6, and Didi Dighomi's `remaining_capacity` makes it
  a **court-level club** like Padelbade. Auth is a triple scraped from the
  page per tick (`X-WP-Nonce`, `bp_v3_nonce`, and a matched
  `instanceId`/`instanceToken` pair) — no login. Expect to retry once on a
  stale nonce.

### Wave 3 — needs F1 + F2

- ~~**Padel Gldani** → **3 courts**.~~ **Done, 2026-10-13.** Its `robots.txt`
  gained `Disallow: /api/` on 2026-09-30 (a Manus default, by the look of it);
  read under ADR-0004. Open tRPC, `bookings.getBookedSlots`,
  batched so three courts arrive in one request. Returns booked intervals →
  invert. A business day is now D's bookings from 08:00 plus D+1's before
  08:00, as the site's own client builds it, so each day reads two dates. Has a real `?court=<id>` deeplink, the only club here that does.
- ~~**PadelHub** → **3 courts**~~ **Done.** A third court opened 2026-10-05. Supabase RPC
  `POST /rest/v1/rpc/get_booking_availability` with the publishable anon key
  from the bundle. Returns booked hours per court → invert. The `bookings`
  table itself is RLS-blocked; the RPC is the intended door. Read the court
  list per tick rather than pinning UUIDs, and count only `confirmed` rows as
  taken — see `docs/research/sport-palace-padelhub-padel-academy.md`.

### Wave 4 — the Grid at twelve clubs

Still open. The City switch took Batumi, Rustavi and Kutaisi off Tbilisi's
screen, but Tbilisi alone is thirteen clubs now. Twelve rows of eighteen hours
does not fit a phone. The decision is: keep the
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

**Done, 2026-10-13**, for Batumi, Rustavi and Kutaisi. City is a Club's
attribute (`settings.city`), never stored on a Watch; each City has its own
Forecast point; a person looks at one City at a time and the switch appears
once there are two. [ADR-0003](adr/0003-city-is-a-club-attribute.md) has the
reasoning. Georgia keeps one clock, so nothing about time changed.

A further City costs a line in `Weather::CITIES` (a spec fails without it),
`city:` on its clubs, and the clubs themselves. What the first three took:

- **Batumi** — `Reservio` learned `service_ids` as a list, one request per
  service (the API takes one id per request), which is also what splits Padel
  Port's one business into its two sites. Grand Padel sells each court as three
  price bands, each its own service and resource; `court_aliases` folds them
  back into two courts.
- **Rustavi** — Padelbade Rustavi was one config entry on the Book & Go tenant
  already read. Higgs has its own open API and its own adapter; GAMO is not
  needed.
- **Kutaisi** — Love Padel is not phone-only after all: `book.lovepadel.ge` is a
  second Book & Go tenant (126), read by the same adapter pointed elsewhere,
  which now drops the pickleball courts that share its location. AIA Padel has
  its own app, read before sign-in.

## Known gaps in the research

- **Sportscape Samgori (4 courts)** has no booking link, site or phone anywhere
  public, only an Instagram handle; Instagram needs a login, so it was not
  looked at. Re-check when it shows up on sapadelo with a link.
- **Higgs** reads almost entirely free — three booked hours on one court on the
  day it was checked. Either the club takes most bookings off this system, or
  it is new. Watch the first week's logs before trusting its notifications.
- **AIA Padel** read every future hour free on the day it was built, so no
  taken-to-free transition has been seen live yet.
- **Padel Academy (3 courts)** is watched since 2026-10-10 through a member
  account the owner holds (`PADEL_ACADEMY_EMAIL`/`_PASSWORD`). If the club
  closes that account, the club goes dark and the log says so.
- **Nonce lifetime** for BookingPress is inferred from WordPress defaults, not
  measured. Re-scraping per tick makes it moot.
- No per-club deeplink exists for Book & Go, BookingPress or Reservio. Both fall back to
  a static `booking_url`, exactly as `Gymbreeze` already does.
