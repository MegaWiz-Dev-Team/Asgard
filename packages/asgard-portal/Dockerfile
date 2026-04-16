# Builder stage
FROM rust:1.88-slim-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
# Build the standalone binary
RUN cargo build --release

# Runner stage
FROM debian:bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/asgard-portal /usr/local/bin/asgard-portal

EXPOSE 30005
CMD ["asgard-portal"]
