# 🏰 Asgard v1.0 — Community Edition MVP

> **Release Goal:** *"Anyone can `docker compose up` and have a working self-hosted AI platform with RAG + Agent in 15 minutes."*
>
> **Target Date:** Q4 2026 · **Codename:** Community Launch

---

## MoSCoW Prioritization

### ✅ MUST Have (Release is broken without it)

| # | Feature | Component | Sprint Status | Done Criteria |
|:--|:--|:--|:--|:--|
| M1 | **Unified Docker Compose** | 🏰 Asgard | 📋 Planned | Single `docker compose up` starts all services; health checks pass; `.env.example` complete |
| M2 | **Mimir Core (Sprint 1-23)** | 🧠 Mimir | ✅ Done | 37 features, 23 sprints, 255+ backend tests passing |
| M3 | **Heimdall Gateway** | 🛡️ Heimdall | ✅ Production | Multi-backend routing, SSE streaming, Prometheus metrics |
| M4 | **Bifrost Agent Runtime** | ⚡ Bifrost | 🚧 MVP | ReAct loop works, tool calling via MCP, streaming response |
| M5 | **Yggdrasil Auth** | 🌳 Yggdrasil | 📋 Planned | Yggdrasil running in Docker, Mimir delegates login via OIDC |
| M6 | **Quick Start Guide** | 📖 Docs | 📋 Planned | Tested on clean Mac + Ubuntu; < 15 min to first chat |
| M7 | **Visual Workflow Builder** | 🧠 Mimir | 📋 Planned | ReactFlow canvas, drag-drop nodes, save/load workflows |

### 🔵 SHOULD Have (Important, workaround exists)

| # | Feature | Component | Notes |
|:--|:--|:--|:--|
| S1 | **Heimdall vLLM Backend** | 🛡️ Heimdall | NVIDIA GPU support; workaround = use Ollama |
| S2 | **Backup/Restore CLI** | 🏰 Asgard | `scripts/backup.sh` already exists in Mimir S14b |
| S3 | **Setup Wizard** | 🏰 Asgard | `scripts/setup.sh`; workaround = manual `.env` edit |
| S4 | **A2A Protocol (Server)** | 🧠 Mimir | Agent-to-Agent; workaround = direct API calls |
| S5 | **Documentation Site** | 📖 asgardai.dev | Static site; workaround = GitHub docs/ folder |

### 💡 COULD Have (Nice to have)

| # | Feature | Component | Notes |
|:--|:--|:--|:--|
| C1 | **Agent Template Marketplace** | 🧠 Mimir | Community-contributed agent configs |
| C2 | **A2A Client** | ⚡ Bifrost | Call external agents |
| C3 | **Fenrir MVP** | 🐺 Fenrir | Browser automation; can launch as v1.1 |
| C4 | **Dark/Light Theme Toggle** | 🧠 Mimir | Dashboard UX polish |

### 🚫 WON'T Have (Explicitly v2.0+)

| # | Feature | Why Not v1.0 |
|:--|:--|:--|
| W1 | **HA Clustering** | Enterprise feature; single-node is fine for Community |
| W2 | **SSO (SAML/LDAP)** | Enterprise; Yggdrasil OIDC is sufficient for Community |
| W3 | **White-Label** | Enterprise branding; not needed for Community launch |
| W4 | **Usage Analytics Dashboard** | Enterprise; basic Prometheus metrics are enough |
| W5 | **Windows Support** | Community-contributed; focus on macOS + Linux |
| W6 | **Cloud-hosted SaaS** | Anti-goal per product-direction.md |

---

## Done Criteria for Must-Haves

### M1: Unified Docker Compose
- [ ] Single `docker-compose.yml` starts: Heimdall, Mimir (API + Dashboard), Bifrost, MariaDB, Qdrant, Yggdrasil
- [ ] `.env.example` documents all required variables
- [ ] `docker compose up` from zero → all services healthy in < 5 min
- [ ] Quick Start tested on clean macOS 15 (Apple Silicon) and Ubuntu 24.04

### M4: Bifrost Agent Runtime
- [ ] `POST /v1/agents/{id}/run` executes ReAct loop
- [ ] Streams response via SSE
- [ ] Calls Heimdall for LLM inference
- [ ] Calls Mimir for RAG context retrieval
- [ ] Supports 3+ MCP tools (search, calculate, web_fetch)

### M5: Yggdrasil Auth
- [ ] Yggdrasil container in Docker Compose
- [ ] Mimir delegates login to Yggdrasil via OIDC
- [ ] JWT validation in Heimdall
- [ ] First-run creates default admin user

### M7: Visual Workflow Builder
- [ ] ReactFlow canvas renders in Dashboard
- [ ] Drag-drop node types: LLM, RAG, Tool, Condition, Output
- [ ] Save workflow to database
- [ ] Execute workflow via Bifrost

---

## Launch Checklist

### Code
- [ ] All Must-have features merged and tested
- [ ] Docker images built and pushed to Docker Hub / ghcr.io
- [ ] Version tagged as `v1.0.0`
- [ ] CHANGELOG.md updated

### Documentation
- [ ] README.md updated with v1.0 features
- [ ] Quick Start guide complete and tested
- [ ] API docs published (OpenAPI at /api/docs)
- [ ] Architecture diagrams current

### Community
- [ ] CONTRIBUTING.md ✅
- [ ] CODE_OF_CONDUCT.md ✅
- [ ] Issue templates ✅
- [ ] PR template ✅

### Launch
- [ ] GitHub Release with changelog
- [ ] Product Hunt submission
- [ ] HackerNews "Show HN" post
- [ ] Twitter/X + LinkedIn announcement
- [ ] Blog post: "Why We Built Asgard"
- [ ] Reddit posts: r/selfhosted, r/LocalLLaMA, r/MachineLearning

### Post-Launch (48h)
- [ ] Monitor GitHub issues — respond within 4h
- [ ] Track Docker Hub pull count
- [ ] Collect feedback for v1.1 planning
- [ ] Write "Week 1 Learnings" blog post

---

*📅 Created: March 2026*
