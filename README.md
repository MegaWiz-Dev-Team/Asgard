# 🏰 Asgard AI Platform

> **Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.** 

> *The realm of the gods — a self-hosted AI agent platform built on Apple Silicon & NVIDIA GPU*

**Asgard** is an open ecosystem of AI services designed to run entirely on local hardware. From LLM inference to autonomous agent execution and computer control — everything runs on-premises with zero cloud dependency.

Originally built to power AI NPCs for **Ragnarok Online**, Asgard has evolved into a general-purpose AI platform for healthcare, knowledge management, and autonomous workflows.

**📚 [Full Documentation →](docs/README.md)** | **🏥 [Architecture Plan →](docs/roadmap/MultiAgent_Architecture_Plan.md)** | **🎨 [Studio Design →](docs/roadmap/MultiAgent_Studio_Design.md)** | **🗓️ [Sprint Plan →](docs/roadmap/MultiAgent_Sprint_Plan.md)** | **🔍 [Gap Analysis →](docs/roadmap/MultiAgent_Gap_Analysis.md)**

---

## 🏗️ Architecture

```mermaid
graph LR
    User["👤 User"] --> Mimir["🧠 Mimir<br/>RAG + Agent Builder"]
    User --> |"Chat"| EirGW["🏥 Eir GW<br/>Chat UI"]

    EirGW --> |"proxy"| Bifrost["⚡ Bifrost<br/>Agent Runtime"]
    Bifrost --> |"LLM"| Heimdall["🛡️ Heimdall<br/>LLM Gateway"]
    Bifrost --> |"MCP"| Mimir
    Bifrost --> |"MCP"| Fenrir["🐺 Fenrir<br/>Computer Use"]
    Bifrost --> |"MCP"| EirGW

    Mimir --> |"scrape"| Ratatoskr["🐿️ Ratatoskr<br/>Browser Service"]
    Bifrost --> |"browse"| Ratatoskr

    EirGW --> |"proxy"| Eir["📋 OpenEMR<br/>FHIR R4"]
    Fenrir --> |"Browser"| Eir

    Heimdall --> LLM["🍎 MLX · llama.cpp · Ollama · vLLM"]

    Yggdrasil["🌳 Yggdrasil<br/>Auth (Zitadel)"] -.-> Heimdall
    Yggdrasil -.-> Mimir
    Yggdrasil -.-> Bifrost

    Vardr["🛡️ Várðr<br/>Monitoring"] -.-> |"docker"| Mimir
    Vardr -.-> |"docker"| Bifrost

    style Mimir fill:#1e1b4b,stroke:#818cf8,color:#c7d2fe
    style Bifrost fill:#451a03,stroke:#f59e0b,color:#fef3c7
    style Heimdall fill:#052e16,stroke:#4ade80,color:#bbf7d0
    style Fenrir fill:#1c1917,stroke:#a8a29e,color:#e7e5e4
    style Ratatoskr fill:#422006,stroke:#fb923c,color:#fed7aa
    style Eir fill:#4a1942,stroke:#e879f9,color:#fae8ff
    style EirGW fill:#4a1942,stroke:#e879f9,color:#fae8ff
    style Yggdrasil fill:#14532d,stroke:#86efac,color:#bbf7d0
    style Vardr fill:#172554,stroke:#3b82f6,color:#bfdbfe
```

---

## 📦 Components

| Component | Description | Tech Stack | Tests | Status |
|:--|:--|:--|:--|:--|
| 🧠 **[Mimir](https://github.com/MegaWiz-Dev-Team/Mimir)** | RAG Pipeline, Agent Builder, Dashboard | Rust (Axum), Next.js 14, MariaDB, Qdrant | 255+ | ✅ Sprint 28 |
| 🛡️ **[Heimdall](https://github.com/MegaWiz-Dev-Team/Heimdall)** | LLM Gateway — multi-backend proxy | Rust (Axum) | Benchmarked | ✅ Production |
| ⚡ **[Bifrost](https://github.com/MegaWiz-Dev-Team/Bifrost)** | Multi-Agent Orchestrator — ReAct, MCP, Skills, Memory | **Rust (Axum + rig.rs)** | 146 | ✅ Sprint 35 |
| 🐺 **[Fenrir](https://github.com/MegaWiz-Dev-Team/Fenrir)** | Computer-Use Agent — Browser Automation + FHIR + Docker Sandbox | Rust + Python sidecar | 47 | ✅ Sprint 1.5 |
| 🏥 **[Eir](https://github.com/MegaWiz-Dev-Team/Eir)** | Rust API Gateway + OpenEMR, Chat UI, MCP Server | Rust (Axum) + PHP | 47 | ✅ Sprint 3 |
| 🌳 **[Yggdrasil](https://github.com/MegaWiz-Dev-Team/Yggdrasil)** | Auth Service — Zitadel OIDC + JWT + FastAPI Auth | Zitadel (Go) + Python | 31 | ✅ Sprint 2 |
| 🛡️ **[Várðr](https://github.com/MegaWiz-Dev-Team/Vardr)** | Monitoring Dashboard — health, logs, metrics | Rust (Axum) | 5 | ✅ Sprint 1 |
| ⚖️ **[Týr](https://github.com/MegaWiz-Dev-Team/Tyr)** | Enterprise SIEM & XDR — Wazuh log parsing, threat hunting | Wazuh + OpenSearch | — | ✅ Active |
| 🐦‍⬛ **[Huginn](https://github.com/MegaWiz-Dev-Team/Huginn)** | Security Scanner + AI Pentest Agent + Performance Test | Python (FastAPI) | — | 🚧 Sprint 1 |
| 🐦 **[Muninn](https://github.com/MegaWiz-Dev-Team/Muninn)** | Issue Watcher + LLM Auto-Fixer | Python (FastAPI) | — | 🚧 Sprint 1 |
| 🐿️ **[Ratatoskr](https://github.com/MegaWiz-Dev-Team/Ratatoskr)** | Shared Browser Service — headless Chromium REST API | Rust (Axum) | — | ✅ Sprint 1 |
| 📨 **[Hermóðr](https://github.com/MegaWiz-Dev-Team/Hermodr)** | Universal MCP Sidecar — JSON-RPC bridge for legacy REST | Rust | — | ✅ v0.1.0 |
| 🏰 **Asgard** *(this repo)* | Docker Compose, docs, strategy, 🔱 Odin (Supervisor) | — | — | ✅ Active |

> **530+ tests** across the entire platform · **MCP** for tool calls · **A2A** for task delegation · **Odin's Ravens** for security

---

## 🎯 Mission

Build a **self-hosted AI platform** that enables:

1. 📚 **Knowledge Management** — Ingest, chunk, embed, and search documents with RAG
2. 🤖 **Autonomous Agents** — Create and deploy agents that reason, use tools, and take actions
3. 🌐 **Computer Control** — Agents that browse the web, fill forms, extract data
4. 🎮 **AI NPCs** — Intelligent characters for Ragnarok Online with memory and personality
5. 🏥 **Healthcare AI** — Medical knowledge assistants with domain-specific models

---

## 🔧 Hardware

#### 🍎 Apple Silicon (MLX / llama.cpp / Ollama)

| Tier | Hardware | Users | Model Size |
|:--|:--|:--|:--|
| Starter | Mac Mini M4 (16GB) | 1-5 | 7B |
| Standard | Mac Mini M4 Pro (36GB) | 10-20 | 14B |
| Pro | Mac Mini M4 Pro (64GB) | 20-50 | 30B+ |
| Max | Mac Studio M4 Ultra (192GB) | 50-200 | 70B+ |

#### 🟢 NVIDIA (vLLM + CUDA)

| Tier | Hardware | Users | Model Size |
|:--|:--|:--|:--|
| DGX Spark | NVIDIA DGX Spark (128GB) | 50-200 | 70B+ |
| DGX Station | NVIDIA DGX Station | 200+ | Multi-model |

> All LLM inference runs locally — zero cloud dependency.

---

## 🗺️ Roadmap

> **[Full Roadmap with Gantt Chart →](docs/strategy/roadmap.md)**

### Phase 1: Foundation ✅
- [x] Heimdall — LLM Gateway (v0.4.0, multi-backend, benchmarked)
- [x] Mimir — RAG Pipeline + Agent Builder + Dashboard (Sprint 28, 255+ tests)
- [x] Bifrost — Agent Runtime (Sprint 4, ReAct + MCP + PSO, 99 tests)
- [x] Eir — Rust API Gateway + OpenEMR (Sprint 3, 47 tests)
- [x] Fenrir — Computer-Use Agent scaffold + OpenEMR Messaging (Sprint 1.5, 47 tests)
- [x] Yggdrasil — Auth Service (Sprint 2, Zitadel + JWT + FastAPI Auth, 31 tests)
- [x] Týr — Security Information & Event Management (Wazuh SIEM, T7 external scaling, macOS FIM agent)
- [x] Unified Docker Compose — 10 services, one command
- [x] AGPL-3.0 licensing + CLA
- [x] Bifrost Sprint 35 — Skills system, long-term memory, context engineering (146 tests)
- [x] Asgard `skills/` — 5 built-in skills (DeerFlow-compatible SKILL.md format)

### Phase 2: Integration & Growth 🚧
- [ ] Eir Sprint 4 — MCP Server (FHIR tools) + Chat UI widget
- [ ] Bifrost Sprint 5 — MCP Integration (Eir + Fenrir clients)
- [ ] Mimir → Bifrost agent deployment via MCP
- [ ] Fenrir MVP — OpenEMR form automation
- [ ] Visual Workflow Builder (ReactFlow)
- [ ] Documentation site (asgardai.dev)
- [ ] Developer Preview (GitHub public)

### Phase 3: Community Launch
- [ ] v1.0 Community Edition
- [ ] Product Hunt / HackerNews launch
- [ ] 3-5 Design Partners

### Enterprise Edition 💰
- [ ] SSO (SAML, OIDC, LDAP) via Zitadel
- [ ] Usage Analytics + Cost Dashboard
- [ ] HA Clustering (multi-node)
- [ ] Priority Support + SLA

---

## 🏛️ Norse Naming

| Name | Origin | Role | Edition |
|:--|:--|:--|:--|
| **Asgard** | Realm of the gods | The platform | Community |
| **Mimir** | God of wisdom | Knowledge & RAG | Community |
| **Heimdall** | Guardian of Bifrost | LLM Gateway | Community |
| **Bifrost** | Rainbow bridge | Agent Runtime | Community |
| **Fenrir** | The great wolf | Computer use | Community |
| **Eir** | Goddess of healing | Clinic management (Gateway + OpenEMR) | Community |
| **Yggdrasil** | The world tree | Auth service | Community |
| **Várðr** | The guardian | Monitoring dashboard | Community |
| **Huginn** | Odin's raven (Thought) | Security Scanner + AI Pentest Agent | Odin's Ravens |
| **Muninn** | Odin's raven (Memory) | Issue Watcher + Auto-Fixer (LLM) | Odin's Ravens |
| **Ratatoskr** | The squirrel on Yggdrasil | Shared Browser Service | Community |
| **Hermóðr** | Messenger of the gods | Universal MCP Sidecar | Community |
| **Odin** | The All-Father | Platform Supervisor | Community |

> **[Huginn & Muninn Roadmap →](docs/roadmap/huginn-muninn.md)**

---

## 📄 License

- **Community**: [AGPL-3.0](LICENSE)
- **Enterprise**: [Commercial License](COMMERCIAL.md)
- **Contributing**: [CLA](CLA.md)

---

<p align="center">
  <strong>🏰 Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.</strong>
  <br/>
  <em>Self-hosted AI. Norse-inspired. Built on Apple Silicon & NVIDIA GPU.</em>
  <br/><br/>
  <a href="https://github.com/MegaWiz-Dev-Team/Mimir">Mimir</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Heimdall">Heimdall</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Bifrost">Bifrost</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Fenrir">Fenrir</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Yggdrasil">Yggdrasil</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Eir">Eir</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Vardr">Várðr</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Ratatoskr">Ratatoskr</a>
</p>
