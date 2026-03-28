# 🏰 Asgard — Port Allocation & Startup Guide

> Single source of truth for all port assignments across the Asgard AI Platform.
> All components must follow this map to avoid conflicts on shared hardware.

## 📋 Full Port Map

### 🌐 External Access (Ingress & LoadBalancer)

| URL / Port | Service | Component | Stack |
|------------|---------|-----------|-------|
| `mimir.asgard.local` | Mimir Dashboard | 🧠 Mimir | Next.js |
| `api.asgard.local` | Mimir API (Backend) | 🧠 Mimir | Rust/Axum |
| `bifrost.asgard.local` | Bifrost (Agent Runtime) | ⚡ Bifrost | Python/FastAPI |
| `fenrir.asgard.local` | Fenrir (Computer Use) | 🐺 Fenrir | Python |
| `forseti.asgard.local` | Forseti | ⚖️ Forseti |
| `auth.asgard.local` | Yggdrasil (Auth) | 🌳 Yggdrasil | Zitadel |
| `monitor.asgard.local` | Várðr (Monitoring) | 🛡️ Várðr | Rust |
| `localhost:80` & `443` | Eir (OpenEMR) | 🏥 Eir | PHP (LoadBalancer) |
| `localhost:3005`   | Hermodr-Eir (Chat) | 📨 Messaging | LoadBalancer |

### ☸️ Internal K3s Services (`asgard` namespace)

| Internal Port | Service | Target Port | Component |
|---------------|---------|-------------|-----------|
| `3000` | Mimir Dashboard | `3000` | 🧠 Mimir |
| `8080` | Mimir API | `8080` | 🧠 Mimir |
| `8100` | Bifrost | `8100` | ⚡ Bifrost |
| `8200` | Fenrir | `8200` | 🐺 Fenrir |
| `5555` | Forseti | `5555` | ⚖️ Forseti |
| `8080` | Yggdrasil | `8080` | 🌳 Yggdrasil |
| `9090` | Várðr | `9090` | 🛡️ Várðr |
| `8090` | Hermodr | `3000` | 📨 Messaging |
| `3000` | Eir Gateway | `8300` | 💊 API Gateway |
| `8600` | Pageindex | `8600` | 🔍 Search |
| `8700` | Mjolnir | `8700` | 🔨 Utility |
| `9200` | Ratatoskr | `9200` | 🐿️ Browser API |

### 🤖 LLM Backends (Native Host)

| Port | Service | Component | Protocol |
|------|---------|-----------|----------|
| `8081` | mlx_lm (text) | 🍎 MLX | OpenAI |
| `8082` | mlx_vlm (vision) | 👁️ MLX VLM | OpenAI |
| `8083` | llama.cpp | 🦙 GGUF | OpenAI |
| `8084` | vLLM | 🟢 NVIDIA | OpenAI |
| `11434` | Ollama | 🐫 Ollama | Ollama |
| `8080` | Heimdall Gateway | 🛡️ Heimdall | Proxy |
| `8001` | Embedding Server | 🧮 MLX bge-m3| REST |

### 💾 Infrastructure (K3s)

| Port | Service | Component |
|------|---------|-----------|
| `3306` | MariaDB | 💾 Database |
| `5432` | PostgreSQL | 🐘 Database |
| `6333` / `6334`| Qdrant | 📊 Vector DB |
| `6379` | Redis | ⚡ Cache |
| `7474` / `7687`| Neo4j | 🔗 Graph DB |

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
