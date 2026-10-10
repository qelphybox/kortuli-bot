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
its stretches of free hours, its price and a link to book. The whole day, or
narrowed to a span of hours that may run past midnight.
_Avoid_: digest, summary, export, share

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
of them are free. Padel Club 2 and both Padelbade locations.
_Avoid_: per-court, granular

**Hour-level club**:
A Club whose source reports only whether *some* court is free that hour. Its
Cells say whether, not how many. Kus Tba and both GymBreeze locations — for Kus
Tba by our choice, for GymBreeze because its API refuses.
_Avoid_: per-hour, coarse, aggregate

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
A Watch on one hour of one date, made by tapping a taken Cell. It fires once
and stops mattering after the hour has passed.
_Avoid_: one-shot, alarm, reminder

**Freed**:
A Slot going from taken to free while we were looking — the event worth
messaging about. A day newly opening its booking window is not this.
_Avoid_: available, cancellation, opened

**Booking horizon**:
How far ahead we look, ours rather than a club's. A club's own window is its
`max_days` and can be shorter.
_Avoid_: window, range, lookahead
