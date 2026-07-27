# The poller is a process, not a job queue

Splitting the bot, the poller and the mini app into three containers raised the
obvious question of whether the poller should become Sidekiq work. It should
not: the three processes are three Kamal roles built from one image with
different `cmd`s, and the poller stays a `rufus-scheduler` loop.

## Considered options

**Sidekiq with Redis.** Rejected. Its central feature is a queue with parallel
workers, and parallelism here is forbidden on purpose — clubs run on shared
hosting, so one global interval walks them sequentially (see "Known limits" in
the README). Buying a queue in order to set `concurrency: 1` is paying for the
part we must switch off. Periodic scheduling is not in the free edition either,
so `every 4m` would mean `sidekiq-cron` on top. Retries already exist twice
over: `faraday-retry` backs off on 429/5xx, and a crashed tick is rescued and
logged rather than fatal. Against all that, Redis would be the first stateful
dependency on a box whose whole design is one process and one file.

**Three roles, one image.** Chosen. Independent restart and isolation — the
things actually wanted from the split — come from the container boundary, not
from a queue. Deploying the mini app no longer interrupts polling, and the
poller's code does not change at all; it only moves into its own entrypoint.

## Consequences

Two processes now write to one SQLite file across a bind mount. WAL and
`busy_timeout` were already set for the threads inside the old single process
and carry over, because the containers share a kernel and a filesystem — but
the "one process, one file" line in `config/deploy.yml` stops being true and
has to say so.

Revisit this if background work appears that a scheduler genuinely cannot do:
per-job retry state worth inspecting, or fan-out across many clubs with
per-host limits.
