# Release Notes — Asgard AI Platform

## v1.2-alpha — Sprint 38 Release (2026-04-22)

> Unified platform bump aligning all 14 services, 11 Helm sub-charts, and the umbrella chart to a single consistent release on top of the OrbStack K8s migration delivered in Sprints 37–38.

### 🧩 Umbrella
- Helm umbrella `charts/asgard` — `version 0.1.0 → 0.2.0`, `appVersion 0.37.0 → 0.38.0`
- All 11 sub-charts bumped `0.1.0 → 0.2.0`

### 📦 Service bumps (+0.1.0 minor)

| Component | From | To | Manifest |
|:--|:--|:--|:--|
| 🛡️ Heimdall | 0.4.0 | **0.5.0** | `gateway/Cargo.toml` |
| 🧠 Mimir bridge | 1.1.0 | **1.2.0** | `ro-ai-bridge/Cargo.toml` |
| 🖥️ Mimir Dashboard | 1.1.0 | **1.2.0** | `ro-ai-dashboard/package.json` |
| ⚡ Bifrost | 0.1.0 | **0.2.0** | `Cargo.toml` |
| 🏥 Eir | 0.2.0 | **0.3.0** | `package.json` |
| 🐺 Fenrir | 0.1.0 | **0.2.0** | `pyproject.toml` |
| 🌳 Yggdrasil | 0.1.0 | **0.2.0** | `pyproject.toml` |
| 🛡️ Várðr | 0.4.0 | **0.5.0** | `Cargo.toml` |
| ⚖️ Forseti | 0.1.0 | **0.2.0** | `pyproject.toml` |
| 🔨 Mjölnir | 0.1.0 | **0.2.0** | `Cargo.toml` |
| 🐿️ Ratatoskr | 0.1.0 | **0.2.0** | `Cargo.toml` |
| 📨 Hermóðr | 0.1.0 | **0.2.0** | `Cargo.toml` |
| 🐦‍⬛ Huginn | 0.2.1 | **0.3.0** | `Cargo.toml` |
| 🐦 Muninn | 0.2.0 | **0.3.0** | `Cargo.toml` |

### 🏗️ Delivered in this release cycle (Sprints 37–38)
- **K3s + Helm + CI/CD** production deployment on Mac Mini (Sprint 37)
- **OrbStack migration** — Colima retired; launchd host now runs Heimdall Gateway + MLX backend + Várðr agent only (Sprint 38)
- **ISO 27001 log pipeline** — launchd `log-shipper` + `log-archiver` → Wazuh Indexer (Týr) with 365-day retention on T7 Shield

### 📊 Live K8s footprint (asgard namespace)
27 pods Running across 14 services; all `/healthz` probes green. Heimdall runs native on host (MLX).

### 🎯 Next (Phase 1 "Shield Wall", Apr 2026)
- ⚡ **Bifrost S8** — AI Guardrails (Thai PII filter, kill switch, hallucination check, handover queue)
- 📦 **Package Extract** — `@asgard/line-connector`, Gmail, TTS, BigQuery NLQ
- 👁️ **Syn** — new OCR/eKYC service (`:8600`)

---

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
- Yggdrasil masterkey: exactly 32 bytes + `--masterkeyFromEnv` + `--tlsMode disabled`
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
| 🌳 Yggdrasil | v0.1.0 | 19 | Auth + JWT SDK |
| **Total** | | **455+** | |

### 📄 ISO 29110 Documentation
Every component has complete PM (Project Plan, Sprint Reports, Status) and SI (Requirements, Design, Traceability, Test Reports) documentation.

---

*Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.*
