# BookingPress @ Tbilisi Padel — adapter recon

Investigated 2026-07-30/31 against the live site. Every claim below is tagged
**[verified]** (I saw the bytes) or **[unverified]** (inference — say so in code
comments too).

## TL;DR — the premise in the old doc is wrong

The doc I was handed assumed `admin-ajax.php` with
`bookingpress_front_get_category_services` and a guessed
`bookingpress_front_get_available_time_slots`. **Neither applies to this
deployment.** [verified]

tbilisipadel.ge runs **BookingPress 1.6.1** (`readme.txt`: `Stable tag: 1.6.1`,
<https://tbilisipadel.ge/wp-content/plugins/bookingpress-appointment-booking/readme.txt>)
with the **Vue 3 "form v3"** front end, which replaced the old admin-ajax
transport with a **WP REST namespace**:

    https://tbilisipadel.ge/wp-json/bookingpress-app/v1/form-v3/

No `admin-ajax.php` call is involved in listing courts or fetching slots.
Courts don't need an HTTP call at all — they are **server-rendered into the page
HTML** as a JSON island. [verified]

I found no `bookingpress_front_*` action name anywhere in the loaded JS. If you
ever hit an *older* BookingPress install, the admin-ajax path may still exist,
but for this target it is dead — do not write the adapter against it.

---

## 1. Endpoints

Route list read from `https://tbilisipadel.ge/wp-json/bookingpress-app/v1/`
(anonymous GET, HTTP 200). [verified] Relevant routes:

| Route | Method | Use |
|---|---|---|
| `/bookingpress-app/v1/form-v3/timeslots` | POST | Slots for **one** date + the month-walk cursor |
| `/bookingpress-app/v1/form-v3/month-details` | POST | Slots for an **entire month** — one round trip |
| `/bookingpress-app/v1/form-v3/state` | POST | Form state (not needed) |
| `/bookingpress-app/v1/form-v3/submit` | POST | Actually books. **Never call this.** |

The REST index declares no arguments for these routes (only an optional
`wpml_language` enum `["en","ge"]`), so the real body shape comes from the
plugin's own unminified JS — see §3. [verified]

**(a) Listing services/courts: there is no endpoint.** The service list is
embedded in the booking page HTML (§2). [verified]

**(b) Fetching timeslots: `form-v3/month-details`** is what the adapter should
use — it returns a whole month per request. `form-v3/timeslots` is the
single-date/bootstrap variant. [verified]

### Source files (unminified, publicly readable — best primary source)

Base: `https://tbilisipadel.ge/wp-content/plugins/bookingpress-appointment-booking/src/assets/js/booking-form-vue3/`

- `api/client.js` — the fetch wrapper; defines the auth triple exactly.
- `composables/useTimeslots.js` — builds the request bodies.
- `bootstrap.js`, `app.js` — mount plumbing.

`api/client.js` (literal):

```js
async function post(route, body) {
  const payload = {
    ...(body || {}),
    bp_v3_nonce: cfg.formNonce,
    bp_v3_instance_token: cfg.instanceToken,
    instanceId: cfg.instanceId,
  };
  const res = await fetch(`${root}/${route}`, {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', 'X-WP-Nonce': cfg.wpRestNonce },
    body: JSON.stringify(payload),
  });
```

Note **`Content-Type: application/json`** with a JSON body — *not* form-encoded
like the old admin-ajax API. [verified]

---

## 2. The JSON island: courts, prices, nonces

`GET https://tbilisipadel.ge/` (the homepage **is** the booking page; there is
no `/booking/` route — `wp-sitemap-posts-page-1.xml` lists only `/`, `/shop/`,
`/cart/`, `/my-account/`, `/checkout/`, `/thank-you-2/`, `/terms/`). [verified]

The page carries:

```html
<script id="wp-script-module-data-bookingpress-form-v3-loader" type="application/json">
{"instances":{"a072296fd242":{"instanceId":"a072296fd242","atts":{...},"config":{...},"services":[...],"nonces":{...}}}}
</script>
```

The island is **plain JSON, not HTML-escaped** — no `&quot;`, no `<`. It
parses with `JSON.parse` straight out of the regex capture. Verified in Ruby:

```ruby
ISLAND = %r{<script id="wp-script-module-data-bookingpress-form-v3-loader" type="application/json">(.*?)</script>}m
island   = JSON.parse(html[ISLAND, 1])
id, inst = island.fetch("instances").first   # exactly one instance on this page
nonces   = inst.fetch("nonces")              # wpRestNonce / formNonce / instanceToken
services = inst.fetch("services")
today    = inst.dig("config", "today")       # server-local date, e.g. "2026-07-31"
max_date = inst.dig("config", "maxDate")     # "2027-07-31"
```

This exact snippet ran and printed the right values. [verified]

> **Do not** regex for `"nonces":{...}` directly: the page contains a *second*
> unrelated `"nonces"` object (`floatingButtonsClickTracking`,
> `atomicFormsSendForm`). Anchor on the island id and parse the JSON. [verified]

### `services[]` — the courts (from `/en/`, English labels)

| `serviceId` | `serviceName` (EN) | `serviceName` (KA) | `servicePrice` | `meta.max_capacity` | `meta.minimum_time_required_before_booking` |
|---|---|---|---|---|---|
| 1 | Ilia's Garden | ილიას ბაღი | 60 | 1 | 60 m |
| 4 | Mtatsminda Park | მთაწმინდის პარკი | 60 | 1 | 60 m |
| 6 | Didi Digomi | დიდი დიღომი | 60 | **4** | 30 m |
| 5 | Didi Digomi 1 vs 1 | დიდი დიღომი 1 vs 1 | 50 | 1 | 60 m |

All four: `categoryId: 1`, `serviceDurationVal: 1`, `serviceDurationUnit: "h"`.
[verified] Each also carries `avatarUrl` (a photo) and
`meta.bookingpress_woocommerce_product` (payment goes through WooCommerce).

**Language:** `https://tbilisipadel.ge/` renders Georgian names,
`https://tbilisipadel.ge/en/` renders English ones. **Same `serviceId`s, same
nonces.** Scrape `/en/` for human labels. [verified]

### `config` fields worth reading

| Field | Value observed | Meaning |
|---|---|---|
| `today` | `2026-07-31` | **Server-local** date. Use this, not the bot's clock. |
| `maxDate` | `2027-07-31` | today + 365d |
| `timeFormat` | `24` | |
| `currency` / `currencySymbol` | `GEL` / `₾` | |
| `slotShowEndTime` | `false` | cosmetic |

---

## 3. Request bodies

From `composables/useTimeslots.js` (literal):

```js
const monthBody = applyTimeslotRequestFilter({
  service_id:     sid,
  from_date:      from,          // "YYYY-MM-01"
  selected_year:  year,
  selected_month: month,         // 1-12, NOT zero-padded
}, state, 'month');
```

and for the bootstrap single-date call:

```js
const initialBody = {
  service_id:    sid,
  category_id:   parseInt(state.appointment_step_form_data.selected_category || 0, 10),
  selected_date: todayYmd,
};
```

Plus the three auth fields `api/client.js` injects into every body.

### `month-details` — the one the adapter should use

```
POST https://tbilisipadel.ge/wp-json/bookingpress-app/v1/form-v3/month-details
Content-Type: application/json
X-WP-Nonce: <wpRestNonce>

{
  "service_id": 1,
  "from_date": "2026-08-01",
  "selected_year": 2026,
  "selected_month": 8,
  "bp_v3_nonce": "<formNonce>",
  "bp_v3_instance_token": "<instanceToken>",
  "instanceId": "<instanceId>"
}
```

`category_id` is **not** required here — omitting it returns a correct payload.
[verified]

Real response (HTTP 200, 74109 bytes, trimmed but literal):

```json
{"ok":true,"data":{"working_details":{
  "2026-08-01":[
    {"start_time":"09:00","end_time":"10:00","formatted_start_time":"09:00","formatted_end_time":"10:00","is_available":1,"remaining_capacity":1,"is_overnight":0},
    {"start_time":"10:00","end_time":"11:00","formatted_start_time":"10:00","formatted_end_time":"11:00","is_available":1,"remaining_capacity":1,"is_overnight":0},
    ...
    {"start_time":"23:00","end_time":"00:00","formatted_start_time":"23:00","formatted_end_time":"00:00","is_available":1,"remaining_capacity":1,"is_overnight":0}],
  "2026-08-02":[ ... ],
  ...
  "2026-08-31":[ ... ]},
 "vcal_attributes":[],"vcal_capacity_attrs":[],"is_daysoff":[],
 "v_calendar_blocked_dates":[],"timing_token_data":"...","consider_overnight_booking":0}}
```

`month-details` returns `next_month_date`, `max_available_date` and
`found_month` as `null`. [verified]

### `timeslots` — single date + horizon metadata

Same auth; body `{"service_id":1,"category_id":1,"selected_date":"2026-07-31"}`.
Real response (HTTP 200, 1896 bytes, literal, service 1 on 2026-07-31):

```json
{"ok":true,"data":{"working_details":{"2026-07-31":[
  {"start_time":"09:00","end_time":"10:00","formatted_start_time":"09:00","formatted_end_time":"10:00","is_available":1,"remaining_capacity":1,"is_overnight":0},
  {"start_time":"10:00",...},{"start_time":"11:00",...},{"start_time":"12:00",...},
  {"start_time":"13:00",...},{"start_time":"14:00",...},{"start_time":"15:00",...},
  {"start_time":"16:00",...},{"start_time":"17:00",...},
  {"start_time":"23:00","end_time":"00:00","formatted_start_time":"23:00","formatted_end_time":"00:00","is_available":1,"remaining_capacity":1,"is_overnight":0}]},
 "vcal_attributes":[],"vcal_capacity_attrs":[],"is_daysoff":[],
 "v_calendar_blocked_dates":[],"next_month_date":"2026-08-01",
 "max_available_date":"2027-07-31","found_month":"2026-07",
 "timing_token_data":"6586ef70a7056357","consider_overnight_booking":0}}
```

Note the gap: `18:00`–`22:00` are simply **absent** — those five hours were
booked at Ilia's Garden. That's the whole availability signal (§5). [verified]

`max_available_date` here is the authoritative horizon (§6). It only appears on
`timeslots`, so if you want it, make one `timeslots` call per poll; otherwise
just use `config.maxDate` from the island, which matched it exactly. [verified]

### Error shape

Failures are `{"ok":false,"error":{"code":"...","message":"..."}}` with a real
non-200 status. Observed codes:

| HTTP | `error.code` | Cause |
|---|---|---|
| 403 | `bp_v3_rest_invalid_nonce` | `X-WP-Nonce` header missing |
| 403 | `bp_v3_invalid_form_nonce` | `bp_v3_nonce` body field missing/wrong |
| 400 | `bp_v3_invalid_instance` | `instanceId`/`bp_v3_instance_token` missing, wrong, or mismatched |
| 403 | `rest_cookie_invalid_nonce` | `X-WP-Nonce` present but bogus (WP core rejects before BookingPress; message is localised Georgian) |

[verified — I triggered each one]

---

## 4. Auth: three tokens, all required, no login

**All three are mandatory.** I removed each in turn and got a 4xx every time
(table above). [verified]

| Token | Where it goes | Value seen | Stability |
|---|---|---|---|
| `wpRestNonce` | `X-WP-Nonce` **header** | `bc074b0c33` | **Stable across renders** [verified] |
| `formNonce` | `bp_v3_nonce` **body** | `2efd9e8c7e` | **Stable across renders** [verified] |
| `instanceToken` | `bp_v3_instance_token` body | `klQOZ0NK…` (32 chars) | **New random value on every page render** [verified] |
| `instanceId` | `instanceId` body | `a072296fd242` (12 hex) | New on every render, **must pair with its own token** [verified] |

Findings:

- **No login, no cookie, no session.** Every successful request above was a bare
  `curl` with a browser User-Agent and *zero* cookies. [verified]
- `_wpnonce` as a **query parameter does not work** — BookingPress reads the
  `X-WP-Nonce` header specifically. `?_wpnonce=…` returned
  `bp_v3_rest_invalid_nonce`. [verified]
- `instanceId` + `instanceToken` are validated as a **matched pair, server-side**:
  render-1's token with render-2's id → `bp_v3_invalid_instance`; a random
  32-char token with a real id → same; a made-up pair → same. So you cannot
  synthesize them; you must scrape a real render. [verified]
- Old pairs keep working: the pair from my first fetch still answered ~20 min
  later. [verified] How long the server retains an instance record is
  **[unverified]** (likely a WP transient).
- Nonce lifetime: WordPress default is a 24 h life on a 12 h tick, so a nonce is
  accepted for 12–24 h. **[unverified for this site]** — I only observed the two
  nonces holding steady over ~20 minutes; I did not wait out a tick.

### Extraction regex (Ruby)

```ruby
ISLAND_RE = %r{<script id="wp-script-module-data-bookingpress-form-v3-loader" type="application/json">(.*?)</script>}m
```

Then `JSON.parse` the capture (no HTML-unescaping needed) and read
`instances.first` → `["nonces"]["wpRestNonce" | "formNonce" | "instanceToken"]`
and the outer key for `instanceId`. [verified]

### Recommended credential strategy

Scrape `https://tbilisipadel.ge/en/` once per poll cycle (or cache the triple
and re-scrape on any 403/400 with the codes above). One page fetch + N
`month-details` posts per tick. Cheap and self-healing — and it side-steps the
whole nonce-lifetime unknown.

---

## 5. Free vs. taken: the response is **pre-filtered to free slots**

Across **2310 slot rows** captured over 6 different month/service payloads,
`is_available` was `1` on every single row; `0` never appeared. The front-end
bundle never reads the field either (`grep is_available` over
`useTimeslots.js` and `utils/slots.js` → no hits). [verified]

**The signal is presence in the array.** A booked hour is simply omitted:

- Ilia's Garden, 2026-07-31: `09:00…17:00` + `23:00`, no `18:00`–`22:00` → those
  five were booked. [verified]
- Ilia's Garden, 2026-08-02: `10:00` missing from an otherwise full day.
- Didi Digomi 1v1, 2026-08-02: `20:00` missing.

This matches the adapter contract exactly — **`fetch` returns what the API
already returns**, no filtering needed.

Caveat for the code comment: absence means *booked **or** past **or** outside
working hours*, not specifically "booked". Past dates are dropped wholesale —
`month-details` for the current month (`2026-07`) returned **only**
`2026-07-31`, i.e. today; days 1–30 were absent entirely. [verified]

### `remaining_capacity` — the court counter

For `service_id: 6` (Didi Digomi, `max_capacity: 4`), `remaining_capacity` came
back as `4` or `3` — the number of **free courts** in that hour. For the
capacity-1 services it is always `1`. [verified]

This is the same shape as Padel Club 2's `courts: 4` in `config/clubs.yml`, so
Didi Digomi can be a court-level club and the rest hour-level.

---

## 6. Horizon and granularity

**Horizon: 365 days.** `max_available_date` = `2027-07-31` on a `today` of
`2026-07-31`; `config.maxDate` agrees. [verified]

But — same trap as GymBreeze and Kus Tba. I fetched `service_id 6` for
**2027-06** and got all 30 days × 15 hours at `remaining_capacity: 4`, i.e. a
completely empty year-away month. [verified] Nothing out there ever transitions,
so **cap `max_days` in the club settings** (7–14) exactly as the other adapters
do. Do not walk 12 months.

**Granularity: per-location, not per-court.** [verified]

- A "service" is a **location**, not a court. There is no court id anywhere in
  the response — rows carry only times and a capacity count.
- Ilia's Garden / Mtatsminda Park are `max_capacity: 1` → one bookable unit;
  slot present = free. Hour-level, `court_ref = "any"` like `Gymbreeze`.
- Didi Digomi is `max_capacity: 4` → `remaining_capacity` tells you how many of
  the four are free, but **not which**. Still no per-court ref.
- Slot length is fixed 1 h, aligned on the hour, `09:00`–`23:00` starts.

Also present: a **custom-service-duration** add-on
(`config.bookingpress_custom_service_duration`) letting a customer book 60–180
minutes at 60 GEL/h (50 for service 5). The adapter can ignore it — it only
affects how many consecutive hours a *booking* consumes, and the availability
payload is still per-hour.

---

## 7. Locations, prices, hours

### How the 3 locations are distinguished

**One WordPress site, one category, four services.** [verified]

- `tbilisipadel.com` **301s to `https://tbilisipadel.ge/`** — same site, not a
  second install. [verified]
- All four services are `categoryId: 1`; the island's `categories` array is
  **empty** and the shortcode hardcodes `atts.category = "1"`.
- So: **location == `serviceId`**.

| Location | serviceId(s) | Note |
|---|---|---|
| Ilia's Garden | `1` | |
| Mtatsminda Park | `4` | |
| Didi Dighomi | `6` (4 courts) and `5` (1v1, 1 court) | Two services, one address |

Didi Dighomi is split by game format. Whether services 5 and 6 draw on the same
physical courts is **[unverified]** — I will not test it by booking. Their
availability differs independently (2026-08-02: `20:00` free on 6, absent on 5),
which suggests **separate inventories**, but that's inference. Suggest modelling
`6` as the Didi Dighomi club and treating `5` as optional/secondary.

### Prices

From `services[].servicePrice`, currency `GEL`: [verified]

| Service | Price |
|---|---|
| Ilia's Garden (1) | 60 GEL / h |
| Mtatsminda Park (4) | 60 GEL / h |
| Didi Digomi (6) | 60 GEL / h |
| Didi Digomi 1 vs 1 (5) | 50 GEL / h |

Flat — no time-of-day tiering in the payload (unlike GymBreeze).
`config.bookingpress_custom_service_duration` confirms `unit_price` 60/60/60/50
per hour.

### Opening hours

**Not published anywhere on the page** — the site has no hours/address text; it
is a booking form plus a photo gallery and a phone number
(`+995 577 95 24 24`, `info@padel.ge`). [verified]

Derived from the slot grid instead: earliest start `09:00`, latest start
`23:00`, `end_time` `00:00`. Identical for all four services across every month
I pulled. So **`from: "09:00"`, `to: "24:00"`**. `consider_overnight_booking: 0`
and every `is_overnight: 0`, so **no post-midnight rollover** — unlike Kus Tba,
a day is a clean calendar day. [verified for August 2026 and June 2027; whether
winter hours differ is **[unverified]**]

### Timezone

**Asia/Tbilisi, UTC+4, no DST.** Response times are bare local wall-clock
(`"09:00"`) with no offset, so the adapter must attach `+04:00` itself.
[verified] Proof: server `Date:` header read `Thu, 30 Jul 2026 22:09:40 GMT`
while the island's `config.today` read `2026-07-31` — the site's local date had
already rolled over, which only works at +04.

Use `config.today` from the island as "today" rather than the bot's clock.

---

## 8. Adapter sketch

```
per poll tick:
  html   = GET https://tbilisipadel.ge/en/
  triple = parse island -> {instanceId, wpRestNonce, formNonce, instanceToken}
  today  = island.config.today                      # server-local
  for each (year, month) touched by date_range.first(max_days):
    POST /wp-json/bookingpress-app/v1/form-v3/month-details
         headers: X-WP-Nonce, Content-Type: application/json
         body:    service_id, from_date, selected_year, selected_month,
                  bp_v3_nonce, bp_v3_instance_token, instanceId
    for each date, row in data.working_details:
      skip dates outside date_range
      Slot.new(
        court_ref:   "any",                          # no court id exists
        court_label: club.name,
        starts_at:   Time.parse("#{date}T#{row['start_time']}:00+04:00"),
        ends_at:     row['end_time'] == "00:00" ? starts_at + 1h
                                                : Time.parse("#{date}T#{row['end_time']}:00+04:00"),
        price:       club.settings["price"],
        deeplink:    "https://tbilisipadel.ge/en/")
```

Gotchas to encode:

1. `end_time` `"00:00"` on the 23:00 row is **next day** — adding an hour to
   `starts_at` is safer than parsing it. [verified the value exists]
2. `selected_month` is an integer 1-12, not zero-padded. [verified]
3. `{"ok":false}` bodies arrive with 4xx, so an HTTP-status check catches them —
   but check `ok` too, and raise `SourceUnavailable` rather than reading an
   empty `working_details` as "everything booked" (the `Gymbreeze` lesson).
4. Cap `max_days`; the API answers 365 days out with fiction.
5. Refresh the triple and retry once on `bp_v3_invalid_instance` /
   `bp_v3_*_nonce`.

### Suggested `config/clubs.yml`

```yaml
- slug: tbilisi-padel-ilias-garden
  name: Tbilisi Padel — Ilia's Garden
  adapter: bookingpress
  settings:
    base_url: "https://tbilisipadel.ge"
    booking_url: "https://tbilisipadel.ge/en/"
    service_id: 1
    price: "60 GEL"
    opening_hours: { from: "09:00", to: "24:00" }
    max_days: 10
    court_aliases: {}

- slug: tbilisi-padel-mtatsminda   # service_id: 4, price "60 GEL"
- slug: tbilisi-padel-didi-dighomi # service_id: 6, price "60 GEL", courts: 4
```

Only Didi Dighomi gets `courts: 4` (from `remaining_capacity`); the other two
are hour-level.

---

## 9. Deeplink: partially blocked

**There is no per-court or per-date deeplink that I could find.** [verified
negative — see caveat]

I tried `?service_id=4`, `?bpa_service_id=4`, `?service=4`,
`?bookingpress_service=4`, `?selected_service=4` against
`https://tbilisipadel.ge/`. In all five the server-rendered island came back
identical: `preselection.is_from_url = 0`, `atts.service = ""`,
`preselection.selected_service = 0`. [verified]

The plugin clearly *has* a from-URL concept (`is_from_url`, `allow_modify` in
`preselection`), so a magic parameter name probably exists — I did not find it
and the PHP that reads it is not web-readable. **[unverified]**

Practical consequence: **`deeplink` is just `https://tbilisipadel.ge/en/`** for
all three clubs. The user lands on the form and picks the court. Given the
notification names the court and the time, that's acceptable — but it is a step
worse than a Reservio deeplink.

**If you want to resolve this properly**, this is the one thing that needs a
JS-executing browser or admin access:
- **URL:** `https://tbilisipadel.ge/en/`
- **What to capture:** click through to step 2, pick a date/slot, and watch
  whether the SPA writes anything to `window.location` / `history.pushState`.
  Also worth reading `components/App.js` and `components/steps/*.js` under
  `…/booking-form-vue3/` for a `URLSearchParams` reference — I only checked
  `useFormState.js` (no hits), `client.js`, `bootstrap.js` and `app.js`.

---

## 10. Everything marked unverified, in one place

1. **Nonce lifetime.** WP's 12–24 h default is an inference; I observed only
   ~20 min of stability. Mitigation: re-scrape per tick, retry on 403.
2. **`instanceToken` server-side retention window.** Old pairs worked after
   20 min; the expiry is unknown.
3. **Whether services 5 and 6 share physical Didi Dighomi courts.** Their
   availability moves independently, suggesting no, but proving it needs a
   booking.
4. **Seasonal opening hours.** 09:00–24:00 held for Aug 2026 and Jun 2027;
   winter may differ.
5. **A URL parameter for preselecting a service.** Five candidates failed; the
   real name (if any) is unknown.
6. **Whether an older admin-ajax transport still exists on this install.**
   Irrelevant to the adapter — the REST path is what the site itself uses — so
   I did not probe `admin-ajax.php` for legacy actions.

---

## Appendix: reproduce it

```bash
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

# 1. scrape the triple
curl -sS -A "$UA" https://tbilisipadel.ge/en/ \
| perl -0777 -ne 'print $1 if m{<script id="wp-script-module-data-bookingpress-form-v3-loader" type="application/json">(.*?)</script>}s' \
| python3 -m json.tool | head -40

# 2. one month of availability for Ilia's Garden (substitute your fresh triple)
curl -sS -A "$UA" -X POST \
  https://tbilisipadel.ge/wp-json/bookingpress-app/v1/form-v3/month-details \
  -H 'Content-Type: application/json' \
  -H 'X-WP-Nonce: bc074b0c33' \
  -d '{"service_id":1,"from_date":"2026-08-01","selected_year":2026,"selected_month":8,
       "bp_v3_nonce":"2efd9e8c7e",
       "bp_v3_instance_token":"klQOZ0NKHtke0wGBiPd4S7EU6pmKAZ2v",
       "instanceId":"a072296fd242"}'
```

Total requests made during this recon: ~35, spread over several minutes, plain
`curl` with a browser UA. Nothing was booked; `form-v3/submit` was never called.
