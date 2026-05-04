# ── Stage 1: Build ───────────────────────────────────────────────────────────
FROM elixir:1.17.3-otp-26 AS builder

# Install build deps + Node.js 20 (for assets pipeline)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential curl ca-certificates && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Copy dependency manifests; lock file pins exact versions for reproducible builds
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

RUN mix deps.compile

# Install JS deps (needed for esbuild bundling)
COPY assets/package.json assets/
RUN cd assets && npm install --prefer-offline

# Cache-bust argument: pass --build-arg CACHE_BUST=$(date +%s) to force recompile
ARG CACHE_BUST=1
RUN echo "cache bust: $CACHE_BUST"

# Copy application source
COPY config/ config/
COPY lib/ lib/
COPY priv/ priv/
COPY assets/ assets/

# Build frontend assets, then compile + release
RUN mix assets.deploy
RUN mix compile
RUN mix release

# ── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 libncurses6 locales curl && \
    rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app

RUN useradd -m -u 1000 typevault
COPY --from=builder --chown=typevault:typevault /app/_build/prod/rel/typevault ./

USER typevault

ENV MIX_ENV=prod PHX_SERVER=true

EXPOSE 4000

CMD ["bin/typevault", "start"]
