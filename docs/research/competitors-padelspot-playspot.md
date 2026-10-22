# Competitors: PadelSpot and PlaySpot

Read on 2026-10-22, from what each serves an anonymous visitor: PadelSpot's
Inertia page props (`<script data-page="app">` on `/`, `/clubs`,
`/padelis-kortebis-ruka` and `/?location=<city>`), PlaySpot's landing page and
its app's open `GET https://app.play-spot.app/api/clubs` and `/api/cities`.
Nothing behind a login was touched. Raw dumps are not kept; re-read them the
same way.

## Who they are

**PadelSpot** (`padelspot.ge`, Laravel + Inertia, `t.me/PadelSpotBot`) is the
closest thing to us. A web grid of free hours across every club, a Telegram bot
that answers "free courts today in Tbilisi" with buttons or through an AI
assistant, and "Notify me" reminders when a slot frees up. Around that, a whole
portal: a map of 48 venues, club pages with prices and weather, a coach
directory, tournaments with registration (one sponsored by Bybit), recorded
friendly matches with head-to-head stats, a blog and SEO landings, and a
merchant portal where a club can take bookings and host tournaments on
PadelSpot itself.

**PlaySpot** (`play-spot.app`, Next.js, `t.me/playspot_app_bot`, iOS and
Android) is a social app that happens to show courts. Its pitch is booking
inside the app, open seats in a 2v2, a results-driven rating a coach can
confirm, coach sessions, and Americano/Mexicano/King of the Hill tournaments
with live scoring. Padel and tennis. Its club catalogue spans Tbilisi, Batumi,
Kutaisi (empty), Yerevan and Tehran; only Tbilisi and Batumi have anything
bookable.

PlaySpot reads exactly what we read. Its `booking.locations[].id` are our
`location_id`, `cuadro_id` and `service_id` values verbatim — GymBreeze's
uuids, Padelbade's 141/163, Padel Island's 6/8, Tbilisi Padel's 1/4/6. PadelHub's
bundle names `playspot` as a booking source, so for PadelHub at least the
in-app booking is a real integration, not a link.

## Clubs: what they have that we do not

Against our 24 clubs in `config/clubs.yml`.

### Readable, worth adding

| Club | City | Courts | Who has it | What it runs |
|---|---|---|---|---|
| **PadelHipp** | Rustavi | 3 | PadelSpot, live | Own site. `GET https://padelhipp.com/api/availability?date=YYYY-MM-DD` answers anonymously, per court (`Court 1–3`), half-hour starts with an `available` boolean, `duration` 60 by default. `GET /api/config` gives hours (10:00–24:00), durations 60/90/120 and prices (60 weekday, 80 weekend). `robots.txt` disallows `/api/` — ADR-0004 applies. |
| **VR Krtsanisi Resort Residence** | Tbilisi | 2 | PadelSpot, live | WordPress + WooCommerce + **Bookly** (Pro) on `vrlifestyle.ge`; the court is a product page. Not probed past the page — Bookly's public form steps through `admin-ajax.php`, which needs its own recon. 60–80 GEL per PadelSpot. |

PadelHipp is the cheapest new club we will ever get: one GET per date returns
every court. The coverage plan still files it as "Instagram only"; that was
true on 2026-10-13 and is not now.

### Coming, worth watching

**FC Dinamo Tbilisi Padel Club** — nine outdoor courts at Boris Paichadze 11,
Dighomi. `padeldinamo.ge` is a "coming soon" page collecting phone numbers;
PadelSpot lists it as opening soon with no scraper yet. Nine courts would be
the largest club in the city. Re-probe the site weekly; whoever reads it first
on opening day has it alone for a while.

### Listed by them, not watchable

Not added, by the coverage plan's rule that a club without online booking is
not shown at all.

- Tbilisi: Bioli Wellness Resort (2, 200 GEL), Padel in Varketili (1),
  Sportscape (4, PadelSpot marks it closed), GPadel Tskneti (dead domain, still
  on both competitors).
- Batumi: Dunlop (WhatsApp only).
- Resort and hotel courts in the regions, on PadelSpot's map only: Chiko Group
  (Aspindza), Buknari Hotel, Georgia Palace Kobuleti, Kvareli Lake Resort,
  Samzeo Kvareli, Tskluleti Padel and Villa Mosavali (Mtskheta), Iora Winery
  and Mtevino (Sagarejo), Sairme Resort, Paragraph Shekvetili, Bodbe Hotel
  (Sighnaghi), The Wine Station and Tsinandali Estate (Telavi), Chateau
  Vartsikhe. Fifteen venues, mostly one to three courts, none bookable online.
  PadelSpot uses them for reach (`/padelis-kortebi-kurortebze`), not slots.

Tbilisi Padel Didi Dighomi's 1-vs-1 court is on both. We leave it out on
purpose — see `bookingpress-tbilisi-padel.md`.

## Clubs: what we have that they do not

**PadelSpot** lists every one of our 24. But on 2026-10-22 its own flags read
`has_scraper: true, has_availability: false` for Kus Tba (8 courts), all three
GymBreeze sites (16), Padelbade Krtsanisi (5) and Padel Academy (3) — the
biggest clubs in Tbilisi. Krtsanisi with nothing free all day is unlikely, so
this looks like broken scrapers rather than full courts (**UNVERIFIED** — one
reading, not a trend). Worth re-reading before anyone repeats it.

**PlaySpot** has 16 bookable Georgian clubs to our 24. Missing: Padel Gldani,
Padelbade Rustavi, Higgs, Love Padel, AIA Padel, Padel Island Gudauri and
Kachreti, and GymBreeze Sport Palace (listed, `booking: null`). Every Rustavi,
Kutaisi and resort club.

Court counts disagree in places — PadelSpot says PadelHub 2 (it is 3 since
2026-10-05), Kachreti 2 (the grid sells 4), AIA 4 (one is inactive); PlaySpot
says GymBreeze Ninoshvili 9 and Radio City 2. Ours come from the sources and
stand.

## Features side by side

| | Us | PadelSpot | PlaySpot |
|---|---|---|---|
| Free hours across clubs | Grid, one City | Web grid + Telegram buttons | Per club, in app |
| Cancellation alert | Telegram, no quota | SMS or email, 100 a month, account and phone required | — none advertised |
| Recurring window ("Tuesdays 19–22") | **Standing watch** | — reminders are per date and expire | — |
| Several clubs in one alert | yes | yes | — |
| Durations | 60 | 30–180, half-hour starts | 60–180 per provider |
| Booking | link out | link out; in-platform for merchant clubs | in app, at least PadelHub |
| Natural-language search | — | AI assistant, web and bot | — |
| Weather | Forecast per City | per venue per day | — |
| Map, club pages, prices | yes | yes, richer (gallery, amenities, rackets) | yes, with ratings |
| Coaches | — | directory | bookable sessions |
| Tournaments | — | registration, brackets | create, run, live scoring |
| Matchmaking / rating | — | recorded friendlies, head-to-head | open 2v2 seats, rating |
| Other sports | — | — | tennis |
| Languages | one | ka, en | en, ka, uk, ru |

## What this means for us

1. **Clubs.** Add PadelHipp now; recon VR Krtsanisi's Bookly next; put
   `padeldinamo.ge` on a weekly re-probe. That makes us a strict superset of
   both competitors' watchable clubs. The resort directory is reach, not
   product — skip it unless the map grows a "no online booking" layer on
   purpose.
2. **Reliability is the moat on clubs.** PadelSpot already lists everything;
   it loses on the clubs it silently stops reading. A watched club that goes
   dark should be visible to us before a user notices — the ops dashboard is
   where that belongs.
3. **The Standing watch is the one thing neither has.** PadelSpot's reminders
   are dated, capped and go by SMS. A recurring Telegram watch with no quota
   and no sign-up is the pitch; say it on the first screen.
4. **Durations and half-hour starts are the real feature gap.** Both
   competitors offer 90 and 120. The coverage plan's wave 4 already notes that
   half-hour starts are half of Padelbade's inventory and that watching them is
   a Grid change first. That change now has a competitive reason.
5. **Do not chase the social layer.** Matchmaking, ratings and tournaments are
   PlaySpot's whole product and PadelSpot's sideline; neither is better at
   catching a cancellation because of it. The one bridge worth a thought is
   the moment after a slot frees up: "court's free, need a fourth".
