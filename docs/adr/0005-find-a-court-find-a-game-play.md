# Find a court, find a game, play — the watch is one tool among them

`docs/INIT_CONCEPT.md` set the priority at the start: the watch is the
product, a one-off search is commodity, and matchmaking is "a different
product with different dynamics — do not mix". That was right for a weekend
MVP with one user who already played. It is not what the project is for now.

Decided 2026-10-25: the product is that **anyone can quickly find a court that
suits them, find people to play with, and play** — including someone who has
never held a racket. The Watch stays, and stays good, but it is one way of
finding a court, not the point of the app.

## Why now

The competitor sweep (`docs/research/competitors-padelspot-playspot.md`)
showed both neighbours treating the alert as a side feature. PadelSpot's
reminders are dated, capped and sent by SMS; PlaySpot advertises none at all.
Neither is losing users for it. What both are building is the path from "I
want to play tonight" to standing on a court with three other people, and
that path is where a person who is new to padel gets lost: which club, which
hour, who with, and what the rules even are.

## The three jobs

1. **Find a court.** The Grid, the Rundown, the clubs directory and the map
   are this job; the Watch is its patient form, for an hour that is not free
   yet. Speed and coverage — every watchable club, read correctly — matter
   more than any one screen.
2. **Find a game.** A person with a court and one seat short, and a person
   with no group at all, should be able to meet. Today a Game is hours
   somebody booked, told to the people they already play with; this job is
   the same Game reaching people they do not know yet.
3. **Play.** For a beginner that starts before the court: the rules, how a
   point and a set are scored, who wins, how to serve, and where the glass
   comes in. Short, illustrated, understood at a glance — a tutorial a person
   finishes, not a rulebook they skim.

## Considered options

**Keep the watch as the product.** Rejected. It serves people who already
play, already have a group and already know which clubs they like — the
audience that needs the app least. It also made the matchmaking line in the
concept a rule rather than a judgement, and that rule is what is being
dropped.

**Become a full social app (ratings, tournaments, coaches) to match
PlaySpot.** Not decided, and not implied by this record. The jobs above are
the scope; anything outside them is its own decision when it comes up.

## Consequences

- `docs/INIT_CONCEPT.md` §2 and its "no matchmaking" line are superseded by
  this record and say so.
- Finding a game needs domain language the glossary does not have yet — what
  an open seat is, whether a level is shown and who sets it. Settle it in
  `CONTEXT.md` before code, not in it.
- Tutorials are content before they are code: their languages (the audience is
  Georgian-, Russian- and English-speaking) and their format want deciding
  before the first screen.
- Unchanged: the app does not book and does not pay for anyone. Finding a game
  does not reopen that; booking would be a decision of its own.
- Unchanged: coverage stays the first job. A game nobody can find a court for
  is not a game.
