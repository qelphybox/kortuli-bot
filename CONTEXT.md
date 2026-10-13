# Padel slot watcher

The language this project thinks in: what a free hour is, who is waiting for
one, and what a viewer of them shows. Terms here are the ones the code uses —
if a name changes here, it changes in the code too.

## Availability

**Slot**:
One bookable hour on one court at one club, and only ever a free one — a Slot
exists precisely while nobody has taken it.
_Avoid_: booking, reservation, timeslot

**Cell**:
One hour at one club on one date, across all of that club's courts. Coarser
than a Slot: a Cell is free while *any* court is, and carries how many are
where the club says.
_Avoid_: square, box, slot

**Grid**:
The Cells for every watched club over the booking horizon — what the viewer
shows. One row per club, one column per hour.
_Avoid_: schedule, table, calendar

**Rundown**:
One date's free Cells as a single message meant to be forwarded — per Club,
its stretches of free hours, its price and a link to book. The whole day and
every Club, or narrowed to a span of hours that may run past midnight, and to
the Favourites or a handful of Clubs ticked by hand.
Opens with the Forecast over the hours it offers, where there is one.
_Avoid_: digest, summary, export, share

**Game**:
Hours somebody has booked themselves at one Club — one stretch of them on
one date — told to the people they play with: where, when, the Forecast, the
price, the pin, and a link that puts it in a calendar. Whatever the person
says they booked, taken or free, because the Grid may not have caught up.
Never stored; it lives in its URL, which is also the link the group gets.
_Avoid_: booking, reservation, match

**Opening hours**:
The hours a club offers at all, declared per club rather than observed. They
decide how long a row is; no source tells us reliably.
_Avoid_: working hours, business hours

## Clubs

**Club**:
One watchable source of Slots. A venue with two locations is two Clubs, because
a person choosing between them is choosing between neighbourhoods.
_Avoid_: venue, location, site

**Court-level club**:
A Club whose source names the individual court, so its Cells can say how many
of them are free. Padel Club 2, both Padelbade locations, PadelHub, Padel
Academy and Lemans Padel.
_Avoid_: per-court, granular

**Hour-level club**:
A Club whose source reports only whether *some* court is free that hour. Its
Cells say whether, not how many. Kus Tba and all three GymBreeze locations —
for Kus Tba by our choice, for GymBreeze because its API refuses.
_Avoid_: per-hour, coarse, aggregate

**Profile**:
What a Club is like rather than what it has free: each court's Cover, where
the club is, its Listed hours and prices. Read from the club's own listing on
sapadelo.com into `config/club_profiles.yml`; for a person choosing where to
play, and read by nothing that decides a Cell.
_Avoid_: details, info, card

**Cover**:
What is over a court: `indoor` (walls and a roof), `covered` (a roof alone) or
`outdoor`. A Club's courts can differ.
_Avoid_: court type, surface, open/closed

**Listed hours**:
The hours a Club's Profile says it keeps. Shown, never used to draw the Grid —
that is Opening hours' job, and the two can disagree.
_Avoid_: working hours, schedule

**Forecast**:
The weather over Tbilisi by the hour — the chance of rain, how much, how warm
— from Open-Meteo, fetched by the poller every hour and replaced whole. One
point for the whole city. For a person choosing between an open court and a
roofed one; read by nothing that decides a Cell.
_Avoid_: weather data, meteo

**Wet hour**:
An hour of the Forecast when rain is likely (a chance of 50% or more) or a
thunderstorm is due. A date with one sinks the Clubs whose every court is
`outdoor` below the rest of their half.
_Avoid_: rainy slot, bad weather

**Favourite**:
A Club one person has starred. Theirs alone; it narrows a Rundown, leads the
list of Clubs, and comes pre-ticked when making a Standing watch.
_Avoid_: bookmark, pinned, saved club

## Watching

**Watch**:
One person's request to be told when something frees up. Comes in two shapes —
Standing and Dated — and everything downstream treats them alike.
_Avoid_: subscription, alert, filter

**Standing watch**:
A Watch on a recurring window: these clubs, these weekdays, these hours. It has
no end and fires as often as the window keeps producing.
_Avoid_: recurring watch, rule

**Dated watch**:
A Watch on one hour of one date. It fires once and stops mattering after the
hour has passed. Tapping a taken Cell used to make one; nothing does now, and
the ones already made run out on their own.
_Avoid_: one-shot, alarm, reminder

**Freed**:
A Slot going from taken to free while we were looking — the event worth
messaging about. A day newly opening its booking window is not this.
_Avoid_: available, cancellation, opened

**Booking horizon**:
How far ahead we look, ours rather than a club's. A club's own window is its
`max_days` and can be shorter.
_Avoid_: window, range, lookahead

## Running it

**Poll**:
One read of one Club's free Slots, and how it went: `ok`, `suspect` (an
answer the differ refused to believe, so the snapshot was kept) or `failed`
(the source could not be read). Only the last one per Club is kept.
_Avoid_: fetch, scrape, check

**Heartbeat**:
A process saying it is still running, every thirty seconds, into a file of
its own. Proves the process is up, not that it is working — a stale Poll is
what says the poll loop has stopped.
_Avoid_: ping, health check, liveness

**Visit**:
One person opening the mini app on one local date — counted once however
many screens they open, and only once they are signed in. What they looked at
is not kept. The owner's own are not counted.
_Avoid_: session, hit, page view

**Dashboard**:
The owner's screen in the mini app: Heartbeats, every Club's last Poll, the
Visits, the database and the disk under it, and the logs to search. Exists for
`OWNER_TELEGRAM_ID` alone; to anybody else it is not there.
_Avoid_: admin panel, monitoring, status page
