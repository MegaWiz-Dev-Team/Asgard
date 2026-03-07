# 🏰 Asgard AI Platform

> *The realm of the gods — a self-hosted AI agent platform built on Apple Silicon*

**Asgard** is an open ecosystem of AI services designed to run entirely on local hardware (Mac Mini M4 Pro, 64GB). From LLM inference to autonomous agent execution and computer control — everything runs on-premises with zero cloud dependency.

Originally built to power AI NPCs for **Ragnarok Online**, Asgard has evolved into a general-purpose AI platform for healthcare, knowledge management, and autonomous workflows.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    🏰 Asgard AI Platform                     │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  🧠 Mimir     │  │  ⚡ Bifrost   │  │  🛡️ Heimdall  │       │
│  │              │  │              │  │              │       │
│  │  RAG Pipeline │  │ Agent Runtime│  │ LLM Gateway  │       │
│  │  Agent Builder│  │ Tool Executor│  │ Multi-backend│       │
│  │  Dashboard    │  │ MCP Client   │  │ Auth/Metrics │       │
│  │              │  │              │  │              │       │
│  │  Rust/Axum   │  │ Python/Fast  │  │ Rust/Axum    │       │
│  │  Next.js     │  │ API          │  │              │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                  │               │
│         │          ┌──────┴───────┐          │               │
│         │          │ MCP Protocol │          │               │
│         │          └──────┬───────┘          │               │
│         │                 │                  │               │
│  ┌──────┴───────┐  ┌──────┴───────┐          │               │
│  │  mimir-mcp   │  │  🐺 Fenrir    │          │               │
│  │  RAG Tools   │  │  Computer Use│          │               │
│  │              │  │  Browser Ctrl│          │               │
│  │              │  │  Shell/File  │          │               │
│  └──────────────┘  └──────────────┘          │               │
│                                              │               │
│                    MLX · llama.cpp · Ollama ──┘               │
│                    (Apple Silicon optimized)                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Components

| Component | Description | Tech Stack | Repo |
|:--|:--|:--|:--|
| 🧠 **[Mimir](https://github.com/megacare-dev/Mimir)** | RAG Pipeline, Agent Builder, Dashboard | Rust (Axum), Next.js, SQLite | Private |
| 🛡️ **[Heimdall](https://github.com/megacare-dev/Heimdall)** | LLM Gateway — multi-backend proxy with auth & metrics | Rust (Axum) | Private |
| ⚡ **[Bifrost](https://github.com/megacare-dev/Bifrost)** | Agent Runtime Engine — ReAct loop, tool execution, session mgmt | Python (FastAPI) | Private |
| 🐺 **[Fenrir](https://github.com/megacare-dev/Fenrir)** | Computer-Use Agent — browser control, shell, screen capture | Rust (ZeroClaw-based) | Private |
| 🏰 **Asgard** *(this repo)* | Ecosystem docs, architecture, docker-compose, roadmap | — | **Public** |

---

## 🎯 Mission

Build a **self-hosted AI platform** that enables:

1. **Knowledge Management** — Ingest, chunk, embed, and search documents with RAG
2. **Autonomous Agents** — Create and deploy agents that can reason, use tools, and take actions
3. **Computer Control** — Agents that can browse the web, fill forms, extract data, and automate workflows
4. **AI NPCs** — Intelligent non-player characters for Ragnarok Online with memory and personality
5. **Healthcare AI** — Medical knowledge assistants with domain-specific models (MedGemma)

---

## 🔧 Hardware Requirements

| Component | Spec |
|:--|:--|
| **Machine** | Mac Mini M4 Pro (or any Apple Silicon) |
| **Memory** | 64GB Unified Memory (recommended) |
| **Storage** | 1TB+ SSD |
| **OS** | macOS 15+ (Sequoia) |

> All LLM inference runs locally via MLX, llama.cpp, or Ollama — no cloud APIs required.

---

## 🗺️ Roadmap

### Phase 1: Foundation ✅
- [x] Heimdall — LLM Gateway with multi-backend support
- [x] Mimir — RAG Pipeline with document ingestion
- [x] Mimir — Agent Builder (CRUD, templates, chat)
- [x] Mimir — Dashboard (Next.js admin UI)
- [x] Multi-model benchmarking (Qwen, Gemma, MedGemma)

### Phase 2: Agent Runtime 🚧
- [ ] Bifrost — Agent Executor (ReAct loop)
- [ ] Bifrost — MCP tool integration
- [ ] Bifrost — Session management (short-term + long-term memory)
- [ ] Built-in tools: RAG search, HTTP, calculator

### Phase 3: Computer Use
- [ ] Fenrir — ZeroClaw fork with Heimdall integration
- [ ] Browser automation (Playwright)
- [ ] Form filling & data extraction
- [ ] Screen capture & keyboard/mouse control

### Phase 4: AI NPCs for Ragnarok Online
- [ ] NPC personality system
- [ ] Quest generation
- [ ] Dynamic dialogue with memory
- [ ] Game event integration via rAthena

---

## 🏛️ Naming Convention

All components are named after entities from **Norse mythology**, inspired by the Ragnarok Online universe:

| Name | Norse Origin | Role in Asgard |
|:--|:--|:--|
| **Asgard** | Realm of the gods | The platform / ecosystem |
| **Mimir** | God of wisdom, keeper of knowledge | Knowledge & RAG |
| **Heimdall** | Guardian of the Bifrost bridge | LLM Gateway |
| **Bifrost** | The burning rainbow bridge | Agent Runtime bridge |
| **Fenrir** | The great wolf | Computer-use power |

---

## 📄 License

Individual components have their own licenses. See each repo for details.

---

<p align="center">
  <strong>🏰 Asgard AI Platform</strong>
  <br/>
  <em>Self-hosted AI. Norse-inspired. Built on Apple Silicon.</em>
  <br/><br/>
  <a href="https://github.com/megacare-dev/Mimir">Mimir</a> ·
  <a href="https://github.com/megacare-dev/Heimdall">Heimdall</a> ·
  <a href="https://github.com/megacare-dev/Bifrost">Bifrost</a> ·
  <a href="https://github.com/megacare-dev/Fenrir">Fenrir</a>
</p>
