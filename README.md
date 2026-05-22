# 🏰 Asgard AI Platform

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![Commercial License](https://img.shields.io/badge/Commercial-Available-success.svg)](COMMERCIAL.md)
[![Code of Conduct](https://img.shields.io/badge/Contributor_Covenant-2.1-purple.svg)](CODE_OF_CONDUCT.md)
[![Security Policy](https://img.shields.io/badge/Security-Policy-red.svg)](SECURITY.md)

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
    Bifrost --> |"MCP"| Huginn["🐦‍⬛ Huginn<br/>Security Scanner"]

    Mimir --> |"scrape"| Ratatoskr["🐿️ Ratatoskr<br/>Browser Service"]
    Bifrost --> |"browse"| Ratatoskr

    EirGW --> |"proxy"| Eir["📋 OpenEMR<br/>FHIR R4"]
    Fenrir --> |"Browser"| Eir

    Heimdall --> |"PII/DLP gate"| Skuggi["🕶️ Skuggi<br/>Guardrail (in-process)"]
    Heimdall --> LLM["🍎 MLX Backend (LLM)<br/>⚡ ONNX (Embedding)"]

    Yggdrasil["🌳 Yggdrasil<br/>Auth (Zitadel)"] -.-> Heimdall
    Yggdrasil -.-> Mimir
    Yggdrasil -.-> Bifrost

    Vardr["🛡️ Várðr<br/>Monitoring"] -.-> |"Metrics"| K3s["Kubernetes (OrbStack)"]
    LogShipper["📡 Log Shipper<br/>(macOS Native)"] --> |"Bulk API"| Tyr["⚖️ Týr<br/>(Wazuh SIEM)"]

    style Mimir fill:#1e1b4b,stroke:#818cf8,color:#c7d2fe
    style Bifrost fill:#451a03,stroke:#f59e0b,color:#fef3c7
    style Heimdall fill:#052e16,stroke:#4ade80,color:#bbf7d0
    style Fenrir fill:#1c1917,stroke:#a8a29e,color:#e7e5e4
    style Ratatoskr fill:#422006,stroke:#fb923c,color:#fed7aa
    style Eir fill:#4a1942,stroke:#e879f9,color:#fae8ff
    style EirGW fill:#4a1942,stroke:#e879f9,color:#fae8ff
    style Yggdrasil fill:#14532d,stroke:#86efac,color:#bbf7d0
    style Vardr fill:#172554,stroke:#3b82f6,color:#bfdbfe
    style Huginn fill:#020617,stroke:#94a3b8,color:#e2e8f0
    style Tyr fill:#450a0a,stroke:#f87171,color:#fecaca
    style LogShipper fill:#450a0a,stroke:#f87171,color:#fecaca
    style Skuggi fill:#1e1b4b,stroke:#a78bfa,color:#ddd6fe
```

---

## 📦 Components

| Component | Description | Tech Stack | Tests | Status | Access |
|:--|:--|:--|:--|:--|:--|
| 🧠 **[Mimir](https://github.com/MegaWiz-Dev-Team/Mimir)** | RAG Pipeline, Agent Builder, Dashboard | Rust (Axum), Next.js 14, MariaDB, Qdrant | 255+ | ✅ Sprint 38 | 🌐 Public |
| 🛡️ **[Heimdall](https://github.com/MegaWiz-Dev-Team/Heimdall)** | LLM Gateway — multi-backend proxy | Rust (Axum) + MLX + fastembed | Benchmarked | ✅ Sprint 38 | 🌐 Public |
| ⚡ **[Bifrost](https://github.com/MegaWiz-Dev-Team/Bifrost)** | Multi-Agent Orchestrator — ReAct, MCP, Skills, Memory | **Rust (Axum + rig.rs)** | 146 | ✅ Sprint 35 | 🌐 Public |
| 🐺 **[Fenrir](https://github.com/MegaWiz-Dev-Team/Fenrir)** | Computer-Use Agent — Browser Automation + FHIR + Docker Sandbox | Rust + Python sidecar | 47 | ✅ Sprint 1.5 | 🌐 Public |
| 🏥 **[Eir](https://github.com/MegaWiz-Dev-Team/Eir)** | Rust API Gateway + OpenEMR, Chat UI, MCP Server | Rust (Axum) + PHP | 47 | ✅ Sprint 3 | 🌐 Public |
| 🌳 **Yggdrasil** | Auth Service — Zitadel OIDC + JWT + FastAPI Auth | Zitadel (Go) + Python | 31 | ✅ Sprint 2 | 🔒 Private |
| 🛡️ **[Várðr](https://github.com/MegaWiz-Dev-Team/Vardr)** | Monitoring Dashboard — health, logs, native macOS Log Shipper | Rust (Axum) + Python | 5 | ✅ Sprint 38 | 🌐 Public |
| ⚖️ **Týr** | Enterprise SIEM & XDR — Wazuh log parsing, threat hunting | Wazuh + OpenSearch | — | ✅ Sprint 38 | 🔒 Private |
| 🐉 **Fáfnir** | K3s HashiCorp Vault Secrets Manager | Vault / HCL | — | ✅ Sprint 38 | 🔒 Private |
| 🐦‍⬛ **Huginn** | Security Scanner + AI Pentest Agent + Performance Test | Rust (Axum) | 51 | ✅ Active | 🔒 Private |
| 🐦 **Muninn** | Issue Watcher + LLM Auto-Fixer | Rust (Axum) | 60 | ✅ Active | 🔒 Private |
| 🐿️ **[Ratatoskr](https://github.com/MegaWiz-Dev-Team/Ratatoskr)** | Shared Browser Service — headless Chromium REST API | Rust (Axum) | — | ✅ Sprint 1 | 🌐 Public |
| 📨 **[Hermóðr](https://github.com/MegaWiz-Dev-Team/Hermodr)** | Universal MCP Sidecar — JSON-RPC bridge for legacy REST | Rust | — | ✅ v0.1.0 | 🌐 Public |
| ⚖️ **[Forseti](https://github.com/MegaWiz-Dev-Team/Forseti)** | LLM-Powered E2E Testing Service — multi-project, auto-report | Python | 147 | ✅ Sprint 6 | 🌐 Public |
| 🔨 **[Mjölnir](https://github.com/MegaWiz-Dev-Team/Mjolnir)** | HTTP Load Testing Service — MCP-compatible, Forseti linked | Rust (Axum) | — | ✅ Active | 🌐 Public |
| 🩻 **Syn** | Document OCR & PII redaction — handwriting, layout, DICOM | Rust + Python (MLX VLM) | — | ✅ Active | 🔒 Private |
| 🏰 **Asgard** *(this repo)* | K3s Deployment (OrbStack), docs, strategy, 🔱 Odin (Supervisor) | — | — | ✅ Active | 🌐 Public |

> 🔒 **Private** components are commercial / security-sensitive (cyber-security suite, auth, secrets, OCR with PHI) and are not browsable publicly. 🌐 **Public** components are open-core under AGPL-3.0. See [`DATA_LICENSE.md`](https://github.com/MegaWiz-Dev-Team/Mimir/blob/main/DATA_LICENSE.md) in Mimir for medical-terminology data licensing (SNOMED CT / ICD-10-TM / TMT / LOINC / DrugBank — code references only, never redistributed release data).

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

## 🔑 Authentication

Auth is **dual-mode**, so the open-core services run **without** the (private)
Yggdrasil auth service. Each service inspects the bearer token: a JWT (starts
with `ey`) is validated via JWKS; anything else is treated as a static API key.

**1. Static API key — default, no identity provider needed**

Leave `YGGDRASIL_ISSUER` / `JWT_AUDIENCE` unset and configure a static key.
Services log `JWT disabled … static API_KEYS only` and run as-is — ideal for
self-hosted, single-user, and dev setups.

```bash
# no issuer/audience set → static-key mode
export API_KEYS="my-secret-key"
curl -H "Authorization: Bearer my-secret-key" http://localhost:8080/...
```

**2. Bring your own OIDC provider — multi-user / SSO**

Point the services at *any* OIDC issuer (Keycloak, Auth0, your own Zitadel —
not just Yggdrasil). They fetch the issuer's JWKS and validate RS256 JWTs.

```bash
export YGGDRASIL_ISSUER="https://id.example.com"   # any OIDC issuer URL
export JWT_AUDIENCE="heimdall"                       # per-service audience
```

The only contract is a RS256 JWT carrying the expected claims (e.g.
`urn:zitadel:iam:org:id` → `tenant_id`).

> 🔒 Yggdrasil is private and provides only the **turnkey multi-tenant SSO
> provisioning** (a commercial convenience on top of [Zitadel](https://github.com/zitadel/zitadel), Apache-2.0).
> It is **not** required to run or self-host the open-core platform.

---

## 🗺️ Roadmap

> **[Full Roadmap with Gantt Chart →](docs/strategy/roadmap.md)**

### Phase 1: Foundation ✅
- [x] Heimdall — LLM Gateway (Sprint 38, Native ONNX + MLX Backend stabilized)
- [x] Mimir — RAG Pipeline + Agent Builder + Dashboard (Sprint 38, Agentic RAG Telemetry)
- [x] Bifrost — Agent Runtime (Sprint 4, ReAct + MCP + PSO, 99 tests)
- [x] Eir — Rust API Gateway + OpenEMR (Sprint 3, 47 tests)
- [x] Fenrir — Computer-Use Agent scaffold + OpenEMR Messaging (Sprint 1.5, 47 tests)
- [x] Yggdrasil — Auth Service (Sprint 2, Zitadel + JWT + FastAPI Auth, 31 tests)
- [x] Várðr — Monitoring Dashboard (v0.4.0, K3s integration + Native macOS Agent)
- [x] Týr — Security Information & Event Management (Wazuh SIEM, ISO 27001 Log Archiving, macOS Log Shipper)
- [x] Unified K3s Cluster Deployment — OrbStack integration for 15+ microservices
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
- [x] Developer Preview — core repos public on GitHub under AGPL-3.0 (open-core; security/auth/OCR repos remain private)

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
| **Laminar** → `heimdall-trace` | (Heimdall submodule) | LLM tracing / observability | Community ‡ |
| **Skuggi** | "Shadow" (Old Norse) | PII/DLP guardrail — in-process middleware | Community † |
| **Bifrost** | Rainbow bridge | Agent Runtime | Community |
| **Fenrir** | The great wolf | Computer use | Community |
| **Eir** | Goddess of healing | Clinic management (Gateway + OpenEMR) | Community |
| **Yggdrasil** | The world tree | Auth service | 🔒 Private |
| **Várðr** | The guardian | Monitoring dashboard | Community |
| **Týr** | God of justice & war | Enterprise SIEM & XDR (Wazuh) | 🔒 Odin's Ravens |
| **Huginn** | Odin's raven (Thought) | Security Scanner + AI Pentest Agent | 🔒 Odin's Ravens |
| **Muninn** | Odin's raven (Memory) | Issue Watcher + Auto-Fixer (LLM) | 🔒 Odin's Ravens |
| **Syn** | Goddess of watchfulness | Document OCR & PII redaction | 🔒 Private |
| **Ratatoskr** | The squirrel on Yggdrasil | Shared Browser Service | Community |
| **Hermóðr** | Messenger of the gods | Universal MCP Sidecar | Community |
| **Forseti** | God of justice & reconciliation | LLM-Powered E2E Testing Service | Community |
| **Mjölnir** | Thor's hammer | HTTP Load Testing Service | Community |
| **Sága** | Seeress & chronicler | Speech-to-Text (STT) | Community ‡ |
| **Bragi** | God of poetry & eloquence | Text-to-Speech (TTS) | Community ‡ |
| **Odin** | The All-Father | Platform Supervisor | Community |

> 🔒 = private repository (commercial / security-sensitive). **Odin's Ravens** = the cyber-security suite (Huginn · Muninn · Týr).
>
> † **Skuggi** is not a standalone repo — it is in-process Rust middleware. The text-tier engine (Tier 1 regex + audit, ADR-007) ships **public** inside Heimdall (`gateway/src/skuggi.rs`) and Mimir's benchmarks; product-specific applications are private (Underwriter/Iris patient-name masking, Týr archive redaction). The image-tier model that gates cloud OCR is a runtime model, not committed code.
>
> ‡ **Planned** — not yet built; no repository exists yet. Intended to be open-core (public) when created. Laminar is being absorbed as the `heimdall-trace` submodule rather than a new top-level service.
>
> **Iris** (Greek: messenger goddess) is the **Underwriter product's** multi-agent orchestrator and lives in the private `asgard-underwriter` repo — a commercial product component, not part of the open-core platform, hence not listed above.

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
  <a href="https://github.com/MegaWiz-Dev-Team/Eir">Eir</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Vardr">Várðr</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Ratatoskr">Ratatoskr</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Hermodr">Hermóðr</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Forseti">Forseti</a> ·
  <a href="https://github.com/MegaWiz-Dev-Team/Mjolnir">Mjölnir</a>
</p>
