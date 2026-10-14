# Beyond padel — tennis, squash, pickleball, badminton, table tennis

Every Georgian venue for a racket sport other than padel that a web search
turned up as bookable online, probed live on 2026-10-14 between 03:25 and
03:50 Tbilisi time (2026-10-13 23:25–23:50 UTC). In the samples "today" is
2026-10-14 in Tbilisi. Every endpoint below was called anonymously, with no
cookie and no token, and the samples are literal excerpts. Anything not
confirmed by a live call or a line of the venue's own bundle is marked
**UNVERIFIED**.

Where the list came from: a multi-source web sweep (Gamo, club sites, App
Store and Play listings, directories), compared against `config/clubs.yml`.
None of these venues is on Playtomic, MATCHi, Padel Mates or Reservio. Batumi,
Kutaisi and the other regional cities turned up nothing beyond the padel clubs
we already watch.

| Venue | Sport | City | Courts | System | Auth | Verdict |
|---|---|---|---|---|---|---|
| [Gamo](#gamo--gamoge) (Leila Meskhi ×3, Tokhadze, Nutsubidze, LeaderSport, Lebowski) | tennis, squash, table tennis | Tbilisi | 13 | marketplace, Next.js | none for reads | **Readable**, one adapter for 7 venues |
| [Lisi Tennis Club](#lisi-tennis-club--lisitennisclubge) | tennis | Tbilisi | 1 | own, ASP.NET | none | **Readable**, court-level, explicit status |
| [Mizano](#mizano--mizanoge) | badminton | Tbilisi | 2 | own, Next.js | none | **Readable**, court-level, explicit status |
| [Vake Park Tennis Courts](#vake-park-tennis-courts--youthtbilisige) | tennis | Tbilisi | 3 + mini | municipal (TSYC), Next.js + Laravel API | none | **Readable**, but very little of it is sold online |
| [PadelHub](#padelhub--pickleball) | pickleball | Tbilisi | 1 | already adapted (Supabase) | none | **Already fetched, filtered out** |
| [Love Padel](#love-padel--pickleball) | pickleball | Kutaisi | 2 | already adapted (Book & Go) | none | **Already fetched, filtered out** |
| [ProSpin](#prospin--bookingprospinge) | table tennis | Tbilisi | 4 tables | own, Firebase + Cloud Run | **login** | **Excluded**, ADR-0004 |
| [MZE Pickleball](#mze-pickleball--bookmzepickleballcom) | pickleball | Tbilisi | ? (Saburtalo, Dighomi) | own | members | **Excluded** |

Nothing here is wired up. Every one of these needs the app to learn that a
Club has a sport first, or a tennis hour lands in the padel Grid.

---

## Gamo — gamo.ge

**The old recipe is dead.** `docs/research/self-written-club-sites.md`
describes Gamo as Laravel + Inertia with
`GET /en/book/availability?product_id=&date=`. That path is now a **404**: the
site was rebuilt as a **Next.js App Router** app on **Vercel** (`server: Vercel`,
`NEXT_LOCALE` cookie, turbopack chunks under `/_next/static/immutable/`). The
product ids did survive the move: PadelHiggs is still 196.

`https://gamo.ge/robots.txt` is `User-Agent: * / Allow: /`.

### 1. Where the calendar reads from

The booking sheet is a client component (`BookProvider`, module `617189`)
whose lazy chunks call two same-origin route handlers. Literal, from
`/_next/static/immutable/chunks/1o5kklztxao01.js` and siblings:

```js
fetch(`/api/book/venues?sport=${encodeURIComponent(e)}&locale=${encodeURIComponent(t)}`,{cache:"no-store"})
fetch(`/api/book/day?product=${String(e)}&date=${t}`,{cache:"no-store"})   // 404 → null
```

The only server actions in the bundle are auth, `verifyPromoAction` and
`bookAction`. Availability is not behind any of them.

### 2. Catalogue, per sport

`GET https://gamo.ge/api/book/venues?sport=<key>&locale=en`, no auth, 200:

| `sport=` | Venues |
|---|---|
| `tennis` | 194 Bubble Court, 193 Clay Court, 192 Theraflex Closed (all Leila Meskhi Academy), **191 Squash – LeaderSport Arena**, 166 Courts at Nutsubidze |
| `table-tennis` | 186 Ping Pong – Lebowski East Point |
| `padel` | 196 PadelHiggs (Rustavi). This is the Higgs we already read through its own API |
| `squash`, `badminton`, `pickleball`, `tabletennis` | `[]` |

Squash is filed under `tennis` (`"sport":"Tennis"` on product 191), so
`sport=squash` comes back empty. The venue's name is the only reliable sign
of what it is.

Entry shape:

```json
{"id":194,"slug":"bubble-court-leila-meskhi-academy","name":"Bubble Court - Leila Meskhi Academy",
 "sport":"Tennis","district":"Marjanishvili","city":"Tbilisi","address":"29 Kote Marjanishvili St, Tbilisi",
 "coords":{"lat":41.709551,"lng":44.796273},"isInstantBook":false,"extras":[],
 "minBookingMinutes":60,"slotIntervalMinutes":60,"priceTetri":5500,"price":"₾55"}
```

**Guram Tokhadze Tennis Club is not in that list**, yet its pages render and
its day endpoint answers. The RSC payload of `/en/venues/guram-tokhadze-tennis-club`
names it product **167** (`"sport":"Tennis","district":"Didube"`). The sitemap
also lists `guram-tokhadze-court-1..3`, which are products **200, 201, 202**,
one zone each. 167 has `zones: 3`, so 167 looks like the three courts read
together. Reading both would count each court twice. Hidden from the catalogue
on purpose or by mistake: **UNVERIFIED**.

### 3. One day of one venue

`GET https://gamo.ge/api/book/day?product=194&date=2026-10-14`, no auth, 200:

```json
{"date":"2026-10-14","zones":4,"minAdvanceHours":3,"minBookingMinutes":60,"slotIntervalMinutes":60,
 "baseTetri":5500,"useDynamicPrices":false,"rules":[],
 "ranges":[{"startMinute":420,"endMinute":840},{"startMinute":1320,"endMinute":1440}],
 "nextDayRanges":[…same…],"closedDates":[],"busy":[],"blackouts":[],"nowMs":1791934028597}
```

The client maps it like this, literally:

```js
{date:n.date,zones:n.zones,minAdvanceHours:n.minAdvanceHours,ranges:n.ranges,nextDayRanges:n.nextDayRanges,
 bookings:n.busy.map(e=>({start:new Date(e.startMs),end:new Date(e.endMs)})),
 blackouts:n.blackouts.map(e=>({start:new Date(e.startMs),end:new Date(e.endMs)})), …}
```

- `zones` is the number of courts. `busy` is a list of `{startMs, endMs}` with
  **no court id**. A start is free while fewer than `zones` busy intervals
  overlap it. That makes Gamo an **hour-level club that can still say how
  many**: the free count is `zones − overlapping busy`.
- `ranges` gives the open hours as minutes from midnight. They differ per
  venue and are not one block: the Bubble Court sells 07:00–14:00 and
  22:00–24:00 only. `closedDates` and `blackouts` close whole days and spans.
- Seen non-empty `busy`, 2026-10-13: product 194
  `{"startMs":1791880200000,"endMs":1791883800000}` (12:30–13:30 Tbilisi), and
  193 `{"startMs":1791918000000,…}` (23:00). So a booking does show up here.
- Unknown product: `{"error":"not found"}`, 404.

A seven-day sweep of every product found `busy` almost always empty. Like
Higgs, most of these venues take their bookings somewhere else, and Gamo only
sees a little of it.

| Product | Venue | `zones` | Hours sold (`ranges`) | Notes |
|---|---|---|---|---|
| 194 | Bubble Court, Leila Meskhi | 4 | 07–14, 22–24 | 55 ₾, hourly starts |
| 193 | Clay Court, Leila Meskhi | 1 | — | 55 ₾ |
| 192 | Theraflex Closed, Leila Meskhi | 1 | — | 55 ₾ |
| 167 | Guram Tokhadze Tennis Club | 3 | 11–15, 21–23 | 60 ₾; 200–202 per court |
| 166 | Courts at Nutsubidze | 1 | — | 70 ₾; closed Sundays; at Public School №171, rents a *Tennis Racket* extra, so it is tennis after all |
| 191 | Squash – LeaderSport Arena | 2 | — | 66 ₾; instant book; `closedDates` 14–16 Oct |
| 186 | Ping Pong – Lebowski East Point | 1 | — | table tennis |

### 4. Granularity and deeplink

Per product and per half or whole hour (`slotIntervalMinutes` 30 or 60),
minimum 60 minutes, nothing bookable within `minAdvanceHours` (3).
Deeplink: `https://gamo.ge/en/venues/{slug}`.

**Verdict:** one `gamo` adapter, configured with a product id per Club,
covers six tennis/squash venues and a ping-pong table. Cheapest new coverage
on this page.

---

## Lisi Tennis Club — lisitennisclub.ge

ASP.NET Core on IIS/Plesk (`server: Microsoft-IIS/10.0`,
`x-powered-by: ASP.NET`). `robots.txt` comes back empty. The `/Book` page
sets an antiforgery cookie, but the GETs below do not need it.

The booking page's inline script calls:

```
/api/courts/availability?startDate=${…}&days=…
/api/courts/${selectedCourtId}/slots/${dateStr}
```

`GET /api/courts`:

```json
[{"id":1,"name":"Tennis Court","nameGeo":"ჩოგბურთის კორტი","surface":"Hard","isIndoor":false,"hourlyRate":55.00}]
```

`GET /api/courts/availability?startDate=2026-10-13&days=30` returns
**six** days however many you ask for, so the horizon is about a week:

```
2026-10-13 2/29 · 2026-10-14 0/29 · 2026-10-15 0/29 · 2026-10-16 5/29 · 2026-10-17 9/29 · 2026-10-18 8/29
```

`GET /api/courts/1/slots/2026-10-16`:

```json
[{"timeSlotId":1,"startTime":"08:00","endTime":"09:00","isAvailable":false,"status":"Lesson"},
 {"timeSlotId":29,"startTime":"08:30","endTime":"09:30","isAvailable":false,"status":"Lesson"},
 {"timeSlotId":19,"startTime":"13:30","endTime":"14:30","isAvailable":true,"status":"Available"},
 {"timeSlotId":8,"startTime":"15:00","endTime":"16:00","isAvailable":true,"status":"Available"}, …]
```

- An explicit per-slot status, `Available` / `Booked` / `Lesson`, so there is
  nothing to invert.
- Starts every half hour, 60 minutes each, so they overlap. Read only the
  hourly starts, as `Bookandgo` does.
- This one is in real demand: two days out of six are sold out. That is the
  case a cancellation watcher is for.
- The homepage still says online booking "opens late May 2026", but `/Book`
  and the API work.

**Verdict:** court-level and trivial to adapt.

---

## Mizano — mizano.ge

Next.js behind Cloudflare. `robots.txt` disallows `/admin`,
`/book/checkout`, `/book/success`, `/my` and `/cancel`, not the API.

**The web sweep refuted this endpoint 1–2. The sweep was wrong.** From the
bundle:

```js
o="https://mizano.ge/api"
fetch(`${o}/courts/slots/stream?date=${encodeURIComponent(t)}`)      // SSE, backs off 30 s on 429
"SLOT_STATUS",{AVAILABLE:0,OCCUPIED:1,BLOCKED:2,HELD:3}
fetch("https://mizano.ge/api/courts/pricing")
```

`GET https://mizano.ge/api/courts/slots?date=2026-10-14`, no auth, 200,
`application/json`:

```json
[{"courtId":1,"hour":8,"status":1},{"courtId":1,"hour":8.5,"status":1}, …
 {"courtId":1,"hour":11,"status":0}, … {"courtId":2,"hour":20,"status":0},{"courtId":2,"hour":21,"status":1}, …]
```

- Two courts, half-hour cells from 08:00 to 23:30. `status` 0 means free, and
  3 (`HELD`) is somebody at checkout.
- The minimum booking is an hour ("Minimum 1 hour — select an adjacent
  slot"), so an hour start is free only when both `h` and `h+0.5` are 0.
- The client shows a "Too many requests" toast on 429 and the stream backs
  off. Rate limiting exists, but the limit itself is **UNVERIFIED**, and so
  is the 14-day horizon (taken from the date strip).
- Real demand here too: the evening of 2026-10-14 was mostly status 1.

**Verdict:** court-level, readable, and the SSE stream is there if polling
ever gets too slow.

---

## Vake Park Tennis Courts — youthtbilisi.ge

Municipal, run by the Tbilisi Sports and Youth Center. The front end is
Next.js pages-router, the API is `https://api.youthtbilisi.ge/api`.
`robots.txt` is Cloudflare's content-signals boilerplate.

From the bundle:

```js
get({url:"/v1/services/".concat(t)})
get({url:"/v1/hours",params:{sports_center_item_id:t,service_item_id:i,reservation_date:r}})
```

`GET /v1/services/17` (17 is the `center_id` in the page URL):

```
item_id 43 "Courts reservation" · 51 "Tennis court N2" · 53 "Tennis court N3" · 55 "Mini court"
```

`GET /v1/hours?sports_center_item_id=17&service_item_id=51&reservation_date=2026-10-14`:

```json
{"data":[{"id":55,"start_hour":"23:00","end_hour":"00:00","cost":45,"is_bookable":true}],"holidays":[]}
```

Swept over D+1, D+3, D+6 and D+10:

- 51 (N2): only 23:00, every day.
- 55 (Mini court): 07–10 and 20–23, 25 ₾, every day.
- 43 and 53 (N3): `[]` every day. Court N1 is not a service at all.

The same answer every day means the city sells only a fixed sliver online,
and the rest goes to schools and lessons. Whether a booked hour disappears
from `data` or flips `is_bookable` to false is **UNVERIFIED**, because no
booked hour was seen.

**Verdict:** readable but nearly worthless. A watcher would see one late
hour on one court. Keep for later.

---

## PadelHub — pickleball

Already adapted. The Supabase court list we read every tick has a fourth
active row:

```json
{"id":"154545c2-e962-4d85-8e1a-9bf5bcfa4721","name":"court_pickleball","sport_type":"pickleball","is_active":true}
```

`rpc/get_booking_availability` answers for it exactly as it does for the
padel courts: `[]` (nothing taken) on 13, 14 and 15 October.
`Adapters::Padelhub::SPORT = "padel"` is the only thing keeping it out.

## Love Padel — pickleball

Already adapted. `GET https://api.bookandgo.app/api/v1/apps/126/court-bookings?date=2026-10-14`,
60-minute variants:

```
Padel      location 246  2 courts  59 free starts
Pickleball location 246  2 courts  32 free starts
```

`Bookandgo#padel?` drops it. Tenant 58 (Padelbade) has no pickleball.

---

## ProSpin — booking.prospin.ge

A Vite/React app. Its `API_URL` is pinned to
`https://prospin-api-194894830109.europe-central2.run.app` (the bundle's
allowlist also names `api.prospin.ge`, which has no DNS from here). Firebase
handles auth.

```
GET …run.app/tables                                → 401 {"detail":{"error":"Authentication required","code":"auth_required"}}
GET …run.app/tables/availability?date=2026-10-14   → 401 same
```

**Verdict:** excluded. Availability sits behind a login, and by
[ADR-0004](../adr/0004-robots-txt-is-not-a-refusal-a-login-is.md) a login is a
closed door.

---

## MZE Pickleball — book.mzepickleball.com

"Georgia's first dedicated pickleball club", at Saburtalo and Dighomi. The
marketing site is Webflow and embeds `book.mzepickleball.com/mze-embed.js`,
a members' booking app. The iOS app is *MZE PICKLEBALL* by Sonriente LLC,
v2.0.6.

The court list and opening hours are not readable anonymously, so there is no
grid to subtract bookings from.

**Verdict:** excluded. Nothing here is an anonymous visitor's view of the
schedule.

---

## What it adds up to

Against what `config/clubs.yml` already watches:

| Sport | New readable venues | Courts | Through |
|---|---|---|---|
| Tennis | 6: Leila Meskhi ×3, Tokhadze, Nutsubidze, Lisi (+ Vake Park, barely) | 11 (+3) | Gamo, own API (+ youthtbilisi) |
| Pickleball | 2, both already fetched | 3 | Padelhub and Bookandgo, filter only |
| Squash | 1: LeaderSport Arena | 2 | Gamo |
| Badminton | 1: Mizano | 2 | own API |
| Table tennis | 1: Lebowski East Point | 1 | Gamo |
| Padel | 0. Gamo's PadelHiggs is our Higgs | — | — |

That is three new adapters (`gamo`, `lisi`, `mizano`) plus two filters
loosened, giving 11 venues and about 19 courts. The blocker is in the domain,
not in the sources: a Club has no sport today.
