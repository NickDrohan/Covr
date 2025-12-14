# Dockerfile for Covr Gateway (Elixir/Phoenix)
# Optimized for Fly.io deployment

# Build stage - using known working image tags
ARG ELIXIR_VERSION=1.16.2
ARG OTP_VERSION=26.2.5
ARG DEBIAN_VERSION=bookworm-20240513-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Copy mix files first (for dependency caching)
COPY mix.exs ./
COPY apps/gateway/mix.exs apps/gateway/
COPY apps/image_store/mix.exs apps/image_store/

# Copy config
COPY config/config.exs config/prod.exs config/

# Get and compile dependencies
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy runtime config
COPY config/runtime.exs config/

# Copy application code
COPY apps apps
COPY rel rel

# Compile the release
RUN mix compile

# Build release
RUN mix release covr

# Runtime stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV="prod"

# Copy the release from builder
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/covr ./

USER nobody

# Run migrations on startup, then start the server
CMD ["/app/bin/covr", "start"]
