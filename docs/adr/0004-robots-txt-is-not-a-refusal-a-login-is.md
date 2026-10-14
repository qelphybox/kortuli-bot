# robots.txt is not a refusal; a login is

The coverage plan excluded Padel Island because its `robots.txt` disallows
`/Booking/`, and called reading past that "deliberately working around a
refusal the operator wrote down". On 2026-10-13 the same test turned out to
catch far more than Padel Island: `api.reservio.com/robots.txt` is
`Disallow: /` (so Padel Port, Padel Port New Park, Grand Padel Batumi, and the
Padel Club 2 page we had read since the first commit), and Padel Gldani's site,
built on Manus, added `Disallow: /api/` on 2026-09-30. Applied evenly, the rule
would have emptied Batumi and taken a Tbilisi club with it. So the rule was
decided again, on purpose.

The line is drawn at what the operator puts *in the way*, not at what a
crawler policy file says:

- **We read** a club's public availability — the same answer its own booking
  page fetches for any anonymous visitor — at the rate the poller runs (one
  pass every few minutes, sequential, with jitter), whatever `robots.txt`
  says about that path.
- **We do not read** anything behind a login, a captcha, a Turnstile or other
  challenge, or a member account, and we do not forge or replay credentials to
  get past one. Padel Academy is the
  one club read behind a login, and it is read the way a member reads it: an
  ordinary account signing in through the club's own front door, never a
  bypass of it.

## Considered options

**Honour robots.txt everywhere.** Rejected. It is the conservative reading,
and it is what the plan said. But `robots.txt` is written for crawlers that
index and republish pages; most of these files are a platform's default
(Reservio's API host, Manus's `/api/`), not a club's decision about its own
schedule. Honouring them would drop the clubs that most want a full evening —
the ones a cancellation notice sends traffic back to — while every club on a
platform without a robots file stays in. That is an accident of hosting, not
a policy.

**Ignore robots.txt and anything else.** Rejected. A login or a challenge is
the operator spending effort to keep anonymous readers out, and getting past
it is the line between reading a public page and breaking in.

## Consequences

Each adapter that reads a robots-disallowed path says so in its header
comment, with the date the rule was seen, so the decision is visible where it
is exercised rather than only here.

Asking still beats reading. When a club or platform asks us to stop, the club
is disabled the same day — removing its entry from `config/clubs.yml`
switches it off on the next boot — and the request is recorded in
`docs/coverage-plan.md` under "Excluded on purpose". Revisit this ADR the first
time that happens.

## Correction, 2026-10-14

This record first kept Padel Island out as the example of a door shut: "its
grid sits behind a login and a Turnstile". That was wrong. Its root URL
redirects to a login page that carries the Turnstile, but the grid itself,
`/Booking/Grid.aspx`, opens for anyone, and so does the JSON its own script
reads. The 2026-07-31 recon had stopped at the robots file and never fetched
the grid, so the login stood in for it. Under the rule above, Padel Island is
in: a robots line, not a door. Its adapter, `matchpoint`, carries the dated
note the rule asks for.
