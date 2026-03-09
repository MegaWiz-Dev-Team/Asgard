# 📚 Asgard AI Platform — Documentation

> Consolidated documentation for developers, partners, and investors.

---

## 📋 Table of Contents

### Strategy & Planning

| Document | Description |
|:--|:--|
| 🎯 [Product Direction](strategy/product-direction.md) | Vision, design principles, anti-goals, strategic priorities |
| 📊 [Platform Review](strategy/platform-review.md) | Platform overview, strengths, gap analysis, licensing |
| 🗺️ [Roadmap](strategy/roadmap.md) | Development roadmap with Gantt chart and milestones |
| 🎯 [Competitor & Target Market Analysis](strategy/competitor-analysis.md) | 8 competitors analyzed, market gaps, positioning |
| 🗺️ [Gap → Project Mapping](strategy/gap-mapping.md) | Maps every gap to a specific project for implementation |
| 🚀 [MVP v1.0 Scope](strategy/mvp-v1.0.md) | MoSCoW prioritization, done criteria, launch checklist |

### Business

| Document | Description |
|:--|:--|
| 💰 [Pricing Strategy](business/pricing-strategy.md) | Community vs Enterprise tiers, competitive benchmark |
| 📈 [Business Plan](business/business-plan.md) | Market sizing, financial projections, team, funding |
| 🚀 [Go-to-Market](business/go-to-market.md) | Launch phases, adoption funnel, community & enterprise sales |

### Architecture & Technical

| Document | Description |
|:--|:--|
| 🏗️ [Architecture Overview](architecture.md) | System architecture, data flow, component specs |
| 🌳 [Yggdrasil Auth Selection](technical/yggdrasil-auth-selection.md) | Auth platform comparison — Zitadel selected |
| 🔧 [ADK-Rust Evaluation](technical/adk-rust-evaluation.md) | ADK-Rust analysis, workflow builder decision, A2A protocol |

### Legal & Community

| Document | Description |
|:--|:--|
| 📜 [LICENSE](../LICENSE) | AGPL-3.0 — Community Edition |
| 🏢 [COMMERCIAL.md](../COMMERCIAL.md) | Enterprise licensing information |
| 📝 [CLA.md](../CLA.md) | Contributor License Agreement |
| 👥 [CONTRIBUTORS.md](../CONTRIBUTORS.md) | Contributor list |
| 🤝 [CONTRIBUTING.md](../CONTRIBUTING.md) | How to contribute |
| 📜 [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) | Community standards |

---

## 🏰 Platform Overview

```mermaid
graph LR
    User["👤 User"] --> Mimir["🧠 Mimir<br/>RAG + Agent Builder"]
    User --> Bifrost["⚡ Bifrost<br/>Agent Runtime"]

    Bifrost --> |"LLM"| Heimdall["🛡️ Heimdall<br/>LLM Gateway"]
    Bifrost --> |"MCP"| Mimir
    Bifrost --> |"MCP"| Fenrir["🐺 Fenrir<br/>Computer Use"]

    Heimdall --> LLM["🍎 MLX · llama.cpp · Ollama · vLLM"]

    Yggdrasil["🌳 Yggdrasil<br/>Auth (Zitadel)"] -.-> Heimdall
    Yggdrasil -.-> Mimir
    Yggdrasil -.-> Bifrost
```

| Component | Description | Tech | Status |
|:--|:--|:--|:--|
| 🛡️ **Heimdall** | LLM Gateway | Rust (Axum) | ✅ Production |
| 🧠 **Mimir** | RAG + Agent Builder | Rust (Axum) + Next.js 14 | ✅ Sprint 23 Done |
| ⚡ **Bifrost** | Agent Runtime | Python (FastAPI) | 🚧 Scaffolding |
| 🐺 **Fenrir** | Computer Use | Python (Browser Use + FHIR) | 📋 Planned |
| 🏥 **Eir** | Clinic Management | OpenEMR (PHP, GPL v3) | 📋 Planned |
| 🌳 **Yggdrasil** | Auth Service | Zitadel (Go) | 📋 Planned |

---

## 💼 For Investors

Recommended reading order:

1. **[Platform Review](strategy/platform-review.md)** — Understand the platform, roadmap, and licensing
2. **[Competitor Analysis](strategy/competitor-analysis.md)** — Market landscape and differentiation
3. **[COMMERCIAL.md](../COMMERCIAL.md)** — Business model and Enterprise features

---

## 📞 Contact

- 📧 Email: paripol@megawiz.co
- 🏢 Organization: [MegaWiz](https://github.com/megacare-dev)

---

© 2026 MegaWiz — Licensed under AGPL-3.0
