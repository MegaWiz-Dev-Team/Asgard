# 🏰 Asgard — Port Allocation & Startup Guide

> Single source of truth for all port assignments across the Asgard AI Platform.
> All components must follow this map to avoid conflicts on shared hardware.

## 📋 Full Port Map

### 🌐 External Access (User-facing)

| Port | Service | Component | Stack | Repo |
|------|---------|-----------|-------|------|
| `3000` | Mimir API (Backend) | 🧠 Mimir | Rust/Axum | [Mimir](https://github.com/megacare-dev/Mimir) |
| `3001` | Mimir Dashboard | 🧠 Mimir | Next.js | [Mimir](https://github.com/megacare-dev/Mimir) |
| `8080` | Heimdall Gateway | 🛡️ Heimdall | Rust/Axum | [Heimdall](https://github.com/megacare-dev/mega-llm-server) |
| `8085` | Yggdrasil (Auth) | 🌳 Yggdrasil | Zitadel | *reserved* |
| `8100` | Bifrost (Agent Runtime) | ⚡ Bifrost | Python/FastAPI | *reserved* |

### 🤖 LLM Backends (Internal)

| Port | Service | Component | Protocol |
|------|---------|-----------|----------|
| `8081` | mlx_lm (text) | 🍎 MLX | OpenAI-compatible |
| `8082` | mlx_vlm (vision) | 👁️ MLX VLM | OpenAI-compatible |
| `8083` | llama.cpp | 🦙 GGUF | OpenAI-compatible |
| `8084` | vLLM | 🟢 NVIDIA | OpenAI-compatible |
| `11434` | Ollama | 🐫 Ollama | Ollama API |

### 🧮 AI Services (Internal)

| Port | Service | Component | Protocol |
|------|---------|-----------|----------|
| `8001` | Embedding Server | 🧮 MLX bge-m3 | REST |
| `8200` | Fenrir (Computer Use) | 🐺 Fenrir | MCP | *reserved* |
| `80` | Eir (OpenEMR) | 🏥 Eir | HTTP/FHIR | *reserved* |

### 💾 Infrastructure

| Port | Service | Component |
|------|---------|-----------|
| `3306` | MariaDB 11 | 💾 Database |
| `6333` | Qdrant (HTTP) | 📊 Vector DB |
| `6334` | Qdrant (gRPC) | 📊 Vector DB |
| `6379` | Redis 7 | ⚡ Cache |
| `7474` | Neo4j (Browser) | 🔗 Graph DB |
| `7687` | Neo4j (Bolt) | 🔗 Graph DB |
| `8201` | Vault 1.15 | 🔐 Secrets |
| `9000` | RustFS (S3 API) | 📦 Object Storage |
| `9001` | RustFS (Console) | 📦 Object Storage |

---

## 🚀 Startup Order

All Asgard services must be started in this order due to dependencies:

```
Phase 1: Infrastructure (Docker)
    ↓
Phase 2: LLM Backends (Heimdall + MLX)
    ↓
Phase 3: Application (Mimir Backend + Dashboard)
```

### Phase 1 — Infrastructure

Start Docker services (MariaDB, Qdrant, Redis, RustFS, Vault, Neo4j):

```bash
cd ~/Documents/Mimir
docker compose up -d
```

Wait for MariaDB to be healthy:
```bash
docker exec mimir_mariadb healthcheck.sh --connect --innodb_initialized
```

Verify all containers:
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected output:
```
NAMES           STATUS          PORTS
mimir_mariadb   Up (healthy)    0.0.0.0:3306->3306/tcp
mimir_qdrant    Up              0.0.0.0:6333-6334->6333-6334/tcp
mimir_redis     Up              0.0.0.0:6379->6379/tcp
mimir_rustfs    Up              0.0.0.0:9000-9001->9000-9001/tcp
mimir_vault     Up (healthy)    0.0.0.0:8201->8200/tcp
mimir_neo4j     Up              0.0.0.0:7474->7474/tcp, 0.0.0.0:7687->7687/tcp
```

### Phase 2 — LLM Backends (Heimdall)

```bash
cd ~/Documents/Heimdall
./scripts/start.sh
```

This starts:
1. **MLX Backend** on `:8081` — loads the LLM model into memory
2. **Embedding Server** on `:8001` — BAAI/bge-m3 embeddings
3. **Heimdall Gateway** on `:8080` — proxies requests to backends

Verify:
```bash
curl http://localhost:8080/health
curl http://localhost:8080/v1/models
```

### Phase 3 — Application (Mimir)

**Backend** (terminal 1):
```bash
cd ~/Documents/Mimir/ro-ai-bridge
./target/release/ro-ai-bridge
# or: cargo run (for development)
```
→ API: http://localhost:3000

**Dashboard** (terminal 2):
```bash
cd ~/Documents/Mimir/ro-ai-dashboard
npm start
# or: npm run dev (for development)
```
→ Dashboard: http://localhost:3001

---

## ✅ Health Check — All Services

```bash
# Infrastructure
curl -sf http://localhost:6333/healthz && echo "Qdrant ✅"
docker exec mimir_redis redis-cli ping
curl -sf http://localhost:8201/v1/sys/health > /dev/null && echo "Vault ✅"

# LLM
curl -sf http://localhost:8080/health && echo "Heimdall ✅"
curl -sf http://localhost:8001/health && echo "Embedding ✅"

# Application
curl -sf http://localhost:3000/health && echo "Mimir API ✅"
curl -sf http://localhost:3001 > /dev/null && echo "Dashboard ✅"
```

---

## 🛑 Shutdown Order (Reverse)

```bash
# Phase 3: Stop Mimir (Ctrl+C in terminals)

# Phase 2: Stop Heimdall
cd ~/Documents/Heimdall
./scripts/stop.sh

# Phase 1: Stop Infrastructure
cd ~/Documents/Mimir
docker compose down
```

---

## 🖥️ Reference Hardware

| Spec | Value |
|------|-------|
| Machine | Mac Mini M4 Pro |
| RAM | 64GB Unified Memory |
| CPU | 14-core (10P + 4E) |
| GPU | 20-core |
| Memory Bandwidth | 273 GB/s |
| Storage | 1TB SSD + Samsung T7 Shield (external models) |
