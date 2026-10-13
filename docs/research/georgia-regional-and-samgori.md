# AIA Padel, Sportscape Samgori, Grand Padel Batumi, Dunlop Batumi — recon

Four clubs nobody had examined, looked at on 2026-10-13 between 23:00 and
23:15 Tbilisi time (19:00–19:15 UTC). "Today" in the samples is
2026-10-13. Every endpoint below was called live; the samples are literal
excerpts. Anything not confirmed by a live call or a line of the club's own
bundle is marked **UNVERIFIED**.

| Club | City | Courts | System | Auth | Verdict |
|---|---|---|---|---|---|
| [AIA Padel](#aia-padel--aiapadelge) | Kutaisi | 4 (3 active) | own Next.js + JSON API | none for reads | **Adapted** — `aiapadel` |
| [Sportscape Samgori](#sportscape-samgori) | Tbilisi | 4 | — | — | **No online booking found** |
| [Grand Padel Batumi](#grand-padel-batumi--reservio) | Batumi | 2 | Reservio | none | **Excluded: `api.reservio.com/robots.txt` disallows everything** |
| [Dunlop Batumi](#dunlop-batumi--tennisbatumicom) | Batumi | 1 | — (WhatsApp) | — | **No online booking** |

## Where the booking links come from

The four profiles on sapadelo.com (`/georgia/clubs/<slug>`; its `robots.txt`
disallows only `/admin`, `/owner` and `/api`) carry each club's links in the
React Server Components payload. Literal fields, unescaped:

```
aia-padel-club      "bookingHref":"https://aiapadel.ge/book?utm_source=sapadelo…"
                    "websiteHref":"https://aiapadel.ge/?utm_source=sapadelo…"
sportscape-padel    (no bookingHref key at all)  "phone":null,"email":null,"websiteHref":null,
                    "instagramHandle":"sportscape_padel"
grand-padel-batumi  "bookingHref":"https://grandpadelbatumi.reservio.com/?utm_source=sapadelo…"
                    "websiteHref":null
dunlop-batumi       "bookingHref":null,"whatsappHref":"https://wa.me/995599386571",
                    "websiteHref":"https://tennisbatumi.com/?utm_source=sapadelo…"
```

Court counts, hours and prices sapadelo lists for each, from the same
payload (`courts[]`, `defaultHours`, `pricingRules[]`):

| Club | Courts (cover) | `defaultHours` | Prices (GEL / 60 min) |
|---|---|---|---|
| AIA Padel | 1–2 `canopy`, 3–4 `outdoor` | 08:00–01:00 | none listed |
| Sportscape | 1–4 `outdoor` | 07:00–02:00 | 80 flat |
| Grand Padel | 2 `outdoor` | 09:00–02:00 | 65; 50 for 09:00–13:00; 80 for 17:00–02:00 |
| Dunlop | 1 `outdoor` | 08:00–00:00 | 40; 35 for 12:00–16:00; 55 for 16:00–00:00 |

---

## AIA Padel — aiapadel.ge

The brief said "Next.js + NextAuth". It is Next.js, but **not NextAuth**:
`/api/auth/session` and `/api/auth/providers` are 404, and no bundle chunk
mentions `next-auth`. The site talks to a separate JSON API with its own
phone + OTP accounts and bearer tokens.

### 1. Rendering

`GET https://aiapadel.ge/book` → 200, `server: cloudflare`,
`x-powered-by: Next.js`, `x-nf-request-id` (Netlify). The page is a
client-rendered shell; its only text is `Book a court — AIA Padel Club … Book
Now Loading…`. `https://aiapadel.ge/robots.txt` is a 404 (the Next.js
not-found page), so no robots rules exist for the site.

### 2. The API and where the auth boundary is

Chunk `/_next/static/chunks/26t928g7qtmv9.js` holds the API client, literally:

```js
let d="https://api.aiapadel.ge/v1",f="en";
function p(e){return{"Content-Type":"application/json","X-Client":"consumer",
  "Accept-Language":f,...e?{Authorization:`Bearer ${e}`}:{}}}
async function w(e,t={},n=!1){let r,{auth:i="none",...a}=t; …
  r=await fetch(`${d}${e}`,{...a,headers:{...p("required"===i?o():null),...t.headers}})
```

A bearer goes out only when a call passes `auth:"required"`. The exports from
the same module:

```js
"getAvailableDays",0,function(){return w("/bookings/availability/days")},
"getAvailableSlots",0,T,   // T = w(`/bookings/availability/slots${S({date:t,courtId:e,durationMinutes:n})}`)
"listCourts",0,function(e){return w(`/catalog/courts${S({date:e})}`)},
"getProfile",0,function(){return w("/me",{auth:"required"})},
"createBooking",0,function(e){return w("/bookings",{method:"POST",auth:"required",…})},
```

So the three reads the booking page opens with are deliberately
unauthenticated, and everything personal is not. Confirmed live:

```
GET /v1/me             (X-Client + Accept-Language, no bearer) → 401 {"code":"unauthorized","message":"Missing, invalid, or expired credentials."}
GET /v1/me/bookings    → 401 (same)
GET /v1/bookings/x     → 401 (same)
```

`https://api.aiapadel.ge/robots.txt` → 404 `{"code":"not_found",…}` (`via:
1.1 Caddy`), so no robots rules on the API host either.

**Two headers are mandatory**, and both are constants in the bundle:

```
GET /v1/catalog/courts                       (no headers)       → 400 {"code":"missing_header","message":"Missing X-Client header."}
GET /v1/me                                   (X-Client only)    → 400 {"code":"missing_header","message":"Missing Accept-Language header."}
```

Rate limit, from the response headers: `x-ratelimit-limit: 100`,
`x-ratelimit-reset: 17`. The window length is **UNVERIFIED** (the reset
counter suggests a minute).

### 3. The three reads

**Bookable dates** — `GET /v1/bookings/availability/days` → 200:

```json
[{"date":"2026-10-13","isAvailable":true},{"date":"2026-10-14","isAvailable":true}, … ,
 {"date":"2026-10-22","isAvailable":true}]
```

Ten dates, today included. The page uses `isAvailable` to disable a date
chip (`disabled:!n.isAvailable` in `26g7_o_--p449.js`).

**Courts** — `GET /v1/catalog/courts?date=2026-10-14` (identical without
`date`):

```json
[{"id":"c0000000-0000-4000-8000-000000000001","name":"Court 1","hasRoof":false,
  "durations":[{"durationMinutes":60,"label":"1 hour","price":6000},
               {"durationMinutes":90,"label":"1.5 hours","price":9000},
               {"durationMinutes":120,"label":"2 hours","price":12000}],"isActive":true, …},
 {"id":"…0002","name":"Court 2","hasRoof":false, … "isActive":true},
 {"id":"…0003","name":"Court 3","hasRoof":true,  … "isActive":true},
 {"id":"…0004","name":"Court 4","hasRoof":true,  … "isActive":false}]
```

Prices are in tetri: 6000 = 60 GEL an hour on every court. Court 4 is
inactive, and the slots route refuses it:

```
GET …/slots?date=2026-10-13&courtId=…0004&durationMinutes=60
→ 400 {"code":"invalid_parameter","message":"This court is not available for booking right now."}
```

Sapadelo disagrees about the roofs: it lists courts 1–2 as `canopy` and
3–4 as `outdoor`, while the club's own API says `hasRoof:true` for 3–4. The
API is the club's own word. Which one is right is **UNVERIFIED**.

**Starts** — `GET /v1/bookings/availability/slots?date=2026-10-13&courtId=…0001&durationMinutes=60`,
called at 23:04 local:

```json
{"date":"2026-10-13","slots":[{"startTime":"09:00","isAvailable":false},
 {"startTime":"09:30","isAvailable":false}, … ,{"startTime":"23:00","isAvailable":false},
 {"startTime":"23:30","isAvailable":true},{"startTime":"00:00","isAvailable":true}]}
```

All three parameters are required (`"courtId, date and durationMinutes are
required."`), and a duration off the court's list is refused (`45` →
`"durationMinutes must be one of the offered session lengths."`). So a tick
costs one request per active court per date, plus the two lists: **32
requests** at 3 courts × 10 dates.

### 4. Reading it

- **Free-flagged, not free-only.** Every start is listed with an explicit
  `isAvailable`, so there is nothing to invert. Half-hour starts are listed
  too, and are dropped for the usual reason (the Grid matches on the hour).
- **`00:00` is tonight's midnight.** It comes last, after `23:30`, and at
  23:04 on the 13th it read `true` while `23:00` read `false`. If it meant
  the 13th's own 00:00, it would be long gone and flagged as such. The
  client's `endTimeOf` wraps at `%1440`, the same reading. So the source
  speaks in business-day labels, which is what `OpeningHours#starts_by_label`
  reads.
- **Opening hours: 09:00 to a last start at 00:00**, on every date sampled.
  Sapadelo says 08:00; the source never offers an 08:00.
- **Gone hours are only flagged today.** At 23:04 the 13th's 09:00–23:00
  read `false` on all three courts at once. But the 12th, already over,
  answers with every hour `true`, and so does 2026-12-30, past the ten-date
  window. So the adapter drops past starts against the clock itself, and asks
  only for the dates `/days` lists.
- **A booking is not observed.** Ten dates × three courts were all free
  from 2026-10-14 onwards, so no future start was ever seen as `false`.
  That a booking flips `isAvailable` is **UNVERIFIED**, but it is the only
  reading of the field the client supports: it disables the time chip with
  `disabled:!e.isAvailable` and counts `I.filter(e=>e.isAvailable).length`
  as "slots available". Court ids of the form `c0000000-…-000000000001` look
  hand-seeded, and the club may simply be new. Watch the first week of polls
  before trusting a quiet log.
- **Deeplink: none.** The booking page restores a half-finished choice from
  `sessionStorage` (`aia_booking_draft`) and reads nothing from its URL, so
  the static `https://aiapadel.ge/book` is the link.
- **Never call** `POST /v1/bookings`. It needs a bearer and starts a card
  payment (`paymentMethod:"link"`, then a redirect to `payment.clientSecret`).

### 5. What was built

`lib/booking/adapters/aiapadel.rb`, registered as `aiapadel`; config entry
`aia-padel` (`city: Kutaisi`, 09:00–01:00, `max_days: 10`, `courts: 3`,
60 GEL). Live run at 23:11 local: **435 free slots** in 14.3 s. That is 9 full
dates × 3 courts × 16 hours, plus tonight's 00:00 on each court. Fixture
`spec/fixtures/aiapadel_availability.json` is the responses above, recorded
at 23:05.

---

## Sportscape Samgori

**No booking channel published anywhere we can read.**

- Its sapadelo profile has no `bookingHref` key at all, and `"phone":null,
  "email":null,"websiteHref":null`. The only contact is
  `"instagramHandle":"sportscape_padel"`. Address `37 Mikheil Abramishvili
  st`, Tbilisi.
- Every guessed domain is NXDOMAIN, per `dns.google/resolve`: `sportscape.ge`,
  `www.sportscape.ge`, `sportscapepadel.ge`, `sportscape-padel.ge`,
  `sportscape.com.ge`, `sportscapepadel.com` all return `"Status":3`.
- Two web searches (`Sportscape padel Samgori Tbilisi booking`,
  `"sportscape" padel Tbilisi`) returned nothing about the club.
- Instagram needs a login to read, which is out of bounds. Whether its bio
  links to a booking system is **UNVERIFIED**.

Under the plan's rule that a club with no online booking is not shown,
Sportscape stays out. Re-check sapadelo's profile when it next gains a
`bookingHref`.

---

## Grand Padel Batumi — Reservio

**Excluded on robots.txt.** The booking link is
`https://grandpadelbatumi.reservio.com/`, a stock Reservio page
(`"businessId":"aac3b1f5-7e80-4052-bd09-adc7396cfbec"` in its HTML). The page
host's `robots.txt` disallows `/api/`, `/booking`, `/order` and the
staff/service/event detail paths. The data, though, lives on the API host,
and that one refuses everything:

```
GET https://api.reservio.com/robots.txt  → 200 text/plain
User-agent: *
Disallow: /
```

That is the rule that excluded Padel Island, and Padel Gldani once its own
`robots.txt` gained `Disallow: /api/`, so nothing here reads it. The same file governs **every** Reservio club,
including the Padel Port pair in Batumi that `docs/coverage-plan.md` lists
as "verified live" and technically ready. That plan entry should be
re-decided.

What the API looked like, for the record. These calls were made in this recon
before the robots rule was applied to them, and nothing in the repo reads
them:

- **Six services, six resources, two courts.** Each court is split into
  three price bands, and each band is its own service *and* its own resource:

  ```
  SVC adcd4ab2-…  Court A-(08:00-13:00)  50.00     RES 408fddbc-…  Court A- 50 Gel
  SVC 8f38cc70-…  Court A-(13:00-17:00)  65.00     RES 242d0df6-…  Court A - 65 Gel
  SVC 77bc9810-…  Court A-(17:00-02:00)  80.00     RES 687ce25c-…  Court A- 80 Gel
  SVC 972672c5-…  Court B-(08:00-13:00)  50.00     RES 78060f65-…  Court B- 50 Gel
  SVC 896c724c-…  Court B-(13:00-17:00)  65.00     RES 61acffdf-…  Court B- 65 Gel
  SVC 9813ae70-…  Court B-(17:00-02:00)  80.00     RES cd72f9a6-…  Court B-80 Gel
  ```

  Reading it would need `service_ids` as a list (one request each:
  `filter[serviceId]` with two comma-separated ids is
  `400 Invalid UUID string`, and leaving it out is `404`). It would also
  need `court_aliases` to fold three resource ids into each physical court.
- **Window.** Business settings say `"reservationsLaterThan":604800` (7 days)
  and `"reservationsInAdvance":300` (5 minutes' notice), and slots stopped at
  2026-10-20 when asked to 2027-01-31. Bookings need the club's confirmation
  (`"reservationsManualConfirmation":true`).
- Hours 08:00–02:00, from the page's `OpeningHours` blocks (`start:28800,
  end:86340` plus `start:0, end:7200` on each weekday sampled).

If Grand Padel matters, the move is to ask Reservio or the club. The Reservio
adapter and the `discover:reservio` task already exist.

---

## Dunlop Batumi — tennisbatumi.com

**No online booking.** `https://tennisbatumi.com/` is a page built and
hosted on Gamma (`server: gamma`, assets from `assets.gammahosted.com`,
`<title>Gamma</title>` in the shell; `robots.txt` is a 404 HTML page). It is
one Russian-language landing page for a tennis club with one padel court:
"Dunlop Club Batumi — Теннисный и падел-корт", "₾55 / час".

Every booking button on it is a WhatsApp link. Anchors and their text,
literal:

```
https://wa.me/+995599386571 | Забронировать корт      ("Book a court")
https://wa.me/995599386571  | Забронировать сейчас    ("Book now")
https://wa.me/995599386571  | Забронировать
https://wa.me/995599386571  | Записаться бесплатно    ("Sign up free")
```

There is no other outbound link apart from Gamma's own CDNs. The page's
"Онлайн-бронирование 24/7" promise is qualified in the same sentence:
"(Только для жителей Ande Tower 2)", i.e. only for residents of one
building. No such platform is linked from the page. Not shown, by the same
rule as Sportscape.

---

## Sources

- `https://sapadelo.com/georgia/clubs/{aia-padel-club,sportscape-padel,grand-padel-batumi,dunlop-batumi}`,
  `https://sapadelo.com/ka/georgia/clubs`, `https://sapadelo.com/robots.txt`
- `https://aiapadel.ge/book`, `/robots.txt`, `/api/auth/session`,
  `/_next/static/chunks/26t928g7qtmv9.js` (API client),
  `/_next/static/chunks/26g7_o_--p449.js` (booking page)
- `https://api.aiapadel.ge/v1/bookings/availability/days`,
  `/v1/catalog/courts`, `/v1/bookings/availability/slots`, `/v1/me`,
  `/robots.txt`
- `https://grandpadelbatumi.reservio.com/` and `/robots.txt`,
  `https://api.reservio.com/robots.txt`
- `https://tennisbatumi.com/` and `/robots.txt`
- `https://dns.google/resolve?name=<candidate>&type=A` for the Sportscape
  domains
