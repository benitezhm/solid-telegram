# Build stage
FROM elixir:1.15-alpine AS builder

# Install build dependencies
RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Copy dependency files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy assets
COPY assets assets
COPY priv priv

# Copy application files
COPY lib lib
COPY config config

# Install and compile assets
RUN mix assets.setup
RUN mix assets.deploy

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.18

RUN apk add --no-cache openssl ncurses-libs libstdc++ libgcc

WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/my_app ./

# Create a non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    chown -R appuser:appuser /app

USER appuser

# Expose ports
EXPOSE 4000 4369 9000-9100

ENV HOME=/app

CMD ["bin/my_app", "start"]
