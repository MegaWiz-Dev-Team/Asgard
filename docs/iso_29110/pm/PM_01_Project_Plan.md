# PM-01: Project Plan (แผนโครงการ)
**Project Name:** Asgard AI Platform (Umbrella)
**Document Version:** 3.0
**Date:** 2026-03-16 (updated — TOR Gap Analysis + 3 New Services)
**Standard:** ISO/IEC 29110 — PM Process

---

## 1. Project Scope & Objectives (ขอบเขตและวัตถุประสงค์)

### เป้าหมาย
พัฒนาแพลตฟอร์ม AI แบบ Self-Hosted ครบวงจร ภายใต้ชื่อ **Asgard** ประกอบด้วย **13 components** ที่ทำงานร่วมกันผ่าน Docker Compose เพื่อให้องค์กรสามารถรัน AI stack ทั้งหมดบน hardware ของตัวเอง

> **TOR Gap Closure**: Platform ถูกขยายเพื่อรองรับ TOR AI Agent OPS (ประกันภัย — Dhipaya Life) ผ่าน gap analysis จาก 46% → 85%+ coverage — ดู [Sprint Plan](../strategy/asgard_sprint_plan_gap_to_action.md)

### Component Status (as of 2026-03-16)
| Component | Repository | Description | Version | Tests | Status |
|:--|:--|:--|:--|:--|:--|
| 🛡️ Heimdall | MegaWiz-Dev-Team/Heimdall | LLM Gateway — multi-backend proxy (Ollama/MLX/Gemini/OpenAI) | v0.4.0 | Benchmarked | ✅ Production |
| 🧠 Mimir | MegaWiz-Dev-Team/Mimir | RAG Pipeline + Agent Builder + Dashboard (Rust + Next.js) | Sprint 29 | 255+ tests | ✅ Active Development |
| ⚡ Bifrost | MegaWiz-Dev-Team/Bifrost | Agent Runtime — ReAct + MCP + Multi-Agent + PSO (Python) | Sprint 7 | 133 tests | ✅ MVP Complete |
| 🐺 Fenrir | MegaWiz-Dev-Team/Fenrir | Computer-Use Agent — Browser Use + FHIR R4 + OpenEMR Messaging | v0.3.0 | 63 tests | ✅ Sprint 3 Complete |
| 🌳 Yggdrasil | MegaWiz-Dev-Team/Yggdrasil | Auth Service — Zitadel OIDC + JWT + FastAPI Auth | v0.5.0 | 45 tests | ✅ Sprint 5 Complete |
| 🏥 Eir | MegaWiz-Dev-Team/Eir | Rust API Gateway (Axum) + OpenEMR (FHIR R4) | v0.4.0 | 57 tests | ✅ Sprint 4 Complete |
| 🛡️ Várðr | MegaWiz-Dev-Team/Vardr | Monitoring Dashboard — service health, logs, metrics (Rust) | v0.1.0 | 5 tests | ✅ Sprint 1 Complete |
| 🐦‍⬛ **Huginn** | MegaWiz-Dev-Team/Huginn | Security Scanner — Multi-Agent Pentest + DAST/SAST + LLM Security (Rust) | v0.1.0 | 36 tests | 🚧 Sprint 2 Complete |
| 🐦 **Muninn** | MegaWiz-Dev-Team/Muninn | Auto-Fixer — Issue Watcher + Multi-Agent Fix Pipeline (Rust) | v0.1.0 | 37 tests | 🚧 Sprint 2 Complete |
| 👁️ **Syn** | MegaWiz-Dev-Team/Syn | Document Vision & Identity — OCR + eKYC (Python) | — | — | 🆕 Planned (Apr 2026) |
| 🗣️ **Sága** | MegaWiz-Dev-Team/Saga | Speech & Voice — STT (Whisper) + Streaming (Python) | — | — | 🆕 Planned (May 2026) |
| 📨 **Hermóðr** | MegaWiz-Dev-Team/Hermodr | Notification Gateway — SMS + Push + Webhook | — | — | 🆕 Planned (May 2026) |
| 🏰 Asgard | MegaWiz-Dev-Team/Asgard | Umbrella — docs, Docker Compose, strategy | — | — | 📄 Active |

### Test Summary
| Component | Tests | Framework | Coverage |
|:--|:--|:--|:--|
| Mimir | 255+ | Rust (#[cfg(test)]) + Vitest | Core + API + Frontend |
| Bifrost | 133 | pytest + pytest-asyncio | ReAct + MCP + A2A + PSO + Sync |
| Eir Gateway | 57 | Rust (#[cfg(test)]) | All modules + Chat + A2A |
| Fenrir | 63 | pytest + pytest-asyncio | MCP + FHIR + Browser + Router + Messaging |
| Yggdrasil | 45 | pytest + pytest-asyncio | JWT + Client + Models + FastAPI Auth + Roles |
| Várðr | 5 | Rust (#[cfg(test)]) | Docker CLI parsers |
| Huginn | 36 | Rust (#[cfg(test)]) | Scanner + Parser + DB + Health |
| Muninn | 37 | Rust (#[cfg(test)]) | Watcher + Fixer + LLM + DB + Health |
| Syn | — | pytest | Planned (Apr 2026) |
| Sága | — | pytest | Planned (May 2026) |
| Hermóðr | — | pytest | Planned (May 2026) |
| **Total** | **610+** | | |

### Deliverables
- Unified `docker-compose.yml` ที่ start ทุก service ด้วยคำสั่งเดียว
- Documentation site ที่ asgardai.dev
- Community Edition (AGPL-3.0) + Enterprise Edition (Commercial License)

---

## 2. Project Organization & Resources (โครงสร้างทีมและทรัพยากร)

| Role | Person/Team | Responsibility |
|:--|:--|:--|
| **Founder / CTO** | Paripol (MegaWiz) | Architecture, Rust backend, AI strategy |
| **Project Manager** | Paripol | Sprint planning, ISO docs, stakeholder communication |
| **Developer** | AI-assisted (Antigravity) | Code implementation, testing, documentation |
| **Contact** | paripol@megawiz.co | Primary contact |

---

## 3. Project Schedule & Milestones (ตารางเวลาและจุดส่งมอบ)

### Mimir (🧠 Knowledge Platform)
| Sprint | Deliverable | Test Count | Status |
|:--|:--|:--|:--|
| Sprint 1-7 | Foundation: IAM, Vector, QC, Ingress, Eval, UX | — | ✅ Done |
| Sprint 8 | Unified Data Ingress & File Upload | — | ✅ Done |
| Sprint 9 | Real Pipeline & Navigation | — | ✅ Done |
| Sprint 10 | Embedding & Vector Store | — | ✅ Done |
| Sprint 11a/b | Knowledge Graph + GraphRAG | — | ✅ Done |
| Sprint 12 | Multi-Agent & Coverage Intelligence | — | ✅ Done |
| Sprint 13 | AI Agent Studio | — | ✅ Done |
| Sprint 14a/b | Production Core + Deploy & Docs | — | ✅ Done |
| Sprint 15 | Bug Fixes & Hardening | — | ✅ Done |
| Sprint 16 | Dataset Studio + Training Integration | — | ✅ Done |
| Sprint 17 | Knowledge Graph Implementation (31 tests) | 31 | ✅ Done |
| Sprint 18 | Coverage Analytics Dashboard (14 tests) | 14 | ✅ Done |
| Sprint 19 | Agent Templates & Security | — | ✅ Done |
| Sprint 20 | Custom Roles ACL | — | ✅ Done |
| Sprint 21 | QA Status & Auto-Refresh | — | ✅ Done |
| Sprint 22 | Antigravity Skills & E2E Analysis | — | ✅ Done |
| Sprint 23 | Code Quality & Refactoring (69 tests) | 69 | ✅ Done |
| Sprint 24 | Graph API Hotfix & KG Import (11 tests) | 11 | ✅ Done |
| Sprint 25 | Vector & Chat Fixes | — | ✅ Done |
| Sprint 26 | Multi-Provider Extraction & Prompt Mgmt | — | ✅ Done |
| Sprint 27 | Evaluation Expansion | — | ✅ Done |
| Sprint 28 | Auto-Pipeline & E2E Scorecard | — | ✅ Done (2026-03-11) |

### Heimdall (🛡️ LLM Gateway)
| Version | Deliverable | Status |
|:--|:--|:--|
| v0.1.0 | Foundation: FastAPI, Ollama proxy | ✅ Done |
| v0.2.0 | Multi-provider (Gemini, OpenAI) | ✅ Done |
| v0.3.0 | MLX native provider, model catalog | ✅ Done |
| v0.4.0 | API docs (Scalar), MedGemma benchmark | ✅ Production |
| Benchmark | Qwen3.5-9B vs 27B on Apple Silicon | ✅ Done (2026-03-08) |

### Bifrost (⚡ Agent Runtime)
| Sprint | Deliverable | Tests | Status |
|:--|:--|:--|:--|
| Sprint 1 | Foundation: Config, DB, Heimdall client, ReAct, Tools, Session | 27 | ✅ Done |
| Sprint 2 | MCP client (stdio+SSE), Mimir RAG tools, Webhook tools | 52 | ✅ Done |
| Sprint 3 | Agent Router, Delegate tool, Execution tracing, A2A protocol | 77 | ✅ Done |
| Sprint 4 | Plan-and-Execute, Self-Reflection, PSO Auto-Generate | 99 | ✅ Done (2026-03-11) |
| Sprint 5 | MCP Integration: Eir MCP client, Fenrir MCP client, Eir Chat proxy | — | 📋 Planned |

### Eir (🏥 API Gateway)
| Sprint | Deliverable | Tests | Status |
|:--|:--|:--|:--|
| Sprint 1 | Axum server, reverse proxy, auth, audit, health | 10 | ✅ Done |
| Sprint 2 | FHIR R4 proxy, moka cache, governor rate limit, OpenAPI | 22 | ✅ Done |
| Sprint 3 | Bifrost Agent Tools, Mimir Knowledge Sync, A2A Protocol | 47 | ✅ Done (2026-03-12) |
| Sprint 4 | MCP Server (FHIR tools), Embedded Chat UI + Widget | — | 📋 Planned |

### Fenrir (🐺 Computer-Use Agent)
| Sprint | Deliverable | Tests | Status |
|:--|:--|:--|:--|
| Sprint 1 | MCP Server, FHIR Client, Browser Use Agent, Task Router | 35 | ✅ Done (2026-03-12) |
| Sprint 1.5 | OpenEMR Messaging Integration (Poller + Bifrost relay) | 47 | ✅ Done (2026-03-14) |
| Sprint 2 | Docker Build + Compose Integration | 47 | ✅ Done (2026-03-14) |

### Yggdrasil (🌳 Auth Service)
| Sprint | Deliverable | Tests | Status |
|:--|:--|:--|:--|
| Sprint 1 | Zitadel Docker + Auth SDK (JWT + Client + Models) | 19 | ✅ Done (2026-03-12) |
| Sprint 2 | FastAPI `require_auth`, roles/scopes, dev bypass | 31 | ✅ Done (2026-03-14) |

### Huginn (🐦‍⬛ Security Scanner)
| Sprint | Deliverable | Tests | Status |
|:--|:--|:--|:--|
| Sprint 1 | Scaffold, health, scan API, nmap parser | 18 | ✅ Done (2026-03-15) |
| Sprint 2 | DAST+SAST (ZAP, Semgrep, Trivy) integration | 36 | ✅ Done (2026-03-15) |
| Sprint 3 | AI Pentest Agent (ReAct, LLM, chatbot) | — | 📋 Planned |
| Sprint 4 | Multi-Agent Swarm (5 agents) | — | 📋 Planned |
| Sprint 5 | Purple Team + Cross-Service Graph | — | 📋 Planned |
| Sprint 6 | LLM Security + Compliance Reports | — | 📋 Planned |

### Muninn (🐦 Auto-Fixer)
| Sprint | Deliverable | Tests | Status |
|:--|:--|:--|:--|
| Sprint 1 | Scaffold, GitHub poller, label filter, health | 19 | ✅ Done (2026-03-15) |
| Sprint 2 | AI Analyzer + Auto-Fix + PR creator + LLM client | 37 | ✅ Done (2026-03-15) |
| Sprint 3 | Multi-Agent Fix Pipeline (4 agents) | — | 📋 Planned |
| Sprint 4 | Continuous Learning + Trend Analysis | — | 📋 Planned |

---

- **Sprint 31: Mimir Hybrid Search & MCP Server Foundation** [Planned]
  - True Vector Integration, Parallel Tree Search, Neo4j Graph, Ensemble Retrieval, and Rust MCP Server.
- **Sprint 32: Asgard/Bifrost MCP Adapter & Dynamic Tenants** [Planned]
  - Auto-discover tools from MCP servers, Dynamic Context Isolation (X-Tenant-ID), Agent-to-Agent via JSON-RPC.
- **Sprint 33: Ecosystem Gateway Sidecars** [Planned]
  - Yggdrasil & Eir Universal Go Sidecars to expose auth and medical tools to Asgard.
- **Sprint 34: Platform Automation (Testing, Browsing & Security)** [Planned]
  - Deploy MCP across Fenrir, Forseti, Ratatoskr, Huginn, Muninn, and Heimdall.

## 4. Phase Planning

### Phase 1: Foundation (Q1-Q2 2026) — CURRENT
| Milestone | Target | Status |
|:--|:--|:--|
| Mimir Sprint 28 (Auto-Pipeline, E2E Scorecard) | 2026-03-11 | ✅ Done |
| Heimdall Production (v0.4.0) | 2026-03-04 | ✅ Done |
| Heimdall Benchmark (Qwen3.5 on Apple Silicon) | 2026-03-08 | ✅ Done |
| Asgard docs & strategy | 2026-03-07 | ✅ Done |
| Fenrir tech decision (Browser Use) + Eir codename | 2026-03-09 | ✅ Done |
| Yggdrasil tech decision (Zitadel) | 2026-03-07 | ✅ Done |
| Bifrost Sprint 4 (MVP — ReAct + MCP + PSO, 99 tests) | 2026-03-11 | ✅ Done |
| Eir Gateway Sprint 3 (Asgard Integration, 47 tests) | 2026-03-12 | ✅ Done |
| Fenrir Sprint 1 (MCP + FHIR + Browser, 35 tests) | 2026-03-12 | ✅ Done |
| Yggdrasil Sprint 1 (Zitadel + Auth SDK, 19 tests) | 2026-03-12 | ✅ Done |
| Unified Docker Compose (10/10 services) | 2026-03-13 | ✅ Done |
| Várðr Monitoring Dashboard (Sprint 1, 5 tests) | 2026-03-13 | ✅ Done |
| Fenrir Sprint 1.5 (OpenEMR Messaging) | 2026-03-14 | ✅ Done |
| Docker Compose Build Verification (6/6 passed) | 2026-03-14 | ✅ Done |
| Eir Chat Widget (mint green floating chat) | 2026-03-14 | ✅ Done |
| Yggdrasil Sprint 2 (FastAPI require_auth, 31 tests) | 2026-03-14 | ✅ Done |
| Eir Sprint 4 (MCP Server + Chat UI) | 2026-03-15 | 📋 Planned |
| Bifrost Sprint 5 (MCP: Eir + Fenrir clients) | 2026-03-16 | 📋 Planned |
| **Huginn Sprint 1 (Foundation)** | 2026-03-17 | 📋 **Planned** |
| **Muninn Sprint 1 (Foundation)** | 2026-03-24 | 📋 **Planned** |

### Phase 2a: TOR Gap Closure — Shield Wall (Apr 2026)
> Ref: [Comprehensive Sprint Plan](../strategy/asgard_sprint_plan_gap_to_action.md)

| Milestone | Target | Status |
|:--|:--|:--|
| **Bifrost S8** — AI Guardrails + PII + Kill Switch + Handover | 2026-04 W1-2 | 📋 Planned |
| **Package Extract** — line-connector, email-service, tts-service from MegaCare | 2026-04 W1-2 | 📋 Planned |
| **Syn S1** — Thai ID Card OCR foundation (PaddleOCR) | 2026-04 W3-4 | 📋 Planned |
| **Huginn S1-S2** — Foundation + DAST/SAST | 2026-04 | ✅ Done (2026-03-15) |
| 🆕 **Visual BMI PoC** — Gemini 2.5 Flash + Digital Scale eval | 2026-04 W1 | 📋 Planned |

### Phase 2b: TOR Gap Closure — Valhalla Rising (May-Jun 2026)
| Milestone | Target | Status |
|:--|:--|:--|
| **Bifrost S9** — Approval workflow + Rule engine + Scoring | 2026-05 W1-2 | 📋 Planned |
| **Syn S2** — Medical OCR + eKYC + Document classifier | 2026-05 W1-2 | 📋 Planned |
| **Sága S1** — Whisper Thai STT + FastAPI + WebSocket | 2026-05 W3-4 | 📋 Planned |
| **Hermóðr S1** — SMS + Push + Webhook + Retry queue | 2026-05 W3-4 | 📋 Planned |
| **Mimir S30** — PageIndex integration (tree indexing Step 0) | 2026-05~06 | 📋 Planned |
| **Package Extract 2** — nlq-engine, adk-base from MegaCare | 2026-06 | 📋 Planned |
| **Huginn S3-S4** — AI Pentest + Multi-Agent | 2026-05~06 | 📋 Planned |
| **Muninn S1-S2** — Foundation + AI Auto-Fix | 2026-05~06 | ✅ Done (2026-03-15) |
| 🆕 **Visual BMI Pilot** — STOP-BANG integration + Gemma 3 eval | 2026-06 | 📋 Planned |

### Phase 3: Integration — Ragnarök Prep (Jul-Aug 2026)
| Milestone | Target | Status |
|:--|:--|:--|
| **Sága S2** — Real-time streaming STT + Speaker diarization | 2026-07 | 📋 Planned |
| **Mimir S31-S32** — XLSX/table extraction + PDF/Excel reports | 2026-07~08 | 📋 Planned |
| **Bifrost S10** — A2A Client + Multi-skill routing | 2026-08 | 📋 Planned |
| Visual Workflow Builder | 2026-07 | 📋 Planned |
| Documentation Site (asgardai.dev) | 2026-08 | 📋 Planned |
| **Huginn S5** — Purple Team | 2026-07 | 📋 Planned |
| **Muninn S3** — Multi-Agent Fix Pipeline | 2026-07 | 📋 Planned |

### Phase 4: Community Launch — Götterdämmerung (Sep-Oct 2026)
| Milestone | Target | Status |
|:--|:--|:--|
| E2E Integration (LINE→Bifrost→Eir→Mimir→Response) | 2026-09 | 📋 Planned |
| Insurance connectors (eBao, Salesforce stubs) | 2026-09 | 📋 Planned |
| v1.0 Community Edition | 2026-10 | 📋 Planned |
| TOR Demo readiness (85%+ coverage) | 2026-10 | 📋 Planned |
| **Huginn S6** — LLM Security + Compliance | 2026-09 | 📋 Planned |
| **Muninn S4** — Continuous Learning | 2026-09 | 📋 Planned |

### Phase 5: Enterprise (2027)
| Milestone | Target | Status |
|:--|:--|:--|
| Enterprise Pilot | 2027-Q1 | 📋 Planned |
| Enterprise GA | 2027-Q3 | 📋 Planned |
| $100K ARR | 2027-Q4 | 📋 Planned |

---

## 5. Risk Management (การจัดการความเสี่ยง)

| Risk | Impact | Mitigation |
|:--|:--|:--|
| **Solo founder bottleneck** | High | Hire first engineer at $100K ARR; use AI-assisted development |
| **Docker Compose complexity** | Medium | Start minimal (3 services); add incrementally |
| **Competitor catches up (Dify, Flowise)** | High | Move fast; MLX native is hard to replicate |
| **Cross-component integration failures** | High | E2E test suite; health checks in Docker Compose |
| **Hardware supply chain (DGX Spark, Mac)** | Medium | Maintain multiple suppliers; pre-order strategy |
| **AGPL compliance enforcement** | Low | License key system; feature flags |
| **Enterprise sales cycle too long** | Medium | Design partner program (free 6 months) |
| **Huginn scan impacts production** | High | Kill switch, blast radius limit, RoE, dry-run mode |
| **Muninn auto-fix introduces bugs** | High | Draft PR only, multi-agent review, human approval |
| **WhiteRabbitNeo offensive model abuse** | High | RBAC gating, RoE enforcement, audit log |
| **PaddleOCR Thai accuracy (Syn)** | Medium | Test early with real Thai ID cards; iApp API fallback |
| **Whisper Thai STT accuracy (Sága)** | Medium | Benchmark vs Google STT; hybrid approach |
| **PageIndex Thai ToC detection** | Low | Test with Thai PDFs; adjust LLM prompts |
| **eBao API access (Insurance domain)** | High | Need partner coordination with Dhipaya Life early |
| **Team capacity — 12 products** | High | Prioritize P0 items only in Phase 2a; defer P2 |
| **AGPL contamination (Eir/OpenEMR)** | Medium | Keep Eir isolated; no code merge into proprietary modules |
| 🆕 **Visual BMI cross-population accuracy** | Medium | Gemini PoC first (1-2 days); Digital Scale fine-tune with Thai dataset; use as flag only |
| 🆕 **Visual BMI PDPA (biometric data)** | High | PoC: anonymized on Cloud; Production: Gemma 3 on-prem; delete images after scoring |

---

*บันทึกโดย: AI Assistant (ตามมาตรฐาน ISO/IEC 29110 หมวด PM-01)*
*Last updated: 2026-03-16 by Antigravity — Visual BMI PoC + STOP-BANG, Huginn S1-S2 + Muninn S1-S2 done (73 tests)*
