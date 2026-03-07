# 🏰 Asgard — Product Direction

> Last updated: March 2026

---

## Vision Statement

> **"The complete self-hosted AI platform — from LLM Gateway to Computer Use Agent — running on your own hardware."**

Asgard lets any organization deploy a full AI stack on Apple Silicon or NVIDIA GPU, with zero cloud dependency. Your data stays on your premises, your models run locally, and you maintain full control.

---

## Design Principles

1. **Self-hosted first** — Every feature must work offline on a single machine. Cloud is optional, never required.
2. **Modular by default** — Components are independent. Deploy only what you need. Scale each piece separately.
3. **Local inference is the product** — Native MLX/vLLM performance is our competitive advantage. Never compromise it.
4. **Developer experience matters** — One-command install. OpenAI-compatible APIs. Clear docs. If it's hard to set up, we failed.
5. **Transparency** — Open source (AGPL-3.0), documented decisions (ADRs), public roadmap.

---

## Anti-Goals (What Asgard Will NOT Do)

| Anti-Goal | Why |
|:--|:--|
| **Cloud-hosted SaaS** | We are a self-hosted platform. Running a cloud service would compete with our own users. |
| **Custom model training** | We provide inference and RAG, not training infrastructure. Use Axolotl/Unsloth for training. |
| **Replace Ollama/vLLM** | We complement inference engines, not compete with them. Heimdall routes to them. |
| **Windows-first** | Our primary targets are macOS (MLX) and Linux (NVIDIA). Windows is community-contributed. |
| **Monolith framework** | We stay microservices. Each component has its own repo, stack, and release cycle. |

---

## Strategic Priorities (Next 6 Months)

| # | Priority | Gap Addressed | Differentiator vs Dify | Effort | Status |
|:--|:--|:--|:--|:--|:--|
| 1 | **Bifrost MVP** | Agent Runtime is core value | Full agent with local inference | XL | 🚧 |
| 2 | **Unified Docker Compose** | Must run in 15 minutes | True one-command deploy | M | 📋 |
| 3 | **Yggdrasil Integration** | Centralized Auth | Enterprise SSO out of box | L | 📋 |
| 4 | **Heimdall vLLM Backend** | NVIDIA GPU support | Dual hardware platform | M | 📋 |
| 5 | **Visual Workflow Builder** | Competitor parity with Dify | ReactFlow + local inference | L | 📋 |

---

## Success Metrics

| Metric | Type | Target (6 months) |
|:--|:--|:--|
| **Monthly Docker Pulls** | North Star | 1,000+ |
| **GitHub Stars (all repos)** | Leading | 500+ |
| **Community Contributors** | Leading | 10+ |
| **Design Partners** | Lagging | 3-5 orgs |
| **Documentation Coverage** | Leading | All 23 sprints documented (ISO 29110) |

---

## Key Decisions Log

| Decision | Date | ADR |
|:--|:--|:--|
| Auth platform → Zitadel | Mar 2026 | [yggdrasil-auth-selection.md](../technical/yggdrasil-auth-selection.md) |
| ADK-Rust → Cherry-pick | Mar 2026 | [adk-rust-evaluation.md](../technical/adk-rust-evaluation.md) |
| Workflow Builder → ReactFlow | Mar 2026 | [adk-rust-evaluation.md](../technical/adk-rust-evaluation.md) |
| A2A Protocol → Support | Mar 2026 | [adk-rust-evaluation.md](../technical/adk-rust-evaluation.md) |
| License → AGPL-3.0 | Mar 2026 | [platform-review.md](platform-review.md) |
| Domain → asgardai.dev | Mar 2026 | — |
| Database → MariaDB | — | Mimir README |
