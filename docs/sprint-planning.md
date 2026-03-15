# 🏰 Asgard Sprint Planning — March 2026

> Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.

---

## 📊 Current Status (as of 2026-03-15)

| Component | Version | Sprint | Tests | ISO Docs | Docker | Status |
|:--|:--|:--|:--|:--|:--|:--|
| 🛡️ Heimdall | v0.4.0 | — | Benchmarked | ✅ | ⚠️ Host only | ✅ Production |
| 🧠 Mimir | — | Sprint 28 | 255+ | ✅ | ✅ Infra compose | ✅ Active |
| ⚡ Bifrost | v0.7.0 | Sprint 7 | 133 | ✅ | ✅ Dockerfile | ✅ Mimir Sync |
| 🏥 Eir | v0.3.0 | Sprint 3 | 47 | ✅ | ⚠️ OpenEMR image | ✅ Done |
| 🐺 Fenrir | v0.3.0 | Sprint 3 | 63 | ✅ | ✅ Dockerfile | ✅ JWT Auth |
| 🌳 Yggdrasil | v0.4.0 | Sprint 4 | 39 | ✅ | ✅ Compose | ✅ M2M Auth |
| 🏰 Asgard | v1.0-α | — | — | ✅ PM | ✅ Unified | ✅ Active |

> **537+ tests** across the entire platform

---

## 🎯 Next Sprint: Integration & Hardening

### Week 1 (P0 — Must Do) ✅ Completed 2026-03-14
| Task | Component | Description | Status |
|:--|:--|:--|:--|
| Mimir Dockerfiles | 🧠 Mimir | Multi-stage builds for API (Rust) + Dashboard (Next.js) | ✅ Done |
| Backup CLI | 🏰 Asgard | `scripts/backup.sh` backs up MariaDB + Qdrant | ✅ Done |

### Week 2 (P1 — Should Do)
| Task | Component | Description | Status |
|:--|:--|:--|:--|
| Yggdrasil FastAPI Depends | 🌳 Yggdrasil | `require_auth()` for Python services | ✅ Done |
| Bifrost JWT auth | ⚡ Bifrost | Yggdrasil JWT middleware | ✅ Done |
| Fenrir JWT auth | 🐺 Fenrir | Yggdrasil JWT middleware | ✅ Done |
| Bifrost ↔ Eir E2E | ⚡↔🏥 | ReAct agent → patient query → response | ✅ Done |
| Service accounts | 🌳 Yggdrasil | Machine-to-machine tokens |
| Mimir OIDC login | 🧠🌳 | Dashboard → Zitadel SSO |

### Week 3 (P2 — Nice to Have)
| Task | Component | Description | Status |
|:--|:--|:--|:--|
| Fenrir + Heimdall LLM | 🐺🛡️ | Browser Use + NL → actions |
| Eir FHIR extensions | 🏥 | Encounter create, Medication request |
| Cross-component JWT | All | All services validate Zitadel tokens | ✅ Done (Bifrost+Fenrir) |

---

## 📋 Per-Project Next Sprints

### 🧠 Mimir — Sprint 29: Docker & API Polish
- [ ] Dockerfile (API) — multi-stage Rust build
- [ ] Dockerfile (Dashboard) — Next.js production
- [ ] Agent deployment API → Bifrost
- [ ] A2A Server endpoints

### ⚡ Bifrost — Sprint 7: Mimir Sync
- [x] Eir agent tools (patient_search, fhir_query, clinical_summary)
- [x] Fenrir MCP connection (SSE transport, auto-discovery)
- [x] Yggdrasil JWT auth middleware
- [x] Mimir agent config sync

### 🏥 Eir — Sprint 4: Auth & FHIR
- [ ] Yggdrasil JWT validation (replace static Bearer)
- [ ] FHIR extended resources
- [ ] Bifrost E2E counterpart

### 🐺 Fenrir — Sprint 3: Auth + E2E
- [x] OpenEMR Message Center integration (Sprint 1.5 → 2)
- [x] Yggdrasil JWT auth
- [ ] Browser Use + Heimdall LLM
- [ ] OpenEMR form mapping
- [ ] E2E test: Message → Bifrost → AI Reply in OpenEMR

### 🌳 Yggdrasil — Sprint 4: M2M Auth
- [x] FastAPI `require_auth()` dependency
- [x] Service account tokens (client_credentials)
- [ ] Mimir OIDC login flow
- [ ] Rust JWKS crate for Eir

### 🛡️ Heimdall — Maintenance
- [ ] Optional Dockerfile (CPU-only)
- [ ] Yggdrasil JWT validation

---

## 🗄️ Database Consolidation (Phase 3 — Q4 2026)

> ลด MariaDB + PostgreSQL → **PostgreSQL ตัวเดียว** ก่อน v1.0 Release

| Step | Task | Risk |
|:--|:--|:--|
| 1 | เขียน migration script (MariaDB → Postgres) | 🟡 |
| 2 | ทดสอบบน staging (copy data + verify) | 🟡 |
| 3 | Update Mimir connection string `mysql://` → `postgresql://` | 🟢 |
| 4 | ลบ MariaDB จาก compose | 🟢 |

> `sqlx` ของ Mimir support ทั้ง MySQL และ Postgres อยู่แล้ว — code แทบไม่ต้องแก้

---

## 🐦‍⬛ Enterprise: Huginn & Muninn (Q3 2026+)

> **[Full Roadmap →](roadmap/huginn-muninn.md)**

| Service | Role | Start |
|:--|:--|:--|
| 🐦‍⬛ Huginn | Security Scanner (Semgrep + Trivy + auto GitHub Issue) | Q3 2026 |
| 🐦 Muninn | Auto-Fixer (LLM code fix + PR + auto-merge) | Q4 2026 |

---

*Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.*
