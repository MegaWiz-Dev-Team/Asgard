---
description: Start all Asgard services (Docker + Heimdall) and verify health
---

# Start All Services

## When to use
- Starting the full Asgard platform for development
- After a reboot or cold start
- When user says "เปิดทุก service" or "start all services"

## Steps

// turbo-all

1. **Start Colima (Docker runtime)**:
   ```bash
   colima start
   ```

2. **Start all Docker Compose services** (including OpenEMR/Eir with `--profile full`):
   ```bash
   cd /Users/mimir/Developer/Asgard && docker compose --profile full up -d
   ```

3. **Wait for containers to stabilize** (10 seconds):
   ```bash
   sleep 10
   ```

4. **Check container status**:
   ```bash
   cd /Users/mimir/Developer/Asgard && docker compose --profile full ps -a
   ```

5. **Start Heimdall** (LLM Gateway — runs on host, needs MLX/GPU):
   ```bash
   cd /Users/mimir/Developer/Heimdall && bash ./scripts/start.sh
   ```

6. **Verify all health endpoints**:
   ```bash
   echo "=== Health Check ===" && \
   echo -n "Mimir API (3000):    " && curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health && echo "" && \
   echo -n "Mimir Dash (3001):   " && curl -s -o /dev/null -w "%{http_code}" http://localhost:3001 && echo "" && \
   echo -n "Bifrost (8100):      " && curl -s -o /dev/null -w "%{http_code}" http://localhost:8100/healthz && echo "" && \
   echo -n "Fenrir (8200):       " && curl -s -o /dev/null -w "%{http_code}" http://localhost:8200/healthz && echo "" && \
   echo -n "Eir Gateway (8300):  " && curl -s -o /dev/null -w "%{http_code}" http://localhost:8300/healthz && echo "" && \
   echo -n "Yggdrasil (8085):    " && curl -s -o /dev/null -w "%{http_code}" http://localhost:8085/debug/ready && echo "" && \
   echo -n "Vardr (9090):        " && curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/health && echo "" && \
   echo -n "Heimdall (8080):     " && curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health && echo "" && \
   echo -n "OpenEMR (80):        " && curl -s -o /dev/null -w "%{http_code}" http://localhost:80 && echo "" && \
   echo "=== Done ==="
   ```

## Service Summary

| Service | Type | Port | Health |
|---------|------|------|--------|
| MariaDB | Docker | 3306 | healthcheck |
| PostgreSQL | Docker | — | healthcheck |
| Qdrant | Docker | 6333 | — |
| Redis | Docker | 6379 | — |
| Neo4j | Docker | 7474,7687 | — |
| Yggdrasil (Auth) | Docker | 8085 | `/debug/ready` |
| Mimir API | Docker | 3000 | `/health` |
| Mimir Dashboard | Docker | 3001 | `/` |
| Bifrost | Docker | 8100 | `/healthz` |
| Fenrir | Docker | 8200 | `/healthz` |
| Eir (OpenEMR) | Docker (profile: full) | 80 | `/` |
| Eir Gateway | Docker (profile: full) | 8300 | `/healthz` |
| Vardr | Docker | 9090 | `/health` |
| Heimdall LLM | Host (MLX) | 8080 | `/health` |
| Heimdall Embed | Host (MLX) | 8001 | `/health` |

## Notes
- Heimdall runs on **host** (not Docker) because macOS Docker doesn't support GPU/MLX passthrough
- Use `--profile full` to include OpenEMR + Eir Gateway
- To stop everything: `cd /Users/mimir/Developer/Asgard && docker compose --profile full down` + `cd /Users/mimir/Developer/Heimdall && bash ./scripts/stop.sh`
