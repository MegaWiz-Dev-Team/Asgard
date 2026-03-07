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
    LLM Gateway (Production)          :done,    h1, 2025-06, 2025-12
    vLLM Backend (NVIDIA)             :active,  h2, 2026-04, 2026-06
    Intelligent Router                :         h3, 2026-06, 2026-08
    Zitadel JWT Validation            :         h4, 2026-05, 2026-06

    section 🧠 Mimir
    Sprint 1-8 (Core Platform)        :done,    m1, 2025-06, 2026-03
    Visual Workflow Builder            :         m2, 2026-06, 2026-09
    A2A Server                        :         m3, 2026-07, 2026-09
    Knowledge Graph (Neo4j)           :         m4, 2026-09, 2026-11

    section ⚡ Bifrost
    Agent Runtime MVP                 :active,  b1, 2026-04, 2026-07
    A2A Client                        :         b2, 2026-08, 2026-10
    Plugin System                     :         b3, 2026-10, 2026-12

    section 🐺 Fenrir
    Computer Use MVP                  :         f1, 2026-08, 2026-11

    section 🌳 Yggdrasil
    Zitadel Deployment                :         y1, 2026-05, 2026-06
    Mimir OIDC Migration              :         y2, 2026-06, 2026-07

    section 🏰 Asgard
    Unified Docker Compose            :active,  a1, 2026-04, 2026-05
    Backup/Restore CLI                :         a2, 2026-05, 2026-06
    Documentation Site                :         a3, 2026-06, 2026-08
```

---

## Now / Next / Later

### 🟢 Now (Q2 2026 — April-June)

| Milestone | Component | Status | Done Criteria |
|:--|:--|:--|:--|
| Bifrost MVP | ⚡ Bifrost | 🚧 | ReAct loop works, calls tools via MCP |
| Unified Docker Compose | 🏰 Asgard | 📋 | Single `docker compose up` starts all services |
| Heimdall vLLM | 🛡️ Heimdall | 📋 | Routes to vLLM backend on NVIDIA |
| Zitadel Deploy | 🌳 Yggdrasil | 📋 | Zitadel running, Mimir delegating login |
| Backup CLI | 🏰 Asgard | 📋 | `scripts/backup.sh` backs up MariaDB + Qdrant |

### 🔵 Next (Q3 2026 — July-September)

| Milestone | Component |
|:--|:--|
| Visual Workflow Builder | 🧠 Mimir |
| A2A Server + Client | 🧠 Mimir + ⚡ Bifrost |
| Fenrir MVP | 🐺 Fenrir |
| Documentation Site | 🏰 Asgard (asgardai.dev) |
| Intelligent Router | 🛡️ Heimdall |

### 🟣 Later (Q4 2026 — October-December)

| Milestone | Component |
|:--|:--|
| Knowledge Graph (Neo4j) | 🧠 Mimir |
| Plugin System | ⚡ Bifrost |
| Agent Marketplace | 🧠 Mimir |
| Community v1.0 Launch | 🏰 All |

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
| **v0.5** | Foundation | Q2 2026 | Unified Docker Compose, Bifrost MVP, Yggdrasil |
| **v0.8** | Growth | Q3 2026 | Workflow Builder, A2A, Fenrir MVP |
| **v1.0** | Community Launch | Q4 2026 | Full platform, docs site, marketplace |
| **v2.0** | Enterprise | 2027 | SSO, HA, Analytics, White-Label |

---

*📅 Last updated: March 2026*
