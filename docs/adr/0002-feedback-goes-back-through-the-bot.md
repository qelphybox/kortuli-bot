# Feedback goes back through the bot

The mini app needed a way for people to say "this is broken" or "please add X".
The shape chosen is: a per-screen pill in the app deep-links to the bot chat,
where any non-command message is forwarded to the owner's Telegram with a
canned acknowledgement. Explicitly re-opens a conversational surface the bot
had just been stripped of.

## Considered options

**An in-app form.** Rejected. A textarea plus Submit inside the mini app is
the shape most consistent with the recent "the app is a better form"
direction, and needs no new state on the bot side. But it can only carry
text. People reporting a wrong price or a broken booking flow reach for a
screenshot; people describing a bug in a language they don't write well reach
for a voice note. Building multi-part upload, storage, and playback into the
mini app to catch those cases is an entire feature; a Telegram chat already
is that feature.

**Chat with the bot.** Chosen. `forwardMessage` handles text, photo, video,
voice, document, sticker, animation, location, contact, poll and dice
natively, in one API call, with the original sender preserved. The pills in
the app carry contextual copy ("Missing a club? Tell us", "Times look wrong?
Tell us") and deep-link to `t.me/<bot>?start=feedback`, which triggers a
`/start feedback` the bot answers with the same prompt as a bare `/feedback`.
Everything else the bot sees, except `/start`, is treated as feedback and
forwarded.

## Consequences

The invariant set in the "retire the chat wizard" commit — *every message
gets the same welcome* — no longer holds. The new invariant is narrower:
`/start` (with or without payload) and `/feedback` are the only commands; any
other update is a message to the owner. Readers of `handlers.rb` who
remember the earlier shape need to see this ADR to understand why the
dispatch grew back.

The loop is deliberately one-way. Telegram forbids a bot from initiating a
chat, and building a reply-routing layer on top of forwarded messages is a
support-desk-shaped project the bot is not. The owner reads forwards in
their own chat and, if a reply is warranted, writes to the user by hand from
the forwarded `@username`. Revisit if the same reply starts being written
five times a week.

Delivery is fire-and-forget: a failed `forwardMessage` is logged and dropped.
Nothing about this bot earns revenue, and losing the occasional bug report is
a lower cost than a persistence layer, an admin screen, and a retention
policy. Revisit if the volume of feedback ever justifies searching it.
