# PM-01: Project Plan (แผนโครงการ)
**Project Name:** Asgard AI Platform (Umbrella)
**Document Version:** 1.5
**Date:** 2026-03-13 (updated — Docker Compose 10/10 services verified)
**Standard:** ISO/IEC 29110 — PM Process

---

## 1. Project Scope & Objectives (ขอบเขตและวัตถุประสงค์)

### เป้าหมาย
พัฒนาแพลตฟอร์ม AI แบบ Self-Hosted ครบวงจร ภายใต้ชื่อ **Asgard** ประกอบด้วย 6 components ที่ทำงานร่วมกันผ่าน Docker Compose เพื่อให้องค์กรสามารถรัน AI stack ทั้งหมดบน hardware ของตัวเอง

### Component Status (as of 2026-03-12)
| Component | Repository | Description | Version | Tests | Status |
|:--|:--|:--|:--|:--|:--|
| 🛡️ Heimdall | megacare-dev/Heimdall | LLM Gateway — multi-backend proxy (Ollama/MLX/Gemini/OpenAI) | v0.4.0 | Benchmarked | ✅ Production |
| 🧠 Mimir | megacare-dev/Mimir | RAG Pipeline + Agent Builder + Dashboard (Rust + Next.js) | Sprint 28 | 255+ tests | ✅ Active Development |
| ⚡ Bifrost | megacare-dev/Bifrost | Agent Runtime — ReAct + MCP + Multi-Agent + PSO (Python) | Sprint 4 | 99 tests | ✅ MVP Complete |
| 🐺 Fenrir | megacare-dev/Fenrir | Computer-Use Agent — Browser Use + FHIR R4 (Python) | v0.1.0 | 35 tests | ✅ Sprint 1 Complete |
| 🌳 Yggdrasil | megacare-dev/Yggdrasil | Auth Service — Zitadel OIDC + JWT SDK (Python) | v0.1.0 | 19 tests | ✅ Sprint 1 Complete |
| 🏥 Eir | megacare-dev/openemr | Rust API Gateway (Axum) + OpenEMR (FHIR R4) | v0.3.0 | 47 tests | ✅ Sprint 3 Complete |
| 🏰 Asgard | megacare-dev/Asgard | Umbrella — docs, Docker Compose, strategy | — | — | 📄 Active |

### Test Summary
| Component | Tests | Framework | Coverage |
|:--|:--|:--|:--|
| Mimir | 255+ | Rust (#[cfg(test)]) + Vitest | Core + API + Frontend |
| Bifrost | 99 | pytest + pytest-asyncio | ReAct + MCP + A2A + PSO |
| Eir Gateway | 47 | Rust (#[cfg(test)]) | All modules |
| Fenrir | 35 | pytest + pytest-asyncio | MCP + FHIR + Browser + Router |
| Yggdrasil | 19 | pytest + pytest-asyncio | JWT + Client + Models |
| **Total** | **455+** | | |

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

### Eir (🏥 API Gateway)
| Sprint | Deliverable | Tests | Status |
|:--|:--|:--|:--|
| Sprint 1 | Axum server, reverse proxy, auth, audit, health | 10 | ✅ Done |
| Sprint 2 | FHIR R4 proxy, moka cache, governor rate limit, OpenAPI | 22 | ✅ Done |
| Sprint 3 | Bifrost Agent Tools, Mimir Knowledge Sync, A2A Protocol | 47 | ✅ Done (2026-03-12) |

### Fenrir (🐺 Computer-Use Agent)
| Sprint | Deliverable | Tests | Status |
|:--|:--|:--|:--|
| Sprint 1 | MCP Server, FHIR Client, Browser Use Agent, Task Router | 35 | ✅ Done (2026-03-12) |

### Yggdrasil (🌳 Auth Service)
| Sprint | Deliverable | Tests | Status |
|:--|:--|:--|:--|
| Tech Decision | Zitadel (self-hosted OIDC + RBAC) | — | ✅ Decided (2026-03-07) |
| Sprint 1 | Zitadel Docker + Auth SDK (JWT + Client + Models) | 19 | ✅ Done (2026-03-12) |

---

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

### Phase 2: Growth (Q3 2026)
| Milestone | Target | Status |
|:--|:--|:--|
| Visual Workflow Builder | 2026-07 | 📋 Planned |
| Fenrir MVP (OpenEMR E2E) | 2026-08 | 📋 Planned |
| Documentation Site (asgardai.dev) | 2026-08 | 📋 Planned |
| Developer Preview (GitHub public) | 2026-09 | 📋 Planned |

### Phase 3: Community Launch (Q4 2026)
| Milestone | Target | Status |
|:--|:--|:--|
| v1.0 Community Edition | 2026-10 | 📋 Planned |
| Product Hunt / HackerNews launch | 2026-10 | 📋 Planned |
| 3-5 Design Partners | 2026-12 | 📋 Planned |

### Phase 4: Enterprise (2027)
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

---

*บันทึกโดย: AI Assistant (ตามมาตรฐาน ISO/IEC 29110 หมวด PM-01)*
*Last updated: 2026-03-13 by Antigravity — Docker Compose 10/10 verified, 455+ total tests*
