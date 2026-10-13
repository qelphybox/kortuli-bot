# City is an attribute of a Club

Until now every club was in Tbilisi, so nothing in the code knew what a city
was. Clubs in Rustavi, Batumi and Kutaisi are arriving, and the question
`docs/coverage-plan.md` called "the whole design" had to be answered: does a
Watch belong to a city, or only to the clubs a person picked? The shape
chosen is: a City is a setting on a Club (`settings.city`, read as
`Club#city`, Tbilisi when absent), a Watch stores no city at all, and the
city a person is looking at is a filter over the clubs, remembered per person
in a row of its own.

## Considered options

**A city on the Watch.** Rejected. A Watch names clubs, and each of those
clubs already says where it is, so a city stored beside them could only
repeat that or contradict it. The Matcher, the Notifier and the Watches list
are all driven by slugs and needed no change; a watch that happens to name
clubs in two cities is unusual but not wrong, and nothing downstream has to
decide which city it "is".

**A `city` column on `clubs`.** Rejected for now. `config/clubs.yml` is the
source of truth and is mirrored into `settings` on every boot, so a setting
costs one line per entry and no schema change — the same reasoning Wave 4
gives for `settings.district`. Promote it to a column if anything ever needs
to query clubs by city in SQL.

**Carrying the picked city in the URL, as Share does its options.** Rejected.
Share's switch and hour pickers belong to one screen, which is why they live
in its query string. The city decides every screen at once — the dates, a
date's clubs, Share, the directory, the new-watch form — and the tab bar, the
week strip, the stars' post-redirect-get, the back arrows and the Game's
links would all have to pass it on. The first link that forgot would quietly
drop a person in Batumi back into Tbilisi.

**A cookie.** Rejected. It is per device, so the same person would see
Batumi on their phone and Tbilisi on their laptop; and the app has kept to
one signed cookie that says who you are and nothing else.

**A row per person, beside the Favourites.** Chosen. A person here is a
Telegram id and nothing more, so, like `favourites`, the choice is a row
keyed by that id — `preferences(user_id, city)`. Picking is a post from a
switch of buttons that lands back on the screen it was pressed on. One
indexed read per request, memoised with everything else the request reads.
The switch is drawn only once more than one city has an enabled club, on the
three screens a person starts from: the dates, the clubs directory and the
new-watch form.

## Forecast

The Forecast becomes one Open-Meteo point per City, at its centre
(`Weather::CITIES`), fetched for every city with an enabled club in a single
request — Open-Meteo takes a list of coordinates and answers with a list in
the same order. One request keeps the cities on the same model run and means
one failure leaves every city on its last good Forecast, as before. Hours are
stored keyed by city and replaced a city at a time, so a city whose answer
comes back empty keeps what it had; a city no enabled club is in any more is
dropped, rather than left to age on the Dashboard. Everything that reads the
Forecast reads it for a club's own city: the banner and the sinking of open
courts for the picked city, a club's hours, a Game and a freed slot's message
for that club's city whichever is picked.

`forecast_hours` was keyed by the hour alone. SQLite cannot change a primary
key in place, so the schema rebuilds the table with `(city, starts_at)` as
its key and carries the existing rows across as Tbilisi's, in one
transaction, guarded so it runs once — the second guarded change in
`Schema`, beside the Dated watch's column.

## Consequences

A club's own screens — its hours, its Profile, a Game's public link — are
reached by slug and open whatever city is picked: the link may have been
made while another one was. The Watches list shows every watch a person has,
whatever its clubs' cities. The new-watch form offers the picked city's clubs
only, so a watch in two cities is two watches unless somebody picks again
halfway.

A city in `config/clubs.yml` with no point in `Weather::CITIES` gets no
Forecast and its clubs are drawn without weather rather than with a
neighbour's; the refresh says so in the log, and a spec over the config file
refuses one.

The bot's greeting and the page shown outside Telegram still say "Tbilisi":
the bot never touches the database, and neither knows who is asking, so
there is no picked city to name there.

Revisit when the Wave 4 district filter lands — it nests under the city
rather than beside it — or if people start asking to see two cities at once,
which would make the choice a set rather than a single value.
