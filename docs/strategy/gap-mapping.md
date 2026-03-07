# 🗺️ Gap → Project Mapping Analysis

> Analysis of which project each gap should be implemented in, or whether a new project is needed.
>
> Based on actual repo status as of March 7, 2026.

---

## Current Status by Repo

| Repo | Tech | Status | What exists |
|:--|:--|:--|:--|
| 🧠 **Mimir** | Rust (Axum+Rig.rs), Next.js 14 | ✅ Sprint 1-23 | Multi-Tenant IAM, Dashboard, RAG Pipeline, Data Ingress, Agent Builder, Knowledge Graph, Code Refactoring |
| 🛡️ **Heimdall** | Rust (Axum) | ✅ Production | Gateway proxy, SSE streaming, Prometheus |
| ⚡ **Bifrost** | Python (FastAPI) | 🚧 Scaffolding | Project structure, Dockerfile |
| 🐺 **Fenrir** | Rust (ZeroClaw) | 📋 Planned | README + design |
| 🏰 **Asgard** | — | 📄 Docs | README, architecture.md |

---

## 🔴 Critical Gaps

### 1. Centralized Auth — 🌳 Yggdrasil (Zitadel)

> ✅ **Decided:** Use Zitadel as Yggdrasil
> 📄 See details at [yggdrasil-auth-selection.md](../technical/yggdrasil-auth-selection.md)

| Where to implement | Action |
|:--|:--|
| 🏰 **Asgard** docker-compose | Deploy Zitadel + Postgres |
| 🛡️ **Heimdall** | Validate Zitadel JWT |
| 🧠 **Mimir** | Delegate login → Zitadel (OIDC) |
| ⚡ **Bifrost** | Validate Zitadel JWT middleware |

### 2. Unified Docker Compose → 🏰 Asgard

| What | Details |
|:--|:--|
| **Goal** | Single `docker compose up` starts entire Asgard stack |
| **Services** | Heimdall, Mimir (API + Dashboard), Bifrost, Qdrant, MariaDB, Yggdrasil (Zitadel + Postgres) |
| **File** | `docker-compose.yml` + `.env.example` |
| **Health checks** | All services must pass before marking healthy |

### 3. Backup/Restore → 🏰 Asgard `scripts/backup.sh`

| What | Details |
|:--|:--|
| **Scope** | MariaDB dump + Qdrant snapshots + Zitadel export + config files |
| **Restore** | `scripts/restore.sh <backup-dir>` — full restore from backup |
| **Automation** | Cron-compatible, optional S3/MinIO upload |

### 4. Bifrost Agent Runtime → ⚡ Bifrost

| What | Details |
|:--|:--|
| **MVP scope** | ReAct loop, tool calling via MCP, session management |
| **APIs** | `POST /v1/agents/{id}/run` — execute agent with streaming |
| **Integration** | Calls Heimdall for LLM, Mimir for RAG, Fenrir for computer use |
| **Dependencies** | Heimdall must be running, Mimir optional |

### 5. Setup Wizard → 🏰 Asgard `scripts/setup.sh` + 🧠 Mimir Web UI

| What | Details |
|:--|:--|
| **CLI** | Interactive setup: detect hardware, choose backends, generate `.env` |
| **Web UI** | First-run wizard in Mimir Dashboard: configure LLM, create admin user |
| **Auto-detect** | Detect Apple Silicon vs NVIDIA → suggest MLX or vLLM |

### 6. Heimdall vLLM Backend → 🛡️ Heimdall

### 7. A2A Protocol (Agent-to-Agent) → 🧠 Mimir + ⚡ Bifrost

> ✅ **Decided:** Support A2A in Mimir

[A2A](https://github.com/google/A2A) is an open standard from Google (hosted by Linux Foundation) enabling cross-platform agent communication.

| | |
|:--|:--|
| **Standard** | HTTP + JSON-RPC + SSE (standard web stack) |
| **Complements MCP** | MCP = agent ↔ tools, **A2A = agent ↔ agent** |
| **Agent Card** | JSON describing agent capabilities → used for discovery |
| **Task lifecycle** | submitted → working → completed/failed |

| Where to implement | Action |
|:--|:--|
| 🧠 **Mimir** | A2A Server — expose agents as A2A endpoints + Agent Card registry |
| ⚡ **Bifrost** | A2A Client — enable agents to call external A2A agents |
| 🛡️ **Heimdall** | A2A proxy/auth — route + validate A2A requests |

---

## 🟡 Important Gaps (Enterprise Track)

| Gap | Implement in | Rationale |
|:--|:--|:--|
| **Audit Log** | 🧠 Mimir | Already has DB + API layer |
| **Rate Limiting** | 🛡️ Heimdall | Gateway = inspection point |
| **SSO** | 🌳 Zitadel | Included for free |
| **HA / Clustering** | 🏰 Asgard compose | Docker Swarm/K8s config |
| **Usage Analytics** | 🧠 Mimir Dashboard | Add analytics page |
| **Model Management UI** | 🧠 Mimir Dashboard | Add model management page |

---

## 📊 Summary

```mermaid
graph LR
    subgraph asgard["🏰 Asgard — 4 items"]
        A1["Docker Compose"]
        A2["Backup Scripts"]
        A3["Setup CLI"]
        A4["HA Config"]
    end

    subgraph heimdall["🛡️ Heimdall — 4 items"]
        H1["JWT Validation"]
        H2["Rate Limiting"]
        H3["vLLM Backend"]
        H4["Intelligent Router"]
    end

    subgraph mimir["🧠 Mimir — 8 items"]
        M1["SSO Support"]
        M2["Audit Log"]
        M3["Usage Analytics"]
        M4["Model Mgmt UI"]
        M5["Agent Marketplace"]
        M6["Setup Wizard UI"]
        M7["A2A Server"]
        M8["Workflow Builder"]
    end

    subgraph bifrost["⚡ Bifrost — 4 items"]
        B1["Agent Runtime"]
        B2["Plugin System"]
        B3["Webhook / Events"]
        B4["A2A Client"]
    end
```

> **No new projects needed** — every gap maps to an existing project.

---

*📅 Last updated: March 2026*
