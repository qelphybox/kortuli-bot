# Sport Palace, PadelHub, Padel Academy — re-recon

Three clubs the coverage plan left as "not open", "wave 3" and "deferred",
looked at again on 2026-10-10 (Tbilisi time was already past midnight, so
"today" in the samples below is 2026-10-11). Every endpoint was called live;
the samples are literal excerpts. Anything not confirmed by a live call is
marked **UNVERIFIED**.

| Club | Courts | System | Auth | Verdict |
|---|---|---|---|---|
| [GymBreeze Sport Palace](#gymbreeze-sport-palace) | 4 | gymbreeze | none | **Open now. One config entry, no code.** |
| [PadelHub](#padelhub--changes-since-july) | **3** (was 2) | Supabase RPC | public anon key | **Easy — needs F1 + F2. Two things changed since July.** |
| [Padel Academy](#padel-academy) | 3 | own (Vue + Laravel Sanctum) | **account login** | **Moderate — blocked on a decision, not on tech.** |

---

## GymBreeze Sport Palace

**It is open.** The location has been in the GymBreeze backend since July, and
the coverage plan's "not open — free when it is" is now out of date:

```
GET https://backend.whiteriver-4e0c4713.germanywestcentral.azurecontainerapps.io/api/v1/facilities/locations/
…
{"id":"7a896411-0c3a-5336-a522-a6da08b6132c",
 "name":{"en":"Sport Palace","ka":"სპორტის სასახლე"},
 "address":{"en":"1-26 May Sq.", …},
 "is_active":true, "updated_at":"2026-10-07T14:01:03.780562Z", …}
```

The site offers it too: `https://gymbreeze.ge/eng` server-renders the
location list into the booking form, and Sport Palace is in it along with
its four courts.

**Courts.** `GET …/facilities/courts/` lists four padel courts there
(`number` 1–4, all `is_active`, re-touched 2026-09-09). Ninoshvili has 8 and
Radio City 3, so the plan's "9" for Ninoshvili is one too many.

**Availability.** It is the same endpoint and payload the existing `Gymbreeze`
adapter reads, so nothing about the contract changes:

```
GET …/bookings/availability/?location_id=7a896411-0c3a-5336-a522-a6da08b6132c&date=2026-10-11
{"location_id":"7a896411-…","date":"2026-10-11","available_slots":[
  {"start":"2026-10-11T08:00:00+04:00","end":"2026-10-11T09:00:00+04:00","rate":"60.00"}, …]}
```

The bookings are real. Free hours over the next three weeks look like this, one
character per hour from 08:00 to 00:00, with `#` meaning free:

```
2026-10-11 Sun #####....#.######
2026-10-12 Mon ###########...###
2026-10-13 Tue ############.#.##
2026-10-14 Wed ###########......   ← 19:00–00:00 gone, most days to 10-24
…
2026-10-17 Sat #################
…
2026-10-24 Sat ###########......
2026-10-25 Sun #################   ← everything free from here on
```

Two things to read off that:

- **The evenings 10-14 → 10-24 are blocked on all four courts at once**,
  every day except Saturday the 17th. That looks like a block the club entered
  itself (a league, a corporate rental) rather than ordinary bookings, but the
  API cannot tell the two apart. It does no harm: an hour that is taken is
  taken, and if the block lifts, a person watching that hour will want to hear.
- **Past D+7 the API reports whole days free**, exactly as Ninoshvili does.
  The widget's window is `profile.max_booking_advance_days ?? 7`, read from the
  logged-in user's profile (`bookings/settings/` returns 401 anonymously). An
  anonymous visitor gets 7, so the `max_days: 8` the other two locations use
  (counting today) applies unchanged.

**Hours and price.** Its `working_hours` say 08:00–01:00 every day. Its
`pricing_rules` are Ninoshvili's: 60 before 11:00, 40 from 11:00 to 18:00, and
60 after 18:00.

**What it costs: one entry in `config/clubs.yml`.**

```yaml
- slug: gymbreeze-sport-palace
  name: GymBreeze Sport Palace
  adapter: gymbreeze
  enabled: true
  poll_interval_seconds: 240
  settings:
    location_id: "7a896411-0c3a-5336-a522-a6da08b6132c"
    booking_url: "https://gymbreeze.ge/eng"
    price: "40–60 GEL"
    opening_hours: { from: "08:00", to: "01:00" }
    max_days: 8
    court_aliases: {}
```

It is an **hour-level club** like the other two locations: `court_id` is
still refused by the availability endpoint.

---

## PadelHub — changes since July

The July recon in [self-written-club-sites.md](self-written-club-sites.md#padelhub--padelhubge)
still holds on transport: same Supabase project
(`gpypwkyuangjzgabagyi`), the same anon JWT in the entry bundle (now
`assets/index-BbbjDXQk.js`), and the same RPC. The booking chunk is now
`assets/BookingPage-D8Jr13Zf.js`. `robots.txt` disallows only `/admin`,
`/dashboard`, `/login`, `/register` and `/confirm-email`, so
`/booking` is open.

Two things changed, and both affect an adapter.

**1. A third padel court.** `GET /rest/v1/courts?select=*&is_active=eq.true`:

```json
{"id":"0a0a2ddd-4f0d-4a66-a5c3-2d08bcf5eebd","name":"court_padel_open",    "sport_type":"padel","evening_price":null}
{"id":"7c36c5d8-8a2f-4021-ab76-6305ed6f85a1","name":"court_padel_closed",  "sport_type":"padel","evening_price":70.00}
{"id":"bce555f2-8568-498b-b6cc-55ca1ef71d16","name":"court_padel_closed_2","sport_type":"padel","evening_price":70.00,
 "created_at":"2026-10-05T15:40:20.351928+00:00"}
{"id":"154545c2-e962-4d85-8e1a-9bf5bcfa4721","name":"court_pickleball",    "sport_type":"pickleball","evening_price":null}
```

The new court is already selling. Here is 2026-10-12 on `court_padel_closed_2`:

```json
[{"time_slot":"18:00","booking_date":"2026-10-12","status":"confirmed","is_payment_hold":false},
 {"time_slot":"19:00", …},{"time_slot":"20:00", …},{"time_slot":"21:00", …}]
```

The adapter should therefore **read the court list from `/rest/v1/courts`
each tick** (filtering on `sport_type == "padel"`) rather than hard-coding
two UUIDs, because the club has already added a court once. That makes
three RPC calls per date. Labels still come from i18n keys: "Outdoor",
"Indoor 1" and "Indoor 2" would read well, and they belong in
`court_aliases`.

**2. The taken rule is simpler.** The July client also counted a
`cancelled` row as taken when it started within the next 2 hours. That rule
is gone. The predicate now lives in `assets/booking-constants-CpDNbBE_.js`:

```js
function M(t,s){const o=s.find(e=>e.time_slot===t);
  return o&&o.status==="confirmed"?o.is_payment_hold?"hold":"taken":"free"}
```

So an hour is **free unless a `confirmed` row exists for it**. A
`confirmed` row with `is_payment_hold: true` is a checkout in progress. It
counts as not free. If the payment is abandoned, the hold drops and the hour
reads free again, which is a real freeing and not noise.

**Prices** changed with the courts. The rule is 40 GEL for starts from 08:00
to 14:00, and otherwise the court's `evening_price`, falling back to 60. That
means the outdoor court costs 60 in the evening and the indoor courts cost 70:

```js
function qr(e,t,s){if(e==="padel"){if(Ar.has(t))return jt;if(s!=null)return s}return ot[e]??0}
```

Print it as `"40–70 GEL"`.

**Unchanged:** the grid is the same, running 08:00 to 23:00 plus `00:00`,
and `00:00` is the *next* calendar day (`+24 h`). The timezone is hard-coded
as `+04:00`. The date picker is `disabled:{before:new Date}` with no upper
bound, so an adapter has to cap `max_days` itself. 2026-11-10 returned `[]`
on both of the original courts. There is no deeplink beyond `https://www.padelhub.ge/booking`.

**Bundle aside, not needed for an adapter:** the constants name booking
sources `padpod`, `rallo` and `playspot`. That suggests some bookings arrive
from third-party marketplaces rather than this site (**UNVERIFIED**). The
RPC returns them like any other row, so the adapter does not care.

**What it costs:** F1 (`Http#post_json` with `apikey` and `Authorization`
headers) and F2 (free = grid minus booked), both as planned. The adapter
itself is small:

- one `GET /courts`
- per date in `max_days` × per padel court, one `POST /rpc/get_booking_availability`
- subtract the `confirmed` `time_slot`s from the grid
- roll `00:00` forward a day
- drop starts already past

It is a **court-level club** with `courts: 3`.

---

## Padel Academy

The coverage plan said "login-gated, deliberately skipped", but nobody had
actually looked. Now somebody has. The gate is real, but it is an ordinary
account and not an operator refusal.

**Identity.** The marketing site `https://padelacademy.ge/` gives the address
as Petre Kavtaradze 1 turn N2, Tbilisi, which is in **Saburtalo**. Its
"BOOKING" link goes to `https://booking.padelacademy.ge`. Sapadelo lists
3 courts, all indoor, at 80 GEL an hour, open 08:00–02:00 daily, with racket
rental at 3 GEL. `www.padelacademy.ge` does not resolve.

**Stack.** `booking.padelacademy.ge` is a Vue 3 + axios PWA with a single
bundle (`/assets/index-DFdEwUle.js`), behind Cloudflare. The backend is
Laravel + Sanctum: Bearer tokens, `X-Requested-With: XMLHttpRequest`, and
`{"message":"Unauthenticated."}` on a 401. It is not a known platform, and
there is no anon key to find.

**The wall.** Availability is one call, and it needs a token:

```
POST https://booking.padelacademy.ge/api/booking/check
Content-Type: application/json
{"date":"2026-10-12","court":"1"}
→ 401 {"message":"Unauthenticated."}
```

The schedule lives at `/dashboard`, which is `requiresAuth`. Nothing before
login shows it: the public `/` only shows the club rules.

**What is *not* in the way:**

- `robots.txt` is `User-agent: * / Disallow:`, which allows everything.
- There is no captcha: no Turnstile, reCAPTCHA or hCaptcha in the bundle.
- Cloudflare passes plain requests.

That is the difference from Padel Island, which disallows its booking paths
and sits behind Turnstile. Nothing here was written down as a refusal.

**Behind the wall.** This comes from the bundle; the response shape is
**UNVERIFIED**.

- `POST /api/login {email,password}` returns `{token}`.
- `POST /api/booking/check {date,court}` returns a flat array of **free**
  hours for one court on one date. Free-only means no inversion step.
- Courts are hard-coded as `<option value="1..3">`, and there is no courts
  endpoint. Slots are 60 min at 80 GEL each.
- The client's horizon runs to the end of next month
  (`new Date(y, m+2, 0)`). `minDate` falls back to yesterday before 02:00
  local time, so the hours after midnight probably belong to the previous
  date, as at Kus Tba. **UNVERIFIED**; the first live call has to settle
  this and the element format (`"10:00"` versus `10`).
- There is no deeplink, so use a static `booking_url`.

**Registration** is one POST: name, email, phone, password and a terms
checkbox. There is no OTP step on the client, though the server side is
**UNVERIFIED**. Password reset goes out by SMS, so the account wants a real
phone number.

**What it costs:**

1. **A decision first.** Do we register a dedicated account on the club's
   system and agree to its terms in order to read the schedule? This is a
   relationship question, not a technical one. Asking the club for read
   access instead is the cleaner version of the same thing. No account was
   created during this recon.
2. Then: credentials in env (`PADEL_ACADEMY_EMAIL`/`_PASSWORD`, passed
   through `.kamal/secrets` like the others), log in lazily, cache the token,
   and log in again on a 401. Each tick costs 3 courts × `max_days` calls;
   at 8 days that is 24 calls.
3. It is a **court-level club** with `courts: 3`, and free-only, so it does
   not need F2.
4. **Never** call `/api/booking/save`. It starts a bank-payment booking, and
   the account is limited to one active attempt per 5 minutes.
