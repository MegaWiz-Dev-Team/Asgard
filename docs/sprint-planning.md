# 🏰 Asgard Sprint Planning — March 2026

> Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.

---

## 📊 Current Status (as of 2026-03-15)

| Component | Version | Sprint | Tests | ISO Docs | Docker | Status |
|:--|:--|:--|:--|:--|:--|:--|
| 🛡️ Heimdall | v0.4.0 | — | Benchmarked | ✅ | ⚠️ Host only | ✅ Production |
| 🧠 Mimir | v0.29.0 | Sprint 29 | 255+ | ✅ | ✅ Infra compose | ✅ Active |
| ⚡ Bifrost | v0.7.0 | Sprint 7 | 133 | ✅ | ✅ Dockerfile | ✅ Mimir Sync |
| 🏥 Eir | v0.4.0 | Sprint 4 | 57 | ✅ | ⚠️ OpenEMR image | ✅ JWKS Auth |
| 🐺 Fenrir | v0.3.0 | Sprint 3 | 63 | ✅ | ✅ Dockerfile | ✅ JWT Auth |
| 🌳 Yggdrasil | v0.5.0 | Sprint 5 | 45 | ✅ | ✅ Compose | ✅ Yggdrasil Setup |
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
| Mimir OIDC login | 🧠🌳 | Dashboard → Yggdrasil SSO | ✅ Done |

### Week 3 (P2 — Nice to Have)
| Task | Component | Description | Status |
|:--|:--|:--|:--|
| Fenrir + Heimdall LLM | 🐺🛡️ | Browser Use + NL → actions |
| Eir FHIR extensions | 🏥 | Encounter create, Medication request |
| Cross-component JWT | All | All services validate Yggdrasil tokens | ✅ Done (Bifrost+Fenrir) |

---

### 🐦‍⬛ Huginn — Sprint 1: Foundation
- [ ] Cargo scaffold (main.rs, config.rs, health.rs, db.rs, models.rs)
- [ ] Dockerfile + Docker Compose integration
- [ ] `GET /health` endpoint (Várðr compatible)
- [ ] `POST /api/scan` + `GET /api/scans/{id}`
- [ ] SQLite schema (scans, findings, suppressions)
- [ ] Basic nmap scan via `tokio::process::Command`

### 🐦 Muninn — Sprint 1: Foundation
- [ ] Cargo scaffold (main.rs, config.rs, health.rs, db.rs)
- [ ] Dockerfile + Docker Compose integration
- [ ] `GET /health` endpoint
- [ ] GitHub issue poller (octocrab, 5 min interval)
- [ ] SQLite schema (watched_repos, analyzed_issues, fixes)
- [ ] Label filter (huginn-finding, security, auto-fix, muninn-skip)

---

## 🐦‍⬛🐦 Odin's Ravens: Enterprise Security (Q2-Q3 2026)

> **[Full Implementation Plan →](roadmap/huginn-muninn.md)** | **[BRD](business/odins-ravens-brd.md)** | **[TRD](business/odins-ravens-trd.md)**

```mermaid
gantt
    title Odin's Ravens Sprint Timeline
    dateFormat YYYY-MM-DD
    axisFormat %b %d

    section 🐦‍⬛ Huginn
    S1 Foundation           :h1, 2026-03-17, 14d
    S2 DAST+SAST            :h2, after h1, 14d
    S3 AI Pentest Agent     :h3, after h2, 14d
    S4 Multi-Agent Swarm    :h4, after h3, 14d
    S5 Purple Team          :h5, after h4, 21d
    S6 LLM Security         :h6, after h5, 14d

    section 🐦 Muninn
    S1 Foundation           :m1, 2026-03-24, 14d
    S2 AI Analyzer+Fix      :m2, after m1, 14d
    S3 Multi-Agent Pipeline :m3, after m2, 14d
    S4 Continuous Learning  :m4, after m3, 14d
```

| Service | Stack | Total Sprints | Key Innovation |
|:--|:--|:--|:--|
| 🐦‍⬛ Huginn | 🦀 Rust/Axum | 6 sprints (13 weeks) | Multi-Agent Pentest Swarm + Purple Team |
| 🐦 Muninn | 🦀 Rust/Axum | 4 sprints (8 weeks) | Multi-Agent Fix Pipeline + Continuous Learning |

---

*Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.*
