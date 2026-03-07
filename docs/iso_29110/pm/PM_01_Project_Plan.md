# PM-01: Project Plan (แผนโครงการ)
**Project Name:** Asgard AI Platform (Umbrella)
**Document Version:** 1.0
**Date:** 2026-03-07
**Standard:** ISO/IEC 29110 — PM Process

---

## 1. Project Scope & Objectives (ขอบเขตและวัตถุประสงค์)

### เป้าหมาย
พัฒนาแพลตฟอร์ม AI แบบ Self-Hosted ครบวงจร ภายใต้ชื่อ **Asgard** ประกอบด้วย 6 components ที่ทำงานร่วมกันผ่าน Docker Compose เพื่อให้องค์กรสามารถรัน AI stack ทั้งหมดบน hardware ของตัวเอง

### ขอบเขต
| Component | Repository | Description | Status |
|:--|:--|:--|:--|
| 🛡️ Heimdall | megacare-dev/Heimdall | LLM Gateway — multi-backend proxy | ✅ Production |
| 🧠 Mimir | megacare-dev/Mimir | RAG Pipeline + Agent Builder + Dashboard | ✅ Sprint 23 |
| ⚡ Bifrost | megacare-dev/Bifrost | Agent Runtime Engine — ReAct loop | 🚧 Scaffolding |
| 🐺 Fenrir | megacare-dev/Fenrir | Computer-Use Agent — browser/shell | 📋 Planned |
| 🌳 Yggdrasil | megacare-dev/Yggdrasil | Auth Service — Zitadel-based SSO | 📋 Planned |
| 🏰 Asgard | megacare-dev/Asgard | Umbrella — docs, Docker Compose, strategy | 📋 Active |

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

### Phase 1: Foundation (Q1-Q2 2026) — CURRENT
| Milestone | Target | Status |
|:--|:--|:--|
| Mimir Sprint 23 complete | 2026-03-06 | ✅ Done |
| Heimdall Production | 2026-03-04 | ✅ Done |
| Asgard docs & strategy | 2026-03-07 | ✅ Done |
| Unified Docker Compose | 2026-04 | 📋 Planned |
| Bifrost MVP (ReAct loop) | 2026-05 | 📋 Planned |
| Yggdrasil Setup (Zitadel) | 2026-05 | 📋 Planned |

### Phase 2: Growth (Q3 2026)
| Milestone | Target | Status |
|:--|:--|:--|
| Visual Workflow Builder | 2026-07 | 📋 Planned |
| Fenrir MVP | 2026-08 | 📋 Planned |
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

## 4. Risk Management (การจัดการความเสี่ยง)

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
