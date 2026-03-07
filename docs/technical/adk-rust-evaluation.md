# 🔧 ADK-Rust Evaluation & Workflow Builder Decision

> ตัดสินใจ: Visual Workflow Builder + ADK-Rust integration strategy สำหรับ Asgard
>
> 📅 ตัดสินใจ: 7 มี.ค. 2026

---

## 1. ADK-Rust Evaluation

[zavora-ai/adk-rust](https://github.com/zavora-ai/adk-rust) เป็น full-stack Rust agent framework (25+ crates) ที่ครอบคลุม Agent, RAG, Browser, Voice, MCP, UI Studio

### ✅ ตัดสินใจ: ไม่ใช้ ADK-Rust แทน Rig ใน Mimir

| เหตุผล | รายละเอียด |
|:--|:--|
| **ทำลาย architecture** | Asgard = microservices, ADK-Rust = monolith framework |
| **Mimir มี 8 sprints แล้ว** | Rewrite = เสียเวลามหาศาล |
| **Dependency risk** | ขึ้นกับ Zavora AI ทั้งหมด |
| **ไม่มี MLX/vLLM** | USP ของ Asgard หายไป |
| **Full adopt = Asgard ซ้ำซ้อน** | ADK-Rust ทำทุกอย่าง → Asgard ไม่มีเหตุผลจะมี |

### ✅ ตัดสินใจ: Cherry-Pick + Reference

| Strategy | ใช้อะไร | ใช้ใน | วิธีใช้ |
|:--|:--|:--|:--|
| **Cherry-pick** | `adk-guardrail` | Mimir | PII redaction สำหรับ Healthcare |
| **Reference** | `adk-graph` patterns | Bifrost | LangGraph-style workflow reference |
| **Reference** | `adk-browser` patterns | Fenrir | WebDriver tools reference |
| **Reference** | `adk-eval` patterns | Mimir | Agent evaluation patterns |
| **Study** | Architecture | ทุก component | เรียนรู้ Graph Agent, A2A protocol |

---

## 2. Visual Workflow Builder Decision

### ✅ ตัดสินใจ: Option A — ReactFlow + Mimir Dashboard

| ทำไมเลือก | |
|:--|:--|
| **ไม่ต้องเพิ่ม service** | อยู่ใน Mimir Dashboard (Next.js 14) เลย |
| **Full integration** | ต่อ Heimdall/Bifrost/Fenrir ได้ 100% |
| **Competitive advantage** | Visual builder ตัวเดียวที่ต่อ local inference ได้ |
| **Same stack** | Mimir ใช้ Next.js อยู่แล้ว → เพิ่ม ReactFlow component |

### ทำไมไม่ใช้ ADK Studio

| ปัญหา | |
|:--|:--|
| Tight coupling | สร้างมาเพื่อ generate ADK-Rust code เท่านั้น |
| ต้อง adopt ADK ทั้งหมด | ไม่สามารถใช้กับ Rig/Mimir ได้ |
| Rust-only output | Bifrost (Python) ใช้ไม่ได้ |

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

### ✅ ตัดสินใจ: Support A2A ใน Mimir + Bifrost

[A2A (Agent-to-Agent)](https://github.com/google/A2A) คือ open standard จาก Google/Linux Foundation สำหรับ inter-agent communication

| | |
|:--|:--|
| **A2A** | Agent ↔ Agent (discovery, task delegation, collaboration) |
| **MCP** | Agent ↔ Tools (function calling, data access) |
| **ทั้งคู่** | Complementary — Asgard ต้อง support ทั้ง A2A + MCP |

**Implementation plan:**

| Component | Role | Priority |
|:--|:--|:--|
| 🧠 Mimir | A2A Server — expose agents + Agent Card registry | Phase 2 |
| ⚡ Bifrost | A2A Client — call external agents | Phase 2 |
| 🛡️ Heimdall | A2A proxy + auth | Phase 2 |

---

## 4. Impact on Roadmap

เพิ่มใน **Phase 2: Community Growth (v1.x)**:

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
