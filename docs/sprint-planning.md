# 🏰 Asgard Sprint Planning — March 2026

> Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.

---

## 📊 Current Status (as of 2026-03-13)

| Component | Version | Sprint | Tests | ISO Docs | Docker | Status |
|:--|:--|:--|:--|:--|:--|:--|
| 🛡️ Heimdall | v0.4.0 | — | Benchmarked | ✅ | ⚠️ Host only | ✅ Production |
| 🧠 Mimir | — | Sprint 28 | 255+ | ✅ | ✅ Infra compose | ✅ Active |
| ⚡ Bifrost | v0.4.0 | Sprint 4 | 99 | ✅ | ✅ Dockerfile | ✅ MVP |
| 🏥 Eir | v0.3.0 | Sprint 3 | 47 | ✅ | ⚠️ OpenEMR image | ✅ Done |
| 🐺 Fenrir | v0.1.0 | Sprint 1 | 35 | ✅ | ✅ Dockerfile | ✅ Done |
| 🌳 Yggdrasil | v0.1.0 | Sprint 1 | 19 | ✅ | ✅ Compose | ✅ Done |
| 🏰 Asgard | v1.0-α | — | — | ✅ PM | ✅ Unified | ✅ Active |

> **455+ tests** across the entire platform

---

## 🎯 Next Sprint: Integration & Hardening

### Week 1 (P0 — Must Do)
| Task | Component | Description |
|:--|:--|:--|
| Mimir Dockerfiles | 🧠 Mimir | Multi-stage builds for API (Rust) + Dashboard (Next.js) |
| Verify compose builds | 🏰 Asgard | `docker compose build` all services |

### Week 2 (P1 — Should Do)
| Task | Component | Description |
|:--|:--|:--|
| Yggdrasil FastAPI Depends | 🌳 Yggdrasil | `require_auth()` for Python services |
| Service accounts | 🌳 Yggdrasil | Machine-to-machine tokens |
| Bifrost ↔ Eir E2E | ⚡↔🏥 | ReAct agent → patient query → response |
| Mimir OIDC login | 🧠🌳 | Dashboard → Zitadel SSO |

### Week 3 (P2 — Nice to Have)
| Task | Component | Description |
|:--|:--|:--|
| Fenrir + Heimdall LLM | 🐺🛡️ | Browser Use + NL → actions |
| Eir FHIR extensions | 🏥 | Encounter create, Medication request |
| Cross-component JWT | All | All services validate Zitadel tokens |

---

## 📋 Per-Project Next Sprints

### 🧠 Mimir — Sprint 29: Docker & API Polish
- [ ] Dockerfile (API) — multi-stage Rust build
- [ ] Dockerfile (Dashboard) — Next.js production
- [ ] Agent deployment API → Bifrost
- [ ] A2A Server endpoints

### ⚡ Bifrost — Sprint 5: Integration
- [ ] Eir agent tools E2E test
- [ ] Mimir agent config sync
- [ ] Yggdrasil JWT auth middleware

### 🏥 Eir — Sprint 4: Auth & FHIR
- [ ] Yggdrasil JWT validation (replace static Bearer)
- [ ] FHIR extended resources
- [ ] Bifrost E2E counterpart

### 🐺 Fenrir — Sprint 2: LLM Integration
- [ ] Browser Use + Heimdall LLM
- [ ] OpenEMR form mapping
- [ ] Yggdrasil JWT auth

### 🌳 Yggdrasil — Sprint 2: OIDC Integration
- [ ] FastAPI `require_auth()` dependency
- [ ] Mimir OIDC login flow
- [ ] Service account tokens
- [ ] Rust JWKS crate for Eir

### 🛡️ Heimdall — Maintenance
- [ ] Optional Dockerfile (CPU-only)
- [ ] Yggdrasil JWT validation

---

*Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.*
