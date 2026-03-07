# 🔧 ADK-Rust Evaluation & Workflow Builder Decision

> Decisions: Visual Workflow Builder + ADK-Rust integration strategy for Asgard
>
> 📅 Decided: March 7, 2026

---

## 1. ADK-Rust Evaluation

[zavora-ai/adk-rust](https://github.com/zavora-ai/adk-rust) is a full-stack Rust agent framework (25+ crates) covering Agent, RAG, Browser, Voice, MCP, UI Studio.

### ✅ Decision: Do NOT replace Rig with ADK-Rust in Mimir

| Reason | Details |
|:--|:--|
| **Destroys architecture** | Asgard = microservices, ADK-Rust = monolith framework |
| **Mimir has 8 sprints already** | Rewrite = massive time investment |
| **Dependency risk** | Fully dependent on Zavora AI |
| **No MLX/vLLM** | Asgard's USP would disappear |
| **Full adopt = Asgard redundant** | ADK-Rust does everything → no reason for Asgard to exist |

### ✅ Decision: Cherry-Pick + Reference

| Strategy | What | Use in | How |
|:--|:--|:--|:--|
| **Cherry-pick** | `adk-guardrail` | Mimir | PII redaction for Healthcare |
| **Reference** | `adk-graph` patterns | Bifrost | LangGraph-style workflow reference |
| **Reference** | `adk-browser` patterns | Fenrir | WebDriver tools reference |
| **Reference** | `adk-eval` patterns | Mimir | Agent evaluation patterns |
| **Study** | Architecture | All components | Learn Graph Agent, A2A protocol patterns |

---

## 2. Visual Workflow Builder Decision

### ✅ Decision: Option A — ReactFlow + Mimir Dashboard

| Why this option | |
|:--|:--|
| **No extra service needed** | Lives inside Mimir Dashboard (Next.js 14) |
| **Full integration** | Connects to Heimdall/Bifrost/Fenrir 100% |
| **Competitive advantage** | Only visual builder that connects to local inference |
| **Same stack** | Mimir already uses Next.js → add ReactFlow component |

### Why NOT ADK Studio

| Issue | |
|:--|:--|
| Tight coupling | Built exclusively to generate ADK-Rust code |
| Must adopt all of ADK | Cannot work with Rig/Mimir |
| Rust-only output | Bifrost (Python) incompatible |

### Architecture

```
Mimir Dashboard (Next.js 14)
├── existing pages...
└── /workflow-builder (NEW)
    ├── ReactFlow canvas
    ├── Node types:
    │   ├── 🛡️ LLM (via Heimdall API)
    │   ├── 📚 RAG Query (via Mimir API)
    │   ├── 🔧 Tool Call (via Bifrost API)
    │   ├── 🐺 Browser Action (via Fenrir API)
    │   ├── ⚡ Condition / Switch
    │   ├── 🔄 Loop
    │   └── 📤 Output / Webhook
    ├── Save/Load workflows → MariaDB
    └── Execute → Bifrost Agent Runtime
```

### References to Study

| Project | What to Learn |
|:--|:--|
| [ADK Studio](https://github.com/zavora-ai/adk-rust/tree/main/adk-studio) | Node types, debug mode, code generation UX |
| [Sim Studio](https://github.com/simstudioai/sim) | Next.js + ReactFlow integration, 100+ connectors |
| [ReactFlow AI Template](https://reactflow.dev/) | Core library (MIT, 25K+ ⭐) |
| [Flowise](https://flowiseai.com/) | LLM-specific node patterns |

---

## 3. A2A Protocol Decision

### ✅ Decision: Support A2A in Mimir + Bifrost

[A2A (Agent-to-Agent)](https://github.com/google/A2A) is an open standard from Google/Linux Foundation for inter-agent communication.

| | |
|:--|:--|
| **A2A** | Agent ↔ Agent (discovery, task delegation, collaboration) |
| **MCP** | Agent ↔ Tools (function calling, data access) |
| **Both** | Complementary — Asgard must support both A2A + MCP |

**Implementation plan:**

| Component | Role | Priority |
|:--|:--|:--|
| 🧠 Mimir | A2A Server — expose agents + Agent Card registry | Phase 2 |
| ⚡ Bifrost | A2A Client — call external agents | Phase 2 |
| 🛡️ Heimdall | A2A proxy + auth | Phase 2 |

---

## 4. Impact on Roadmap

Added to **Phase 2: Community Growth (v1.x)**:

```diff
### Phase 2: Community Growth (v1.x)
  - [ ] Bifrost MVP (Agent Runtime)
  - [ ] Heimdall vLLM backend
+ - [ ] Mimir Visual Workflow Builder (ReactFlow)
+ - [ ] Mimir A2A Server (Agent-to-Agent protocol)
+ - [ ] Bifrost A2A Client
+ - [ ] adk-guardrail integration (PII redaction)
  - [ ] Agent Template Marketplace
```

---

*📅 Last updated: March 2026*
