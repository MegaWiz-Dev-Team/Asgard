# Release Notes — Asgard AI Platform

## v1.1-alpha — Várðr & Docker Verified (2026-03-13)

### 🛡️ New Component: Várðr
Monitoring dashboard built in Rust (Axum) — real-time service health, Docker logs, and container metrics.

### 🐳 Docker Compose Verified
All 11 services build and start successfully with `docker compose up`:

| Service | Port | Status |
|:--|:--|:--|
| 🧠 Mimir API | :3000 | ✅ Healthy |
| 🖥️ Mimir Dashboard | :3001 | ✅ Running |
| ⚡ Bifrost | :8100 | ✅ Healthy |
| 🐺 Fenrir | :8200 | ✅ Healthy |
| 🌳 Yggdrasil | :8085 | ✅ Running |
| 🛡️ Várðr | :9090 | ✅ Healthy |
| 🗄️ MariaDB | :3306 | ✅ Healthy |
| 🐘 PostgreSQL | :5432 | ✅ Healthy |
| 🔍 Qdrant | :6333 | ✅ Running |
| 📦 Redis | :6379 | ✅ Running |
| 🕸️ Neo4j | :7474 | ✅ Running |

### 🔧 Fixes
- Zitadel masterkey: exactly 32 bytes + `--masterkeyFromEnv` + `--tlsMode disabled`
- Mimir API: `MARIADB_URL` → `DATABASE_URL`
- Bifrost healthcheck: `/health` → `/healthz`

### 📦 Components (7 + infra)
| Component | Version | Tests |
|:--|:--|:--|
| 🛡️ Heimdall | v0.4.0 | Benchmarked |
| 🧠 Mimir | Sprint 29 | 255+ |
| ⚡ Bifrost | v0.5.0 | 99 |
| 🐺 Fenrir | v0.2.0 | 35 |
| 🏥 Eir | v0.3.0 | 47 |
| 🌳 Yggdrasil | v0.2.0 | 19 |
| 🛡️ Várðr | v0.1.0 | 5 |
| **Total** | | **460+** |

---

## v1.0-alpha — Phase 1 Complete (2026-03-12)

> **Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.**

### 🏰 Platform Milestone
All 6 components have completed Sprint 1 or later. The entire platform can be started with a single `docker compose up` command.

### 📦 Components
| Component | Version | Tests | Highlights |
|:--|:--|:--|:--|
| 🛡️ Heimdall | v0.4.0 | Benchmarked | Multi-backend LLM Gateway (Ollama/MLX/Gemini/OpenAI) |
| 🧠 Mimir | Sprint 28 | 255+ | RAG Pipeline + Agent Builder + Dashboard |
| ⚡ Bifrost | v0.4.0 | 99 | ReAct + MCP + Multi-Agent + PSO |
| 🐺 Fenrir | v0.1.0 | 35 | MCP Server + FHIR R4 + Browser Use |
| 🏥 Eir | v0.3.0 | 47 | Rust API Gateway + Agent Tools + A2A |
| 🌳 Yggdrasil | v0.1.0 | 19 | Zitadel Auth + JWT SDK |
| **Total** | | **455+** | |

### 📄 ISO 29110 Documentation
Every component has complete PM (Project Plan, Sprint Reports, Status) and SI (Requirements, Design, Traceability, Test Reports) documentation.

---

*Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.*
