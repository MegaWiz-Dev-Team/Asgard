# 🔍 Asgard Multi-Agent Ecosystem — Gap Analysis

> **วันที่:** April 10, 2026
> **อ้างอิง:** [MultiAgent_Architecture_Plan.md](file:///Users/mimir/Developer/Asgard/docs/roadmap/MultiAgent_Architecture_Plan.md) v2.0 (15 sections)
> **วิธีวัด:** สแกน Source Code จริงเทียบกับ Architecture Requirement

---

## 📊 Executive Summary — ภาพรวม

```
Readiness Score (จาก Source Code จริง)

⚡ Bifrost       ██████░░░░░░░░░░  38%   ← คอขวดหลัก
📨 Hermóðr       ████████░░░░░░░░  50%
🏥 Eir           ██████████░░░░░░  65%
🧠 Mimir         ████████████░░░░  78%   ← แข็งที่สุด
🐺 Fenrir        ██████░░░░░░░░░░  40%
🐿️ Ratatoskr     ████████████░░░░  80%
🛡️ Heimdall      ██████████░░░░░░  62%
🌳 Yggdrasil     ████████░░░░░░░░  55%
🔱 Odin          ░░░░░░░░░░░░░░░░   0%   ← ยังไม่มี
🛡️ Várðr         ██████░░░░░░░░░░  35%
```

| Severity | Count | หมายถึง |
|----------|-------|---------|
| 🔴 Missing | 51 | ต้องสร้างใหม่ทั้งหมด |
| 🟡 Partial | 8 | มีฐานแล้ว ต้องเพิ่ม |
| 🟢 Done | 51 | ใช้ได้เลย |

---

## ⚡ Bifrost — Multi-Agent Orchestrator (38%)

> **ปัจจุบัน:** Rust (Axum + rig-core) มี Overseer, memory (memvid), retrieval (qdrant/graph/tree)
> **ขาด:** ยังเป็น single-agent executor ไม่ใช่ multi-agent orchestrator

### Backend

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| Axum + rig.rs runtime | §3 | 🟢 Done | มี Cargo.toml rig-core 0.10 | — |
| ReAct loop + Tool calling | §5 | 🟢 Done | Overseer + tool.rs | — |
| Memory (memvid .mv2) | §5 | 🟢 Done | souls.rs + memvid_manager.rs | — |
| Retrieval (Qdrant + Neo4j) | §5 | 🟢 Done | qdrant.rs + graph.rs | — |
| **MCP Client → Hermóðr** | §11 | 🔴 Missing | ไม่มี MCP client code | S4 |
| **Multi-Agent Delegation** | §5, §7 | 🔴 Missing | ไม่มี agent routing/delegation | S7 |
| **Confidence Scoring system** | §6 | 🟡 Partial | มี confidence ใน tree.rs แต่ไม่มี scoring pipeline | S7 |
| **Tool Allowlist (Deny-by-default)** | §10 | 🔴 Missing | ไม่มี allowlist enforcement | S7 |
| **Scope Guard** | §15 G3 | 🔴 Missing | ไม่มี intent classifier | S7 |
| **Dangerousness Classifier** | §15 G3 | 🔴 Missing | ไม่มี Step-up trigger | S7 |
| **Citation Enforcement** | §15 G5 | 🔴 Missing | ไม่มี source badge injection | S9 |
| **Confidence Gate (< 60%)** | §15 G5 | 🔴 Missing | | S9 |
| **Disclaimer Injection** | §15 G5 | 🔴 Missing | | S9 |
| **Persona Files loading** | §9 | 🔴 Missing | ไม่มี IDENTITY/TONE/CONTEXT loader | S4 |
| **A2A Client** | §11 | 🔴 Missing | ไม่มี A2A protocol | S8 |
| Progressive Loading (SSE) | §7 | 🟡 Partial | มี streaming แต่ไม่มี step-by-step status | S9 |

### Frontend
| Feature | Status | Gap | Sprint |
|---------|--------|-----|--------|
| Chat Sidebar (OpenEMR) | 🔴 Missing | ยังไม่มี frontend — embed ใน Eir | S10 |
| Feedback 3 ระดับ (✅✏️⚠️) | 🔴 Missing | ไม่มี UI | S11 |

---

## 📨 Hermóðr — Universal MCP Sidecar (50%)

> **ปัจจุบัน:** Rust JSON-RPC 2.0 bridge ครอบ Eir + Yggdrasil
> **ขาด:** ยังไม่ครอบ Heimdall, ไม่มี Prompt Injection Detection

### Backend

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| JSON-RPC 2.0 server | §3 | 🟢 Done | jsonrpc.rs + proxy.rs | — |
| Eir service bridge | §3 | 🟢 Done | services/eir.rs | — |
| Yggdrasil service bridge | §3 | 🟢 Done | services/yggdrasil.rs | — |
| Service registry | §3 | 🟢 Done | registry.rs | — |
| **Heimdall bridge** | §3 | 🔴 Missing | ไม่มี services/heimdall.rs | S1 |
| **Prompt Injection Detection** | §15 G1 | 🔴 Missing | Webhook Event Receiver | รับ Webhook จาก OpenEMR เมื่อมีการเปิดแฟ้ม, สั่งยา, และปิดแฟ้ม |
| 🔴 Missing | Secure Messaging Webhooks | (Hermes Core) Endpoint เปิดรับแชทจาก LINE/MS Teams และตรวจสอบ Auth กับ Yggdrasil ให้แพทย์สั่งการผ่านแอปภายนอก |
| 🔴 Missing | Context Router | นำ Event ที่ได้จาก Webhook แปลงเป็น Context แล้วส่งหา Bifrost |

### Frontend
| Feature | Status | Gap |
|---------|--------|-----|
| N/A | — | Hermóðr ไม่มี Frontend (ถูกต้อง — เป็น Infrastructure) |

---

## 🏥 Eir — FHIR Gateway + Context Router (65%)

> **ปัจจุบัน:** Rust Axum gateway ครอบ OpenEMR มี FHIR, Chat, A2A, Audit, JWKS
> **ขาด:** Context Router (Webhook Events), Auto Clinical Note

### Backend

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| FHIR R4 proxy | §3 | 🟢 Done | fhir.rs | — |
| Chat UI backend | §5 | 🟢 Done | chat.rs | — |
| JWKS Auth | §10 | 🟢 Done | jwks.rs + auth.rs | — |
| A2A endpoint | §11 | 🟢 Done | a2a.rs | — |
| Audit logging | §13 | 🟢 Done | audit.rs + mcp_audit.rs | — |
| Rate limiting | §15 G1 | 🟢 Done | rate_limit.rs | — |
| RBAC | §10 | 🟢 Done | rbac.rs | — |
| **Context Router (Webhook)** | §4 | 🟡 Partial | main.rs มี event routing แต่ไม่ครบ 6 triggers | S1 |
| **Auto Clinical Note draft** | §1 UC5 | 🔴 Missing | | S10 |
| **Pre-Visit Summary auto-popup** | §1 UC1 | 🔴 Missing | | S10 |

### Frontend
| Feature | Status | Gap | Sprint |
|---------|--------|-----|--------|
| Chat UI widget | 🟡 Partial | มี Chat แต่ยังไม่มี Sidebar embed | S10 |
| Drug Interaction Alert UI | 🔴 Missing | | S10 |

---

## 🧠 Mimir — Knowledge Engine (78%) ⭐

> **ปัจจุบัน:** Rust Axum + Next.js — 85 .rs files, 98 .tsx files, Sprint 29
> **ขาด:** PubMed Pipeline, PrimeKG Drug Interaction, MCP Server mode

### Backend

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| RAG Pipeline (Chunk/Embed/Search) | §2 | 🟢 Done | pipeline.rs + search.rs + vector.rs | — |
| Knowledge Graph (Neo4j) | §2 | 🟢 Done | graph.rs | — |
| Hybrid Search | §6 | 🟢 Done | search.rs + search_optimize.rs | — |
| MCP Server | §11 | 🟢 Done | mcp.rs | — |
| Quality Control | §5 | 🟢 Done | qc.rs | — |
| LLM Router (dynamic) | §5 | 🟢 Done | Built-in LlmRouter | — |
| Multi-tenant | §10 | 🟢 Done | tenant.rs | — |
| Agent Evaluations | §6 | 🟢 Done | eval.rs + rag_eval.rs | — |
| **PubMed Ingestion Pipeline** | §2B, §5 | 🔴 Missing | ไม่มี PubMed E-utilities integration | S2 |
| **PrimeKG Drug Interaction** | §2C | 🔴 Missing | มี graph แต่ไม่มี PrimeKG schema/Cypher | S2 |
| **3-Tier Article Curation** | §2B | 🔴 Missing | ไม่มี Guidelines/Evidence/Context tagging | S2 |
| **ICD-10 Multi-Locale** | §2E | 🟡 Partial | Python ⟶ Rust Translation | ย้าย RAG Retriever จาก Python ไป Rust ทั้งหมด (มีพื้นใน branch migration แล้ว) |
| 🔴 Missing | Agent Card Endpoint | ทำ `/.well-known/agent.json` ให้ Bifrost ค้นเจอ Mimir ผ่าน A2A ได้ |
| 🔴 Missing | GitOps Persona Synchronization | (Hermes Core) ระบบบันทึกและอัปเดตไฟล์ Persona ลงใน Git (.md/.json) ทุกครั้งที่ Deploy จาก Studio เพื่อทำ Audit Trail ทางการแพทย์ |
| **Billing Master Data** | §2F | 🔴 Missing | ไม่มี TMT/TMLT/Rezept data | S6 |

### Frontend (Next.js Dashboard)

| Feature | Status | Gap | Sprint |
|---------|--------|-----|--------|
| Sources management | 🟢 Done | 20+ pages | — |
| Playground + RAG | 🟢 Done | playground/ + rag-playground/ | — |
| Quality Control | 🟢 Done | quality_control/ | — |
| Knowledge Graph viz | 🟢 Done | graph/ | — |
| Evaluations | 🟢 Done | evaluations/ | — |
| Settings (5 tabs) | 🟢 Done | settings/ | — |
| **PubMed Source picker** | 🔴 Missing | ไม่มี PubMed ingestion UI | S2 |
| **Drug Interaction explorer** | 🔴 Missing | ไม่มี PrimeKG visualization | S2 |

---

## 🐺 Fenrir — Computer Use Agent (40%)

> **ปัจจุบัน:** Python FastAPI + browser-use + FHIR R4 client + Message Poller
> **ขาด:** Rust shell wrapper, Docker sandbox, e-Claim automation

### Backend

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| MCP Server (FastMCP) | §3 | 🟢 Done | api/mcp.py | — |
| FHIR R4 Client | §3 | 🟢 Done | fhir/client.py | — |
| Browser agent | §3 | 🟢 Done | browser/agent.py | — |
| OpenEMR Message Poller | §3 | 🟢 Done | openemr/message_poller.py | — |
| Task Router (FHIR vs Browser) | §3 | 🟢 Done | api/workflows.py | — |
| JWT Auth middleware | §10 | 🟢 Done | middleware/auth.py | — |
| **Rust Axum shell** | §3 Stack | 🔴 Missing | ยัง pure Python ไม่มี Rust wrapper | S5 |
| **Docker Sandbox per-task** | §10 | 🔴 Missing | มี ref ใน agent.py แต่ไม่มี container isolation | S5 |
| **e-Claim Auto-Submit** | §2F UC6 | 🔴 Missing | ไม่มี claim workflow | S5 |
| **Ratatoskr integration** | §3 | 🟡 Partial | ใช้ browser-use ตรง ไม่ผ่าน Ratatoskr API | S5 |

### Frontend
| Feature | Status | Gap |
|---------|--------|-----|
| N/A | — | Fenrir ไม่มี Frontend (ถูกต้อง — ควบคุมผ่าน Bifrost) |

---

## 🐿️ Ratatoskr — Shared Browser Service (80%) ⭐

> **ปัจจุบัน:** Rust Axum + headless_chrome — scrape, screenshot, fetch, MCP RPC
> **ขาด:** เล็กน้อย — ต้องเพิ่ม auth

### Backend

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| REST API (scrape/screenshot/fetch) | §3 | 🟢 Done | api.rs | — |
| MCP RPC endpoint | §3 | 🟢 Done | mcp.rs | — |
| Browser pool | §3 | 🟢 Done | browser.rs | — |
| Health endpoint | — | 🟢 Done | /healthz | — |
| **JWT Auth** | §10 | 🔴 Missing | ไม่มี auth middleware | S3 |
| **Rate limiting** | §15 G1 | 🔴 Missing | | S3 |

---

## 🛡️ Heimdall — LLM Gateway (62%)

> **ปัจจุบัน:** Rust Axum gateway — proxy, auth, embedding, metrics, GPU monitor
> **ขาด:** LLM Step-up Router, Temperature Clamp, Token Budget

### Backend

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| Multi-backend proxy | §3 | 🟢 Done | proxy.rs | — |
| API Key auth | §10 | 🟢 Done | auth.rs | — |
| Native Embedding (bge-m3) | §3 | 🟢 Done | embedding.rs | — |
| Prometheus metrics | §12 | 🟢 Done | metrics_handler.rs | — |
| GPU monitoring | §12 | 🟢 Done | gpu.rs | — |
| Health check | — | 🟢 Done | health.rs | — |
| **LLM Step-up Router** | §5 | 🔴 Missing | ไม่มี cloud fallback (Gemini) logic | S6 |
| **Temperature Clamp (≤ 0.3)** | §15 G4 | 🔴 Missing | Memory Component (memvid) | สร้างระบบ memory graph เพื่อจดจำ context ของแต่ละ Session เปิดทำงาน |
| 🔴 Missing | Trajectory Context Compressor | (Hermes Core) บีบอัด Context เมื่อประวัติคนไข้ยาวเกิน 70% ก่อนส่งให้โมเดลเพื่อประหยัด Token และกันความสับสน |
| 🔴 Missing | Preference Memory Auto-Update | (Hermes Core) ระบบวิเคราะห์พฤติกรรมการพิมพ์ ✏️ เพื่อเสนออัตโนมัติในการปรับ Identity ของ Agent |
| 🔴 Missing | A2A Protocol Server | สร้าง Endpoint ให้ Agent ภายนอกสามารถ broadcast ตัวเองเข้ามาหา Bifrost ได้ |
| **System Prompt Injection** | §15 G4 | 🔴 Missing | ไม่มี Persona file injection | S4 |
| **Timeout + Fallback** | §15 G4 | 🟡 Partial | มี timeout แต่ไม่มี fallback strategy | S3 |

### Frontend
| Feature | Status | Gap |
|---------|--------|-----|
| N/A | — | Heimdall ไม่มี Frontend (ถูกต้อง — pure API Gateway) |

---

## 🌳 Yggdrasil — Identity & Auth (55%)

> **ปัจจุบัน:** Python SDK — JWT validation, JWKS, FastAPI deps, Management API
> **ขาด:** PII Scrubbing, Consent Verification, Machine-User Token management

### Backend

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| JWT Validation (RS256) | §10 | 🟢 Done | middleware.py | — |
| JWKS Caching | §10 | 🟢 Done | fastapi.py | — |
| Multi-tenant mapping | §10 | 🟢 Done | models.py | — |
| Management API client | §10 | 🟢 Done | client.py | — |
| Service Account tokens | §10 | 🟢 Done | service_account.py | — |
| **PII/PHI Scrubbing** | §15 G2 | 🔴 Missing | ไม่มี de-identification module | S3 |
| **Consent Verification** | §15 G2 | 🔴 Missing | ไม่มี patient consent check | S13 |
| **Machine-User Token per Agent** | §10 | 🟡 Partial | มี service_account แต่ไม่มี per-agent tokens | S3 |
| **Tenant Boundary Enforcement** | §15 G2 | 🟡 Partial | มี mapping แต่ไม่มี enforcement middleware | S3 |

---

## 🔱 Odin — Platform Supervisor (0%) 🔴

> **ปัจจุบัน:** ยังไม่มี — ไม่มี directory `/Users/mimir/Developer/Odin/`
> **ต้องการ:** Job Scheduler, Health Monitor, QA Auditor, Knowledge Lifecycle Manager

### Backend — ต้องสร้างใหม่ทั้งหมด

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| **Cargo scaffold** | §3 | 🔴 Missing | ไม่มี repo | S4 |
| **Job Scheduler (Cron)** | §4 | 🔴 Missing | PubMed weekly, Patient cache daily | S4 |
| **Health Monitor** | §4 | 🔴 Missing | Ping ทุก Agent ทุก 5 นาที | S6 |
| **QA Auditor** | §4 | 🔴 Missing | Circuit Breaker + Drift Detection | S12 |
| **Knowledge Lifecycle** | §4 | 🔴 Missing | | S12 |
| **Bias Monitoring** | §15 G6 | 🔴 Missing | Pharmaceutical bias detection | S12 |

### Frontend
| Feature | Status | Gap | Sprint |
|---------|--------|-----|--------|
| **QA Dashboard** | 🔴 Missing | Feedback stats, Agent health | S12 |

---

## 🛡️ Várðr — Observability (35%)

> **ปัจจุบัน:** Rust Axum — Docker container stats, logs, alerts, Prometheus
> **ขาด:** OpenTelemetry, Agent call chain tracing, Clinical Trace format

### Backend

| Feature | Arch Ref | Status | Gap | Sprint |
|---------|----------|--------|-----|--------|
| Service health monitoring | §12 | 🟢 Done | docker.rs | — |
| Log viewer + SSE streaming | §12 | 🟢 Done | main.rs log routes | — |
| Container metrics | §12 | 🟢 Done | prometheus.rs | — |
| Alert rules | §12 | 🟢 Done | alerts.rs | — |
| Auto-restart | §12 | 🟢 Done | auto_restart.rs | — |
| Uptime tracking | §12 | 🟢 Done | uptime.rs | — |
| **OpenTelemetry integration** | §12 | 🔴 Missing | ไม่มี OTel SDK | S8 |
| **Agent call chain tracing** | §12 | 🔴 Missing | ไม่มี Trace ID propagation | S8 |
| **Clinical Trace JSON** | §12 | 🔴 Missing | ไม่มี structured trace format | S8 |
| **Audit Trail ↔ Trace linking** | §13 | 🔴 Missing | | S11 |

### Frontend (Embedded HTML)
| Feature | Status | Gap | Sprint |
|---------|--------|-----|--------|
| Container monitoring dashboard | 🟢 Done | Glassmorphism UI | — |
| **Agent Trace viewer** | 🔴 Missing | ต้องสร้าง trace timeline UI | S8 |

---

## 🏗️ Cross-Cutting Gaps (ไม่อยู่ในโปรเจกต์ใดโปรเจกต์หนึ่ง)

| Gap | Arch Ref | ขาดอยู่ที่ | Sprint |
|-----|----------|-----------|--------|
| **Agent Persona Files** (IDENTITY/TONE/CONTEXT) | §9 | ยังไม่มี `asgard/personas/` directory | S4 |
| **Structured Audit Trail schema** | §13 | ยังไม่มี 14-field DB schema | S11 |
| **Shadow Mode** | §14 | ไม่มี code path สำหรับ "recommend only" | S13 |
| **IEC 62304 Safety Case** | §14 | ยังไม่มีเอกสาร | S14 |
| **Docker Compose unified** | §5 | มีอยู่แล้ว ✅ แต่ต้องเพิ่ม Odin + Sandbox Fenrir | S4 |

---

## 📈 Gap Count Summary

| Project | 🟢 Done | 🟡 Partial | 🔴 Missing | Total Gaps | Critical Path? |
|---------|---------|------------|------------|------------|----------------|
| ⚡ Bifrost | 4 | 2 | 14 | **20** | ⚠️ **YES** — ทุกอย่างต่อคิว |
| 📨 Hermóðr | 4 | 0 | 3 | **7** | S1 |
| 🏥 Eir | 7 | 1 | 6 | **14** | S1, S10 |
| 🧠 Mimir | 9 | 1 | 8 | **18** | S2 |
| 🐺 Fenrir | 6 | 1 | 3 | **10** | S5 |
| 🐿️ Ratatoskr | 4 | 0 | 2 | **6** | Minor |
| 🛡️ Heimdall | 6 | 1 | 4 | **11** | S3, S6 |
| 🌳 Yggdrasil | 5 | 2 | 2 | **9** | S3 |
| 🔱 Odin | 0 | 0 | 7 | **7** | ⚠️ **YES** — ไม่มีเลย |
| 🛡️ Várðr | 6 | 0 | 4 | **10** | S8 |
| **Cross-Cutting** | 0 | 0 | 5 | **5** | |
| **Total** | **51** | **8** | **58** | **117** | |

---

## 🎯 Critical Path — สิ่งที่ต้องทำก่อน

```
S1: Hermóðr Bridge (Heimdall) + Eir Context Router + G1 Guardrail
     ↓
S2: Mimir PubMed Pipeline + PrimeKG ← ข้อมูลทางการแพทย์ต้องพร้อมก่อน
     ↓
S3: Yggdrasil PII Scrubbing + Heimdall G4 ← Security ต้องพร้อมก่อนเปิด Agent
     ↓
S4: Bifrost MCP Client + Persona Files + Odin Scaffold ← Orchestrator เริ่มทำงาน
     ↓
S5: Fenrir Sandbox ← Browser Agent ปลอดภัย
     ↓
S7: Bifrost Multi-Agent Delegation ← ทุกอย่างมาประกอบกัน
```

> [!WARNING]
> **Bifrost (14 gaps) และ Odin (6 gaps, ไม่มีเลย)** คือ 2 คอขวดหลัก — ต้องโฟกัสที่ S4-S7

---

*📅 Generated: April 10, 2026 — จาก Source Code scan จริง*
