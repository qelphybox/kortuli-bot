# syntax=docker/dockerfile:1

# One image, three entrypoints: bin/bot long-polls Telegram, bin/poller walks
# the clubs, bin/web serves the mini app. Only the last one listens, which is
# why the other two Kamal roles set `proxy: false` and this exposes a port that
# two of the three ignore.
ARG RUBY_VERSION=4.0.0
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /app

ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test"

# ---------------------------------------------------------------- build stage
FROM base AS build

# sqlite3 2.x ships precompiled native gems for linux, so this is belt and
# braces — it keeps the build working if a gem ever falls back to source.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf "${BUNDLE_PATH}"/ruby/*/cache

COPY . .

# -------------------------------------------------------------- runtime stage
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /app /app

# The database is a bind mount at /app/data. Owning it in the image is what
# gives the mount point the right uid before Docker mounts over it.
RUN groupadd --system --gid 1000 booking && \
    useradd booking --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /app/data && \
    chown -R booking:booking /app

USER booking:booking

EXPOSE 8080

# No HEALTHCHECK on purpose. The mini app answers /up and kamal-proxy asks it,
# which covers the process that can be asked. For the other two the honest
# check — "is the poll loop still ticking?" — needs a heartbeat the MVP
# deliberately does not have, and a process-is-alive check would only restate
# what Docker already reports.
#
# The default is the bot because Kamal's other two roles name their own
# command; this is only what you get running the image bare.
CMD ["bundle", "exec", "bin/bot"]
