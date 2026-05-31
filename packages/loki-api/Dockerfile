# Loki API — Security Testing Handler
# Provides REST endpoints for Hermodr MCP tool execution

FROM rust:1.88-slim-bookworm AS builder

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN cargo build --release

# Runtime
FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/loki-api /usr/local/bin/loki-api

ENV PORT=8000
ENV BIFROST_URL=http://bifrost:8000
ENV HEIMDALL_URL=http://heimdall:8080
ENV MIMIR_URL=http://mimir-api:8090
ENV SYN_URL=http://syn:8000
ENV QDRANT_URL=http://qdrant:6333
ENV MARIADB_HOST=mariadb
ENV TENANT_ID=asgard_platform

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["loki-api"]
