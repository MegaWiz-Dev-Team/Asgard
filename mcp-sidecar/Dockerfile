# ╔══════════════════════════════════════════════════╗
# ║  MCP Sidecar — Multi-stage Rust Build            ║
# ╚══════════════════════════════════════════════════╝

FROM rust:1.82-slim AS builder

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src/ src/

RUN cargo build --release

# Runtime
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/mcp-sidecar /usr/local/bin/mcp-sidecar

# Configured via env vars:
#   SERVICE_NAME  — "yggdrasil" or "eir" (selects tool set)
#   UPSTREAM_URL  — base URL to proxy REST calls to
#   PORT          — listen port (default: 8090)

EXPOSE 8090
CMD ["mcp-sidecar"]
