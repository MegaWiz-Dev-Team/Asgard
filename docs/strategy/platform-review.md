# 🏰 Asgard Platform Review — SME Self-Hosted + Open Source Strategy

> **Context**: Architecture review of Asgard for SME on-premise self-hosted deployment.
> Planned as **Community Edition (OSS)** + **Enterprise Edition (Commercial)** in the future.

---

## 1. 💪 Current Platform Strengths

### Strong Architecture
- **Modular Microservices** — Separate components (Heimdall, Mimir, Bifrost, Fenrir) allow selective deployment
- **OpenAI-Compatible API** — SMEs already using OpenAI can migrate by simply changing the endpoint
- **Multi-Backend Strategy** — MLX, llama.cpp, Ollama, vLLM cover all use cases
- **Rust + Python hybrid** — Performance-critical parts (Gateway, RAG) use Rust; AI-ecosystem parts (Agent) use Python

### Mimir Is Production-Ready (23 Sprints Done)

| Feature | Status | Details |
|:--|:--|:--|
| **Multi-Tenant IAM** | ✅ Done | JWT auth, Argon2id password, role-based access |
| **Admin Dashboard** | ✅ Done | Tenant switcher, user management, settings |
| **Unified Data Ingress** | ✅ Done | File upload (PDF/CSV/XLSX/HTML), web scraper, MCP connector |
| **Quality Control** | ✅ Done | LLM data clustering, conflict resolution Kanban |
| **Agent Evaluations** | ✅ Done | LLM-as-a-judge, heatmap scoring, human override |
| **Pipeline Traceability** | ✅ Done | Source → Vector → Answer end-to-end tracking |
| **NPC Playground** | ✅ Done | Tier 1 (simple chat) & Tier 2 (RAG) with streaming |
| **Real-time Monitoring** | ✅ Done | WebSocket/SSE streaming logs |
| **Docker Compose** | ✅ Done | MariaDB + Qdrant + rAthena |

**Mimir Tech Stack:**

| Layer | Technology |
|:--|:--|
| Backend | Rust (Axum + [Rig.rs](https://rig.rs)) |
| Frontend | Next.js 14 + TailwindCSS + shadcn/ui |
| Database | MariaDB (relational) |
| Vector DB | Qdrant (semantic search) |
| Graph DB | Neo4j Community (Sprint 11) |
| Graph Viz | Sigma.js + graphology (WebGL) |
| LLM Providers | Ollama (local), Google Gemini, Qwen API |
| Embedding | nomic-embed-text, text-embedding-004, bge-m3 |
| Infrastructure | Docker Compose |

### Ideal for SME On-Prem
- **Zero Cloud Dependency** — Data never leaves the company → data sovereignty
- **Single Machine Deployment** — Runs on a single Mac Mini M4 Pro
- **Low Operational Cost** — No API call charges, no large DevOps team needed

---

## 2. ⚠️ Gap Analysis — What's Missing for SME + Commercial

### 🔴 Critical Gaps (Required before Community release)

| Gap | Problem | Solution |
|:--|:--|:--|
| **Centralized Auth** | Each component uses separate auth | ✅ Decided: Zitadel (Yggdrasil) |
| **All-in-One Docker Compose** | Stacks for Heimdall/Bifrost still separate | Create unified `docker-compose.yml` |
| **Backup/Restore** | No automated backup system | Add backup CLI + cron |
| **Bifrost not ready** | Agent Runtime is a core value | Prioritize MVP |
| **Setup Wizard** | Must manually configure `.env` files | Create CLI + Web wizard |

### 🟡 Important Gaps (Required before Enterprise)

| Gap | Reason |
|:--|:--|
| **Audit Log** | Enterprise requires audit trail for compliance |
| **Rate Limiting / Quota** | Prevent abuse, limit usage per user/team |
| **SSO Integration** | Enterprise uses LDAP/SAML/OIDC |
| **HA / Clustering** | Mid-to-large companies need high availability |
| **Usage Analytics Dashboard** | Billing, cost tracking, usage reporting |

---

## 3. 🗺️ Roadmap — Community → Enterprise

### Phase 1: Community Foundation (v1.0) 🎯
> Goal: **Anyone can download and run it in 15 minutes**

```
✅ Already built (from Mimir)              🆕 To be added
├── Multi-Tenant IAM (JWT+RBAC)       ├── Unified docker-compose (all components)
├── Admin Dashboard (Next.js)          ├── Shared Auth (Zitadel)
├── Docker Compose (partial)           ├── One-command install script
├── RAG Pipeline + Ingestion           ├── Backup/Restore CLI
├── Agent Eval + QC System             ├── License selection + NOTICE
└── Real-time Monitoring               └── Asgard Quick Start Guide
```

**Hardware Tiers for SMEs:**

#### 🍎 Apple Silicon Track (MLX / llama.cpp / Ollama)

| Tier | Hardware | Capacity | Approx. Price |
|:--|:--|:--|:--|
| **Starter** | Mac Mini M4 (16GB) | 1-5 users, 7B model | ~$700 |
| **Standard** | Mac Mini M4 Pro (36GB) | 10-20 users, 14B model | ~$1,700 |
| **Pro** | Mac Mini M4 Pro (64GB) | 20-50 users, 30B+ model | ~$2,300 |
| **Max** | Mac Studio M4 Ultra (192GB) | 50-200 users, 70B+ model | ~$5,100 |

#### 🟢 NVIDIA Track (vLLM + CUDA)

| Tier | Hardware | Capacity | Approx. Price |
|:--|:--|:--|:--|
| **DGX Spark** | NVIDIA DGX Spark (128GB) | 50-200 users, 70B+ model | ~$10,000 |
| **DGX Station** | NVIDIA DGX Station (A100/H100) | 200+ users, multi-model | ~$60,000+ |

### Phase 2: Community Growth (v1.x)
> Goal: **Real-world community usage + NVIDIA support**

- [ ] Bifrost MVP (Agent Runtime — ReAct loop, tool execution)
- [ ] 🟢 Heimdall: vLLM backend — CUDA support for NVIDIA DGX Spark
- [ ] 🟢 Heimdall: Intelligent Router — Auto-route by hardware (MLX vs vLLM)
- [ ] 🧠 Mimir: Visual Workflow Builder (ReactFlow) — **moved from Enterprise**
- [ ] 🧠 Mimir: A2A Server (Agent-to-Agent protocol)
- [ ] ⚡ Bifrost: A2A Client
- [ ] adk-guardrail integration (PII redaction — Healthcare)
- [ ] Agent Template Marketplace
- [ ] Plugin system for custom tools
- [ ] Documentation site
- [ ] Knowledge Graph (Neo4j — Mimir Sprint 11)
- [ ] Multi-Agent System (Mimir Sprint 12)

### Phase 3: Enterprise Edition (v2.0) 💰
> Goal: **Sell licenses to companies**

```
Enterprise-Only Features:
├── 🔐 SSO (SAML, OIDC, LDAP) via Zitadel
├── 👥 Advanced RBAC (org → team → project)
├── 📊 Usage Analytics + Cost Dashboard
├── 📋 Audit Log + Compliance Reports
├── 🔄 HA Clustering (multi-node)
├── 🆘 Priority Support + SLA
├── 🏷️ White-Label / Custom Branding
└── 🤖 Advanced Agent Features
    ├── Agent Collaboration (multi-agent)
    └── Enterprise RAG (advanced chunking, PII redaction)
```

---

## 4. 📊 Licensing Strategy

> ✅ **Decided: AGPL-3.0** — Dual License (AGPL Community + Commercial Enterprise)

| Option | License | Pros | Cons | Examples |
|:--|:--|:--|:--|:--|
| **✅ Selected** | AGPL-3.0 | Strong copyleft prevents cloud reselling | Some SMEs wary of GPL | GitLab, Mattermost |
| B | BSL 1.1 | Protects commercial use while allowing free use | Not considered "true OSS" | Sentry, CockroachDB |
| C | Apache 2.0 + CLA | Most permissive | Harder to prevent competitors | Kubernetes, TensorFlow |

---

## 5. 🎯 Competitive Positioning

| Feature | Asgard | Open WebUI | AnythingLLM | Dify |
|:--|:--|:--|:--|:--|
| LLM Gateway | ✅ Heimdall (Rust) | ❌ | ❌ | ❌ |
| RAG Pipeline | ✅ Mimir | ⚠️ Basic | ✅ | ✅ |
| Agent Runtime | ✅ Bifrost | ❌ | ⚠️ Basic | ✅ |
| Computer Use | ✅ Fenrir | ❌ | ❌ | ❌ |
| Apple Silicon | ✅ Native MLX | ❌ | ❌ | ❌ |
| NVIDIA GPU | 🟢 vLLM | ❌ | ❌ | ⚠️ Cloud |
| Self-Hosted | ✅ 100% | ✅ | ✅ | ⚠️ |
| Enterprise Ready | 🚧 | ❌ | ⚠️ | ✅ |

**USP (Unique Selling Point):**
> "A full-stack, self-hosted AI platform for both Apple Silicon and NVIDIA GPU — from LLM Gateway to Computer Use Agent. Your data never leaves your premises."

---

*📅 Last updated: March 2026*
