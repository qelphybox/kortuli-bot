# syntax=docker/dockerfile:1

# There is no web server here — this image runs one long-lived process that
# polls Telegram and a few booking sites. No ports are exposed and nothing
# listens, which is why the Kamal role sets `proxy: false`.
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

# No HEALTHCHECK on purpose. The honest one — "is the poll loop still
# ticking?" — needs a heartbeat the MVP deliberately does not have, and a
# process-is-alive check would only restate what Docker already reports.
CMD ["bundle", "exec", "bin/bot"]
