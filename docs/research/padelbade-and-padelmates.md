# Padelbade (Book & Go) and "Padel Mates" — API recon

Investigated 2026-07-30/31 (Asia/Tbilisi). Every claim below is traced to a live HTTP
response or to a JavaScript bundle downloaded from the vendor's own origin. Claims I
could not verify against a primary source are labelled **UNVERIFIED**.

Method: fetch the SPA shell, extract `<script src>`, download the bundles, grep for API
hosts and endpoint paths, then replay the calls with `curl`. No browser, no auth bypass,
no crawling of robots-disallowed paths.

---

## Headline correction before anything else

**Target B in the brief is misidentified.** `booking.padelisland.ge` is not Padel Mates.
It is **TPC MatchPoint**, a Spanish ASP.NET club-management product. Padel Mates is a
real platform with a clean, unauthenticated availability API — but **it has no Georgian
club at all**. Evidence for both statements is in section B.

So the three sections below are:

- **A. Book & Go / Padelbade** — solved end to end. Easy.
- **B1. Padel Mates** — solved end to end, but irrelevant to Georgia today.
- **B2. TPC MatchPoint (the platform Padel Island actually runs)** — blocked. Hard.
  **Wrong — re-probed 2026-10-14 (B2.4): the grid is public and reads as JSON. Easy.**

---

## A. Book & Go / Padelbade

### A.0 How the host was found

`https://app.padelbade.com/` is a **Flutter web** PWA, not a JS SPA. The shell
(fetched 2026-07-30) contains a Firebase config (`projectId: padel-art-2`) and loads
`flutter_bootstrap.js`, which loads `main.dart.js` (1.32 MB).

Grepping `https://app.padelbade.com/main.dart.js` for absolute URLs yields exactly four
first-party hosts:

```
https://api.bookandgo.app/api/v1/apps/58/          <- REST base (string constant u.M)
https://chat.bookandgo.app/websocket/club/58/      <- socket.io chat
https://share.bookandgo.app/padelbade/<kind>/<id>  <- share/deeplink interstitials
https://bookandgo.sgp1.digitaloceanspaces.com/     <- image CDN
```

The request builder in the same bundle:

```js
m = c.f ? "https://api.bookandgo.app/api/v1/apps/" + c.rm(0,a1) : u.M + c.rm(0,a1)
...
if (c.e && a3 != null) J.bb(k, "Authorization", "Bearer " + a3)
```

`u.M` is the literal `"https://api.bookandgo.app/api/v1/apps/58/"`. `c.e` is the
endpoint's *auth-required* flag, so a bearer token is attached **only** for endpoints
that declare it. The endpoint table is a list of `A.ce(path, expectedStatus, authRequired, …, name)`
constants; the two that matter are:

```js
B.NS = new A.ce("locations",      200, !1, !1, !1,  2, "locations")      // auth = false
B.O1 = new A.ce("court-bookings", 200, !1, !1, !1,  3, "courtBooking")   // auth = false
B.O8 = new A.ce("court-bookings", 200, !0, !1, !1,  4, "courtBookingPost") // auth = true (POST)
```

And the availability call site, showing the only query parameter:

```js
k = A.aT("yyyy-MM-dd", null).aJ(e)          // selected date
J.IF(n, a, B.O1, A.ac(["date", k], t.N, t.z), l)   // l = token, unused because auth=false
```

Source: `https://app.padelbade.com/` and `https://app.padelbade.com/main.dart.js`.

### A.1 API host and availability endpoint

| | |
|---|---|
| Host | `https://api.bookandgo.app` |
| Tenant prefix | `/api/v1/apps/58/` (`58` = the Padelbade tenant) |
| Availability | `GET /api/v1/apps/58/court-bookings?date=YYYY-MM-DD` |
| Club catalogue | `GET /api/v1/apps/58/locations` |
| Content type | JSON; `Content-Type: application/json` request header is what the app sends, not required |

Verified live:

```
$ curl "https://api.bookandgo.app/api/v1/apps/58/court-bookings?date=2026-08-02"
200, 21693 bytes
```

`robots.txt` on `api.bookandgo.app` is Cloudflare's content-signals boilerplate with
**no `User-agent`/`Disallow` directives** — nothing is disallowed.
`app.padelbade.com/robots.txt` returns the SPA shell (no robots file), so also nothing
disallowed.

### A.2 Authentication

**None required for reading availability.** Both `locations` and `court-bookings` (GET)
carry `authRequired = false` in the bundle's endpoint table, and both returned `200` with
full data over plain `curl` with no cookie, no token, no session mint, no nonce. Only
mutations (`POST court-bookings`, `users/*`, `payments/*`) set the flag and get an
`Authorization: Bearer <firebase-id-token>` header.

One authenticated-only field exists in the availability payload: `mine_time_slots`, which
is `[]` for an anonymous caller. Ignore it.

### A.3 Tenant and club identification

Tenant = the numeric **app id in the path** (`apps/58`). Clubs are **`location_id`s**
inside that tenant. From `GET /api/v1/apps/58/locations` (live, 2026-07-30):

| location_id | `location_name` | sport_id | courts (`court_id` → `court_name`) | horizon (days) |
|---|---|---|---|---|
| **163** | `Tbilisi, krtsanisi ` (trailing space) | 347 | 703 `Blue 1`, 704 `Blue 2`, 705 `Blue 3`, 706 `CROCOBET.COM COURT (Black 1)`, 707 `CROCOSHOP COURT (Black 2)` | 703→29, 704→30, 705/706/707→22 |
| **141** | `Tbilisi, Dighomi` | 227 | 480 `Brick Red (Road Side)`, 481 `Green (Wall Side)` | 14 |
| **142** | `Rustavi, Crocobet Courts` | 232 | 486 `Crocobet.com Court`, 487 `Crocoshop Court` | 14 |

Court names come from the `court-bookings` response; `/locations` gives only court ids
plus `app_bookable_days_in_future`. Currency `GEL` for all three. Geo coords are present
(`georeferenced`).

Duration variants (`booking_id`, minutes, price GEL) — these are *separate rows* in the
availability response, not a filter:

- 163 Krtsanisi: 559/60/80, 560/90/120, 561/120/160
- 141 Dighomi: 355/60/80, 360/90/120, 368/120/160
- 142 Rustavi: 365/60/60, 366/90/90, 367/120/120

### A.4 Response shape — free-only, per court, per duration

```
data.locations_window[<location_id>] = { is_open, club_timezone, next_open_at_utc, locked_date, rolling_release }
data.bookings[] = {
  id: <booking/duration-variant id>, duration: 60|90|120, price, open_match_price, …,
  sport:    { id, sport_name, is_open_match },
  location: { id, location_name, currency, courts: [
      { id, court_name, timings: [
          { date: "2026-08-02", start_time: "00:00:00", end_time: "24:00:00",
            available_time_slots: ["08:00:00","08:30:00", …],   // FREE start times only
            mine_time_slots: [] }
      ]}
  ]}
}
```

- **Free slots only.** `available_time_slots` is a whitelist of bookable start times.
  There is no status flag and no listing of taken slots — a booked hour simply vanishes
  from the array. (Cross-checked: Krtsanisi court 704 had 33 free 60-min starts on
  2026-08-20 and only 21 on 2026-07-31.)
- **Per court**, not per hour. `court_id` is a stable integer → good `court_ref`;
  `court_name` → `court_label`.
- **Granularity 30 min** (`:00` and `:30` starts), for each of the three durations.
- **One request covers all three Georgian clubs.** The endpoint takes only `date`; it
  returns every location of app 58. That is a gift for the adapter: one HTTP call per
  date, then partition by `location_id`.
- **Timezone is given**: `data.locations_window["163"].club_timezone == "Asia/Tbilisi"`.
  Slot times are wall-clock local strings, so `starts_at` = `date` + `start_time` in
  `club_timezone`, `ends_at` = `starts_at + duration` minutes.
- **Past times are NOT filtered server-side.** Verified: at 02:09 local (Tbilisi,
  2026-07-31) the response for `date=2026-07-31` still listed `00:00:00` and `00:30:00`
  as available on Dighomi court 480. The adapter must drop slots already in the past.
  (Consistent with the bundle, which does the filtering client-side.)
- **UNVERIFIED:** whether `court-bookings` accepts a `location_id` or `sport_id` filter.
  The bundle only ever sends `date`, so I did not probe for undocumented parameters.

### A.5 Booking horizon

Two independent, agreeing sources:

1. Declared: `app_bookable_days_in_future` per court in `/locations` (see table above) —
   14 days for Dighomi and Rustavi, 22–30 for Krtsanisi.
2. Observed: the API itself enforces it and simply omits out-of-window clubs.

| requested date | days out | locations present in `data.bookings` |
|---|---|---|
| 2026-07-31 | 0 | 141, 142, 163 |
| 2026-08-02 | 2 | 141, 142, 163 |
| 2026-08-20 | 20 | **163 only** |
| 2026-09-15 | 46 | **none** (`data.bookings` empty, still `status: success`) |

So, unlike GymBreeze, no `max_days` guard is strictly needed — an out-of-range date
returns an empty booking list rather than phantom free slots. Still worth capping at ~30
days to avoid pointless requests.

### A.6 Deeplink

**There is no per-club/per-date/per-time deeplink.** The Flutter router's full route
table (from the bundle) is:

```
/home  /auth  /sign_in  /sign_up  /notifications  /chat  /purchase  /show_image
/booking_info/:booking_id  /event_info/:id  /lesson_info/:id  /match_info/:id
/ranking_profile/:id  /flitt_web_view/:url  /splashWithTransactionId/:transId
```

The `:id` routes all address an *existing* booking/match, not a prospective one. The
inbound deeplink handler accepts either one path segment (`events|matches|lessons|bookings|coaches`,
which just selects a tab on `/home`) or exactly three (`.../booking_info/<id>` etc.).

Best available deeplink for a notification:

- `https://app.padelbade.com/` — lands on `/#/home`; the user then picks club, date, time.
- `https://share.bookandgo.app/padelbade/bookings` — verified `200 text/html`
  (Railway-hosted interstitial); per the bundle this opens the app on the bookings tab.
  Which tab exactly is **UNVERIFIED** by HTTP (it is a client-side branch).

Recommendation: store a static `booking_url` per club in club settings, exactly as the
GymBreeze adapter already does.

### A.7 Adapter sketch

One `GET https://api.bookandgo.app/api/v1/apps/58/court-bookings?date=<d>` per day in the
range. For each `data.bookings[]` row whose `location.id` matches the club's configured
`location_id` **and** whose `duration` matches the configured duration (probably 60 or
90 — otherwise you emit 3 overlapping slots per court per time), walk
`location.courts[].timings[].available_time_slots` and emit:

- `court_ref` = `court.id` (int, stable)
- `court_label` = `court.court_name`
- `starts_at` = `Time.parse("#{timing.date} #{slot}")` in `club_timezone`
- `ends_at` = `starts_at + duration * 60`
- `price` = `booking.price` (GEL)
- `deeplink` = configured static URL

Then drop anything `<= Time.now`. Difficulty: **easy** — comparable to GymBreeze, with
the bonus of real per-court identity.

---

## B1. Padel Mates — real API, no Georgian clubs

### B1.0 The `activity.padelmates.io` dead end

`https://activity.padelmates.io/` (robots.txt: `User-agent: *` / `Disallow:` — everything
allowed) is a Netlify-hosted React shell whose only bundle,
`/static/js/main.02994d49.js` (67 KB), contains **no API host at all** — its only
first-party URLs are the App Store and Play Store listings. It is an "open the app"
landing page, not the booking client.

### B1.1 The real client and API hosts

`https://padelmates.se/` is the actual web client (also React, 656-byte shell, one
bundle `/static/js/main.60d5bcda.js`, 2.9 MB). Its inlined `REACT_APP_*` env block:

```js
REACT_APP_AXIOS_API:      "https://nestjs-production-fargate.padelmates.io/"
REACT_APP_AXIOS_FAST_API: "https://fastapi-production-fargate.padelmates.io/"
REACT_APP_FIREBASE_API_KEY: "AIzaSyCTllK1OKm-YRcEeKXEc2KNcPtmZFZrqIk"
```

Two axios instances, two auth schemes:

```js
Ub = axios.create({ baseURL: "https://nestjs-production-fargate.padelmates.io/" });
Ub.interceptors.request.use(async e => { const t = getAuth().currentUser;
  if (t) e.headers.authorization = `PadelMates ${await t.getIdToken()}`; return e; });

Yb = axios.create({ baseURL: "https://fastapi-production-fargate.padelmates.io/" });
Yb.interceptors.request.use(async e => { const t = getAuth().currentUser;
  if (t) e.headers.authorization = `Bearer ${await t.getIdToken()}`; return e; });
```

Note the `if (t)` — the header is attached **only when a Firebase user is signed in**.
Anonymous calls simply omit it, which is why they work.

### B1.2 Availability endpoint

From the bundle:

```js
mM = async (e, t, n) => (await $b.get("/player/player_booking/all_courts_slot_prices_v2",
        { params: { club_id: e, start_datetime: t, end_datetime: n } })).data
```

`start_datetime` / `end_datetime` are **epoch milliseconds**, built by:

```js
lM = (e,t,n) => moment.tz(`${e.format("YYYY-MM-DD")} ${moment(t,"HH:mm").format("HH:mm")}`, n).utc().valueOf()
cM = (e,t) => ({ startTime: lM(e,"00:00",t), endTime: lM(e,"23:59:59",t) })   // n = club timezone
```

Verified live, **unauthenticated**:

```
GET https://fastapi-production-fargate.padelmates.io/player/player_booking/all_courts_slot_prices_v2
    ?club_id=7b1970286727418dbc8c18590d9f3d09&start_datetime=1785531600000&end_datetime=1785617999000
→ 200, 44208 bytes
```

Response:

```
{ allSlots: [ { courtName, courtId, slotId, duration, price, discountedPrice,
                startDatetime: "2026-08-01T06:00:00+00:00", endDatetime: "…",
                startTime: "06:00", endTime: "07:00",
                startTimestamp, endTimestamp,
                reservedIntersection: false, ableToBookOpenMatch, … } ],
  uniqueStartTimes: [ms…], originalCourts: [ {name, club_id, sport, indoor, double, …} ],
  reservedBookings: [], allowed_activity_join, activity_join_messages, disallowed_cards }
```

- **Free slots only** in practice: in the sample all 65 `allSlots` had
  `reservedIntersection: false`, and taken bookings live in the separate
  `reservedBookings` array. Whether `allSlots` can ever contain a `true` row on a busier
  club is **UNVERIFIED**.
- **Per court** (`courtId` is a Mongo ObjectId string — stable ref; `courtName` — label),
  and **per duration** (60/90/120 all present simultaneously).
- **Absolute ISO 8601 with `+00:00` offset** in `startDatetime`/`endDatetime`, plus
  epoch-ms — no timezone guessing needed. Club `timezone` also comes from the club record.
- The window is caller-chosen, so the "horizon" is whatever the backend still returns
  slots for. **UNVERIFIED** — I did not probe far-future windows, since no Georgian club
  uses this platform.

Other unauthenticated-looking endpoints in the bundle:
`GET /club/?club_id=…`, `GET /club/club_extras`, `GET /club/creditpackage/?club_id=…`,
`GET /club/membership/get_all_memberships?club_id=…&guest_user=true`,
`GET webportal/getClubActivityRecordsWithoutAuth/<id>`.

### B1.3 Tenant identification, and the Georgia result

Clubs are 32-hex-character `_id`s, plus a `short_name` slug used in the web URL
(`https://padelmates.se/club/<short_name || _id>`).

Discovery endpoint (from the bundle, verified live, unauthenticated):

```
POST https://fastapi-production-fargate.padelmates.io/player/player_booking/v2/search_nearby_clubs
     ?player_id=&search_club_name=&latitude=41.7151&longitude=44.8271
     &limit_for_registered=250&limit_for_non_registered=0&skip_for_registered=0
body: {"sport":[],"court_type":[]}
```

Centred on Tbilisi (41.7151, 44.8271), the API reports `total_clubs: 309`. I pulled all
309 across two pages (`skip_for_registered=0` and `250`) and inspected every record:

- **Zero clubs with `country: "Georgia"`. Zero with a `city` containing "Tbilis".
  Zero whose `name` contains island / lisi / expo / gudauri / kachreti / tbilisi / georgia.**
- Country distribution: Sweden 85, United Kingdom 90, Norway 25, Denmark 20, Zambia 16,
  Kuwait 11, UAE 8, Oman 6, Vietnam 5, Singapore 4, …

Corroborating: `https://padelisland.ge/` contains **no** occurrence of "padelmates" or
"padel mates" anywhere in its HTML.

**Conclusion: Padel Mates has no presence in Georgia.** The platform is easy to read
(unauthenticated, per-court, absolute timestamps) but there is nothing here to watch.
Worth keeping this section as a ready-made recipe in case a Georgian club onboards.

---

## B2. TPC MatchPoint — what `booking.padelisland.ge` actually is

### B2.1 Identification

`https://booking.padelisland.ge/` `302`s to `/Login.aspx`, sets `ASP.NET_SessionId`, and
serves `X-Powered-By: ASP.NET` / `Server: Microsoft-IIS/10.0`. Its `robots.txt` is a
Spanish-commented boilerplate. The login page identifies the vendor unambiguously:

- `<meta name="author" content="TPC-SOFT" />`
- footer links to `https://tpcmatchpoint.com/english`, "Sports Centers Management Software"
- CSS/asset path `PadelIslandGeorgia/css/global.css` — the tenant folder name
- menu link to **`https://padelisland-ge.matchpoint.com.es/classbooking/index.aspx`** —
  the canonical MatchPoint tenant host
- footer app link `https://play.google.com/store/apps/details?id=es.tpc.matchpoint.appclient.padelisland`
- Cloudflare Turnstile on the login form

`https://padelisland.ge/` (a Next.js/Vercel marketing site with no API of its own) links
its "Book" CTA to `http://booking.padelisland.ge/Booking/Grid.aspx`, and its own copy
names the four venues: **Lisi Lake, Expo Park, Gudauri (Marco Polo, Kazbegi), Kachreti
(Golf & Spa Resort)** — i.e. all four brief-listed venues are on MatchPoint.

So: vendor **TPC MatchPoint (TPC-SOFT, Spain)**; tenant slug **`padelisland-ge`**;
canonical host `https://padelisland-ge.matchpoint.com.es`; vanity host
`https://booking.padelisland.ge`.

### B2.2 Blocked — and why I stopped

Both hosts serve the identical `robots.txt`, which for `User-Agent: *` disallows exactly
the paths that carry availability:

```
Disallow: /Booking/        <- Grid.aspx, the court grid
Disallow: /Services/       <- the ASMX/WCF endpoints the grid calls
Disallow: /ActBooking/  /Reservas/  /ClassBooking/  /PoolBooking/  /Matches/
Disallow: /Login.aspx  /Perfil.aspx  /AutentificarUsuario.aspx
```

Sources: `https://booking.padelisland.ge/robots.txt`,
`https://padelisland-ge.matchpoint.com.es/robots.txt`.

I did **not** fetch `/Booking/Grid.aspx` or anything under `/Services/`. On top of the
robots block, the site is login-gated (`/` → `/Login.aspx`) with Turnstile, so reading
availability would also mean holding an account session — which the brief rules out.

There is no client-side JS bundle to mine: this is a classic server-rendered WebForms app
(jQuery 1.7.2, `WebResource.axd`, `__VIEWSTATE`), so the endpoint-extraction technique
that cracked Padelbade does not apply. `sitemap.ashx`, the one thing robots explicitly
permits, `404`s.

### B2.3 If you want to proceed anyway — exactly what to capture

This needs a human decision (it is a robots + auth question, not a technical one). If the
club grants permission, the cheapest path is a single DevTools session:

1. Log in at `https://booking.padelisland.ge/Login.aspx` with a real account.
2. Open DevTools → Network → filter XHR, then navigate to
   `https://booking.padelisland.ge/Booking/Grid.aspx`.
3. Change the date picker and the venue selector once each, and capture:
   - the request URL and method of every XHR fired (expect `POST` to something under
     `/Services/…​.asmx/…` or a `Grid.aspx` `__DOPOSTBACK` with `__VIEWSTATE`),
   - the full request body (is it JSON, or a WebForms postback blob?),
   - the request headers (`Cookie: ASP.NET_SessionId`, `X-Requested-With`, any
     `RequestVerificationToken`),
   - the response body for one date, so the free-vs-taken encoding and the venue/court
     ids can be read off.
4. The decisive question is **whether the grid is a JSON XHR or a full WebForms postback**.
   If JSON + session cookie → a session-holding adapter is feasible (medium). If
   `__VIEWSTATE` postback → the adapter has to replay viewstate, which is brittle enough
   to be a bad idea (hard).

Alternative primary source, if DevTools is not an option: decompile
`es.tpc.matchpoint.appclient.padelisland` from Play and read its Retrofit/OkHttp
interfaces. The app almost certainly speaks a cleaner mobile JSON API than the web grid.
**UNVERIFIED** — I did not download or decompile the APK.

**UNVERIFIED / open:** whether MatchPoint exposes any public, unauthenticated availability
API for its tenants at all. Nothing in the reachable HTML suggests one.

### B2.4 Re-probed 2026-10-14 — the grid is public

B2.2 never fetched the grid; the login it describes is only what `/` redirects
to. Fetched directly, everything below was verified live:

- `GET https://booking.padelisland.ge/Booking/Grid.aspx` answers **200** with no
  cookie and no login, and sets `ASP.NET_SessionId`. The Turnstile is on the
  login form only.
- An inline script sets `hl90njda2b89k='<base64>'` — the `key` the grid's
  `booking/js/ajax.js` (ver 2.9.6) sends on every call — and
  `dateParameters.cuadroCentroMap` lists the venues:
  `{"5":"Marco Polo Gudauri","6":"Lisi Lake Sports Park","7":"Ambassadori Kachreti","8":"EXPO Park Tbilisi"}`.
- `POST /booking/srvc.aspx/ObtenerCuadro`, JSON body
  `{"idCuadro":8,"fecha":"15/10/2026","key":"<key>"}`, answers
  `{"d":{…CuadroReservasNuevo…}}`: per court (`Columnas[]`, `Id`,
  `TextoPrincipal`) the *taken* spans (`Ocupaciones[]`: `StrHoraInicio`,
  `StrHoraFin`, `Tipo` one of `reserva_individual`, `reserva_temporada`,
  `reserva_club`, `bloqueo`), plus the day's own fence
  (`StrHoraAperturaCentro`, `StrHoraCierreCentro`), the bookable window and the
  horizon (`StrFechaMax`: 30 days ahead, 21 at Kachreti). Half-hour grid.
- **It never refuses.** The key is good only with the session cookie it came
  with, and the server also wants `Referer: …/Booking/Grid.aspx`; get either
  wrong, or ask past the horizon, and the answer is still 200 with `Id: 0` and
  no courts. A wrong key does not kill the session. A session was still good
  seven minutes later.
- The `/Date(ms)/` timestamps are serialised on the server's own clock
  (UTC+2, Madrid): 20:00 in Tbilisi came back as 18:00 UTC. Read the `Str*`
  wall-clock strings.
- `Grid.aspx?id=<cuadro>` opens the page on that venue. No date parameter was
  found (`fecha`, `dia`, `date` all ignored).
- Hours the grid declares: EXPO 07:00–02:00, Kachreti 08:00–23:00, Lisi
  00:00–23:59 and Marco Polo 00:00–00:00 (round the clock, on paper).

Under ADR-0004 that is a robots line, not a door, and the four venues are
watched by `lib/booking/adapters/matchpoint.rb`.

---

## Summary table

| | Padelbade (Book & Go) | Padel Mates | Padel Island (TPC MatchPoint) |
|---|---|---|---|
| API host | `api.bookandgo.app` ✅ | `fastapi-production-fargate.padelmates.io` ✅ | `booking.padelisland.ge` ✅ (B2.4) |
| Availability endpoint | `GET /api/v1/apps/58/court-bookings?date=` ✅ | `GET /player/player_booking/all_courts_slot_prices_v2?club_id&start_datetime&end_datetime` ✅ | robots-disallowed `POST /booking/srvc.aspx/ObtenerCuadro` ✅ (B2.4) |
| Auth to read | none ✅ | none ✅ | none — an anonymous session cookie + page key ✅ (B2.4) |
| Tenant id | `apps/58` + `location_id` 163/141/142 ✅ | 32-hex `club_id` ✅ | `idCuadro` 5/6/7/8 ✅ (B2.4) |
| Free-only? | yes, per court, 30-min grid ✅ | yes, per court ✅ | no — taken spans per court, 30-min grid ✅ (B2.4) |
| Timestamps | local wall-clock + `club_timezone` ✅ | absolute ISO8601 + epoch-ms ✅ | wall-clock strings; `/Date()/` is on Madrid's clock ⚠️ (B2.4) |
| Horizon | 14 d (Dighomi, Rustavi), 22–30 d (Krtsanisi), enforced server-side ✅ | caller-chosen, unprobed | 30 d, 21 d at Kachreti ✅ (B2.4) |
| Deeplink | club/date deeplink does not exist; static URL only ⚠️ | `padelmates.se/club/<slug>` ✅ | `/Booking/Grid.aspx?id=<cuadro>`, no date ⚠️ (B2.4) |
| Georgian clubs | 3 ✅ | **0** | 4 |
| Verdict | **easy** | **easy, but nothing to watch** | ~~hard / blocked~~ **easy** (B2.4) |

## Sources

- `https://app.padelbade.com/` (SPA shell, 2026-07-30)
- `https://app.padelbade.com/flutter_bootstrap.js`
- `https://app.padelbade.com/main.dart.js` (1,319,102 bytes)
- `https://api.bookandgo.app/api/v1/apps/58/locations`
- `https://api.bookandgo.app/api/v1/apps/58/court-bookings?date=2026-07-31|2026-08-02|2026-08-20|2026-09-15`
- `https://api.bookandgo.app/robots.txt`
- `https://share.bookandgo.app/padelbade/bookings`
- `https://activity.padelmates.io/` + `/robots.txt` + `/static/js/main.02994d49.js`
- `https://padelmates.se/` + `/static/js/main.60d5bcda.js` (2,911,732 bytes)
- `https://fastapi-production-fargate.padelmates.io/player/player_booking/v2/search_nearby_clubs` (POST)
- `https://fastapi-production-fargate.padelmates.io/player/player_booking/all_courts_slot_prices_v2`
- `https://booking.padelisland.ge/` → `/Login.aspx`, and `/robots.txt`
- `https://padelisland-ge.matchpoint.com.es/robots.txt`
- `https://padelisland.ge/` (→ `https://www.padelisland.ge/`)
