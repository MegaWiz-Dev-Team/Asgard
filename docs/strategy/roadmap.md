# 🗺️ Asgard — Development Roadmap

> Single source of truth for all milestones and timelines.
>
> Last updated: March 2026

---

## Roadmap Overview

```mermaid
gantt
    title Asgard Development Roadmap
    dateFormat  YYYY-MM
    axisFormat  %b %Y

    section 🛡️ Heimdall
    LLM Gateway v0.4.0 (S0-6)        :done,    h1, 2026-03, 2026-03
    Mimir Integration (S6)            :done,    h1b, 2026-03, 2026-03
    vLLM Backend (NVIDIA)             :active,  h2, 2026-04, 2026-06
    Intelligent Router                :         h3, 2026-06, 2026-08
    Yggdrasil JWT Validation            :         h4, 2026-05, 2026-06

    section 🧠 Mimir
    Sprint 1-23 (Core Platform)       :done,    m1, 2025-06, 2026-03
    Visual Workflow Builder            :         m2, 2026-06, 2026-09
    A2A Server                        :         m3, 2026-07, 2026-09

    section ⚡ Bifrost
    Agent Runtime MVP                 :active,  b1, 2026-04, 2026-07
    A2A Client                        :         b2, 2026-08, 2026-10
    Plugin System                     :         b3, 2026-10, 2026-12

    section 🐺 Fenrir
    Computer Use MVP                  :         f1, 2026-08, 2026-11

    section 🌳 Yggdrasil
    Yggdrasil Deployment                :         y1, 2026-05, 2026-06
    Mimir OIDC Migration              :         y2, 2026-06, 2026-07
    Enterprise Auth (SAML/LDAP)       :         y3, 2027-01, 2027-06

    section 🏰 Asgard
    Unified Docker Compose            :active,  a1, 2026-04, 2026-05
    Backup/Restore CLI                :         a2, 2026-05, 2026-06
    Documentation Site                :         a3, 2026-06, 2026-08

    section 🐦‍⬛ Huginn (Enterprise)
    S1-S2 Foundation+Scans            :         hg1, 2026-03, 2026-04
    S3-S4 AI Pentest+Multi-Agent      :         hg2, 2026-05, 2026-06
    S5-S6 Purple Team+LLM Security    :         hg3, 2026-06, 2026-07

    section 🐦 Muninn (Enterprise)
    S1-S2 Foundation+Auto-Fix         :         mn1, 2026-04, 2026-05
    S3-S4 Multi-Agent+Learning        :         mn2, 2026-05, 2026-06

    section 👁️ Syn (TOR OCR/eKYC)
    S1 OCR Foundation                 :         syn1, 2026-04, 2026-05
    S2 eKYC + Thai ID                 :         syn2, 2026-05, 2026-06

    section 🗣️ Sága (TOR STT)
    S1 Whisper Foundation             :         sag1, 2026-05, 2026-06
    S2 Streaming + Call Center        :         sag2, 2026-06, 2026-07

    section 📨 Hermóðr (TOR Notify)
    S1 SMS/Push/Webhook               :         her1, 2026-05, 2026-06

    section 📸 Visual BMI
    PoC Gemini Flash                  :         vbmi1, 2026-04, 2026-04
    Pilot + STOP-BANG Integration     :         vbmi2, 2026-05, 2026-06
    Gemma 3 On-prem + Production      :         vbmi3, 2026-07, 2026-08
```

---

## Now / Next / Later

### 🟢 Now (Q2 2026 — April-June)

| Milestone | Component | Status | Done Criteria |
|:--|:--|:--|:--|
| Bifrost MVP | ⚡ Bifrost | 🚧 | ReAct loop works, calls tools via MCP |
| Unified Docker Compose | 🏰 Asgard | 📋 | Single `docker compose up` starts all services |
| Backup CLI | 🏰 Asgard | 📋 | `scripts/backup.sh` backs up MariaDB + Qdrant |
| **Huginn S1-S2** | 🐦‍⬛ **Huginn** | 🚧 | Foundation + DAST/SAST scan orchestration |
| **Muninn S1** | 🐦 **Muninn** | 📋 | Foundation + GitHub issue watching |
| 🆕 **Visual BMI PoC** | 📸 **FR-UW-BMI-01** | 📋 | Gemini 2.5 Flash PoC (1-2 days) + Digital Scale eval |
| 🆕 **Syn S1** | 👁️ **Syn** | 📋 | OCR Foundation (PaddleOCR + Thai ID parser) |

### 🔵 Next (Q3 2026 — July-September)

| Milestone | Component |
|:--|:--|
| Visual Workflow Builder | 🧠 Mimir |
| A2A Server + Client | 🧠 Mimir + ⚡ Bifrost |
| Fenrir MVP | 🐺 Fenrir |
| Documentation Site | 🏰 Asgard (asgardai.dev) |
| Intelligent Router | 🛡️ Heimdall |
| **Huginn S3-S5** | 🐦‍⬛ **Huginn** (AI Pentest + Multi-Agent + Purple Team) |
| **Muninn S2-S3** | 🐦 **Muninn** (AI Fix + Multi-Agent Pipeline) |
| 🆕 Visual BMI Pilot | 📸 Pilot + STOP-BANG integration + Gemma 3 on-prem |
| 🆕 Syn S2 | 👁️ eKYC + Face match |
| 🆕 Sága S1-S2 | 🗣️ STT Foundation + Streaming |
| 🆕 Hermóðr S1 | 📨 Notification Foundation (SMS/Push/Webhook) |

### 🟣 Later (Q4 2026 — October-December)

| Milestone | Component |
|:--|:--|
| Plugin System | ⚡ Bifrost |
| Agent Marketplace | 🧠 Mimir |
| Community v1.0 Launch | 🏰 All |
| **Huginn S6 + Polish** | 🐦‍⬛ **Huginn** (LLM Security + Compliance) |
| **Muninn S4** | 🐦 **Muninn** (Continuous Learning) |

> ℹ️ Knowledge Graph (Neo4j) already done in Mimir Sprint 17 (Mar 2026)

### 🔮 Future (2027+)

| Milestone | Component |
|:--|:--|
| Enterprise Edition v2.0 | 🏰 All |
| SSO / Advanced RBAC | 🌳 Yggdrasil |
| HA Clustering | 🏰 Asgard |
| White-Label | 🏰 Asgard |

---

## Release Milestones

| Version | Codename | Target | Key Deliverables |
|:--|:--|:--|:--|
| **v0.5** | Foundation | Q2 2026 | Unified Docker Compose, Bifrost MVP, Yggdrasil, **Huginn S1-S2**, 🆕 Visual BMI PoC, 🆕 Syn S1 |
| **v0.8** | Growth | Q3 2026 | Workflow Builder, A2A, Fenrir MVP, **Huginn S3-S5, Muninn S1-S3**, 🆕 Sága S1-S2, 🆕 Hermóðr S1, 🆕 Visual BMI Pilot |
| **v1.0** | Community Launch | Q4 2026 | Full platform, docs site, marketplace, **Huginn S6, Muninn S4** |
| **v2.0** | Enterprise | 2027 | SSO, HA, Analytics, White-Label, **Odin's Ravens Commercial** |

---

*📅 Last updated: March 2026*
