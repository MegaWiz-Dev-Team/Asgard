---
name: docker-deployment
description: "Guide Docker Compose orchestration, service health checks, environment configuration, and production deployment for the Asgard platform (10 services)."
---

# Docker Deployment & Orchestration

> "One command to rule them all: `docker compose up`"

## Purpose

Deploy, manage, and troubleshoot the full Asgard stack via Docker Compose. Covers development, staging, and production configurations.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docker-compose.yml` | Main orchestration file (10 services) |
| `.env.example` | Required environment variables |
| `docs/architecture.md` | Service dependencies and data flow |

---

## Process

### 1️⃣ Service Inventory

| Service | Port | Health Check | Depends On |
|---------|------|-------------|------------|
| Heimdall (LLM Gateway) | 8000 | `/health` | — |
| Mimir API (Rust) | 3100 | `/health` | MariaDB, Qdrant |
| Mimir Dashboard (Next.js) | 3000 | `/` | Mimir API |
| Bifrost (Agent Runtime) | 8100 | `/health` | Heimdall |
| Fenrir (Computer Use) | 8200 | `/health` | — |
| Eir Gateway (Rust) | 8300 | `/health` | OpenEMR |
| OpenEMR | 8080 | `/` | MariaDB |
| Yggdrasil (Zitadel) | 8888 | `/debug/ready` | PostgreSQL |
| MariaDB | 3306 | `mysqladmin ping` | — |
| Qdrant | 6333 | `/health` | — |

### 2️⃣ Environment Setup

```bash
# 1. Copy example config
cp .env.example .env

# 2. Generate required secrets
openssl rand -hex 32  # For JWT secrets, DB passwords

# 3. Review and fill all required variables
cat .env | grep -E "^[A-Z].*=$"  # Find empty required vars
```

**Critical variables to set:**
- `MARIADB_ROOT_PASSWORD` — Database root password
- `HEIMDALL_API_KEY` — LLM Gateway auth
- `ZITADEL_MASTERKEY` — Auth service master key
- `QDRANT_API_KEY` — Vector DB auth

### 3️⃣ Deployment Commands

```bash
# Development (with hot-reload where supported)
docker compose up -d

# Production (with build)
docker compose -f docker-compose.yml up -d --build

# Specific service only
docker compose up -d heimdall mimir-api

# View logs
docker compose logs -f --tail=100 [service-name]

# Restart a service
docker compose restart [service-name]

# Full teardown (preserves volumes)
docker compose down

# Full teardown (destroys data)
docker compose down -v
```

### 4️⃣ Health Check Verification

```bash
# Quick health check all services
for svc in heimdall:8000 mimir-api:3100 bifrost:8100 fenrir:8200 eir:8300; do
  name=$(echo $svc | cut -d: -f1)
  port=$(echo $svc | cut -d: -f2)
  status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port/health)
  echo "$name: $status"
done
```

### 5️⃣ Production Hardening

```yaml
# Add to each service in docker-compose.yml:
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 4G
    reservations:
      cpus: '0.5'
      memory: 512M
  restart_policy:
    condition: on-failure
    delay: 5s
    max_attempts: 3
```

### 6️⃣ Troubleshooting Playbook

| Symptom | Check | Fix |
|---------|-------|-----|
| Service won't start | `docker compose logs [svc]` | Check env vars, port conflicts |
| Health check failing | `curl localhost:PORT/health` | Wait for dependencies, check DB conn |
| Out of memory | `docker stats` | Increase resource limits |
| Port conflict | `lsof -i :PORT` | Change port mapping in compose |
| Build cache stale | — | `docker compose build --no-cache` |
| Volume permissions | `ls -la` on mount | Set correct UID/GID in Dockerfile |

### 7️⃣ Output

Save deployment runbooks to `docs/technical/deployment-guide.md`

---

## Key Principles
- Always use `.env` for secrets — never hardcode
- Health checks should verify actual functionality, not just port binding
- Start dependencies first (DB → API → Frontend)
- Log aggregation is essential for multi-service debugging

## When to Use
Initial deployment, adding a new service, troubleshooting failures, or preparing production environment.
