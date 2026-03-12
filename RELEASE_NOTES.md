# Release Notes — Asgard AI Platform

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

### 🐳 Unified Docker Compose
```bash
cd ~/Developer/Asgard
docker compose up -d        # Core (10 services)
docker compose --profile full up -d  # + OpenEMR
```

### Services
- 💾 MariaDB 11 · PostgreSQL 16 · Qdrant · Redis 7 · Neo4j 5
- 🌳 Yggdrasil (Zitadel :8085)
- 🧠 Mimir API (:3000) + Dashboard (:3001)
- ⚡ Bifrost (:8100)
- 🐺 Fenrir (:8200)
- 🏥 Eir/OpenEMR (:80) — optional profile

### 📄 ISO 29110 Documentation
Every component has complete PM (Project Plan, Sprint Reports, Status) and SI (Requirements, Design, Traceability, Test Reports) documentation.

---

*Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.*
