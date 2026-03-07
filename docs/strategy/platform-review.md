# 🏰 Asgard Platform Review — SME Self-Hosted + Open Source Strategy

> **Context**: ทบทวนสถาปัตยกรรม Asgard สำหรับ use case: Self-hosted on-prem สำหรับ SME ขนาดกลาง
> โดยวางแผนเป็น **Community Edition (OSS)** + **Enterprise Edition (Commercial)** ในอนาคต

---

## 1. 💪 จุดแข็งของ Platform ปัจจุบัน

### Architecture ดีมาก
- **Modular Microservices** — แยก component ชัดเจน (Heimdall, Mimir, Bifrost, Fenrir) ทำให้ deploy เฉพาะส่วนที่ต้องการได้
- **OpenAI-Compatible API** — ลูกค้า SME ที่ใช้ OpenAI อยู่แล้วสามารถ migrate มาใช้ได้โดยแค่เปลี่ยน endpoint
- **Multi-Backend Strategy** — MLX, llama.cpp, Ollama, vLLM ครอบคลุมทุก use case
- **Rust + Python hybrid** — Performance-critical parts (Gateway, RAG) ใช้ Rust, AI-ecosystem parts (Agent) ใช้ Python

### Mimir มีความพร้อมสูง (8 Sprints Done)

| Feature | Status | รายละเอียด |
|:--|:--|:--|
| **Multi-Tenant IAM** | ✅ Done | JWT auth, Argon2id password, role-based access |
| **Admin Dashboard** | ✅ Done | Tenant switcher, user management, settings |
| **Unified Data Ingress** | ✅ Done | File upload (PDF/CSV/XLSX/HTML), web scraper, MCP connector |
| **Quality Control** | ✅ Done | LLM data clustering, conflict resolution Kanban |
| **Agent Evaluations** | ✅ Done | LLM-as-a-judge, heatmap scoring, human override |
| **Pipeline Traceability** | ✅ Done | Source → Vector → Answer end-to-end tracking |
| **NPC Playground** | ✅ Done | Tier 1 (simple chat) & Tier 2 (RAG) with streaming |
| **Real-time Monitoring** | ✅ Done | WebSocket/SSE streaming logs |
| **Docker Compose** | ✅ Done | MariaDB + Qdrant + rAthena |

**Mimir Tech Stack:**

| Layer | Technology |
|:--|:--|
| Backend | Rust (Axum + [Rig.rs](https://rig.rs)) |
| Frontend | Next.js 14 + TailwindCSS + shadcn/ui |
| Database | MariaDB (relational) |
| Vector DB | Qdrant (semantic search) |
| Graph DB | Neo4j Community (Sprint 11) |
| Graph Viz | Sigma.js + graphology (WebGL) |
| LLM Providers | Ollama (local), Google Gemini, Qwen API |
| Embedding | nomic-embed-text, text-embedding-004, bge-m3 |
| Infrastructure | Docker Compose |

### เหมาะกับ SME On-Prem
- **Zero Cloud Dependency** — ข้อมูลไม่ออกจากบริษัท → ตอบโจทย์ data sovereignty
- **Single Machine Deployment** — Mac Mini M4 Pro เครื่องเดียวรันได้ทั้งระบบ
- **Low Operational Cost** — ไม่มี API call charges, ไม่ต้องมี DevOps team ใหญ่

---

## 2. ⚠️ Gap Analysis — สิ่งที่ยังขาดสำหรับ SME + Commercial

### 🔴 Critical Gaps (ต้องมีก่อนปล่อย Community)

| Gap | ปัญหา | แนวทาง |
|:--|:--|:--|
| **Centralized Auth** | แต่ละ component ใช้ auth แยกกัน | ✅ ตัดสินใจแล้ว: ใช้ Zitadel (Yggdrasil) |
| **All-in-One Docker Compose** | ยังแยก stack กับ Heimdall/Bifrost | สร้าง unified `docker-compose.yml` |
| **Backup/Restore** | ไม่มีระบบ backup อัตโนมัติ | เพิ่ม backup CLI + cron |
| **Bifrost ยังไม่เสร็จ** | Agent Runtime เป็น core value | Prioritize MVP |
| **Setup Wizard** | ต้อง config `.env` หลายไฟล์ | สร้าง CLI + Web wizard |

### 🟡 Important Gaps (ควรมีก่อน Enterprise)

| Gap | เหตุผล |
|:--|:--|
| **Audit Log** | Enterprise ต้องการ audit trail สำหรับ compliance |
| **Rate Limiting / Quota** | ป้องกัน abuse, จำกัด usage per user/team |
| **SSO Integration** | Enterprise ใช้ LDAP/SAML/OIDC เป็นหลัก |
| **HA / Clustering** | บริษัทขนาดกลางขึ้นไปต้องการ high availability |
| **Usage Analytics Dashboard** | Billing, cost tracking, usage reporting |

---

## 3. 🗺️ Roadmap — Community → Enterprise

### Phase 1: Community Foundation (v1.0) 🎯
> เป้าหมาย: **ใครก็ได้โหลดไป run ได้ใน 15 นาที**

```
✅ มีอยู่แล้ว (จาก Mimir)              🆕 ต้องเพิ่ม
├── Multi-Tenant IAM (JWT+RBAC)       ├── Unified docker-compose (all components)
├── Admin Dashboard (Next.js)          ├── Shared Auth (Zitadel)
├── Docker Compose (partial)           ├── One-command install script
├── RAG Pipeline + Ingestion           ├── Backup/Restore CLI
├── Agent Eval + QC System             ├── License selection + NOTICE
└── Real-time Monitoring               └── Asgard Quick Start Guide
```

**Hardware Tiers สำหรับ SME:**

#### 🍎 Apple Silicon Track (MLX / llama.cpp / Ollama)

| Tier | Hardware | รองรับ | ราคาเครื่อง |
|:--|:--|:--|:--|
| **Starter** | Mac Mini M4 (16GB) | 1-5 users, 7B model | ~฿25,000 |
| **Standard** | Mac Mini M4 Pro (36GB) | 10-20 users, 14B model | ~฿60,000 |
| **Pro** | Mac Mini M4 Pro (64GB) | 20-50 users, 30B+ model | ~฿80,000 |
| **Max** | Mac Studio M4 Ultra (192GB) | 50-200 users, 70B+ model | ~฿180,000 |

#### 🟢 NVIDIA Track (vLLM + CUDA)

| Tier | Hardware | รองรับ | ราคาเครื่อง |
|:--|:--|:--|:--|
| **DGX Spark** | NVIDIA DGX Spark (128GB) | 50-200 users, 70B+ model | ~฿350,000 |
| **DGX Station** | NVIDIA DGX Station (A100/H100) | 200+ users, multi-model | ~฿2,000,000+ |

### Phase 2: Community Growth (v1.x)
> เป้าหมาย: **Community เริ่มใช้งานจริง + รองรับ NVIDIA**

- [ ] Bifrost MVP (Agent Runtime — ReAct loop, tool execution)
- [ ] 🟢 Heimdall: vLLM backend — CUDA support สำหรับ NVIDIA DGX Spark
- [ ] 🟢 Heimdall: Intelligent Router — Auto-route ตาม hardware (MLX vs vLLM)
- [ ] 🧠 Mimir: Visual Workflow Builder (ReactFlow) — **moved from Enterprise**
- [ ] 🧠 Mimir: A2A Server (Agent-to-Agent protocol)
- [ ] ⚡ Bifrost: A2A Client
- [ ] adk-guardrail integration (PII redaction — Healthcare)
- [ ] Agent Template Marketplace
- [ ] Plugin system สำหรับ custom tools
- [ ] Documentation site
- [ ] Knowledge Graph (Neo4j — Mimir Sprint 11)
- [ ] Multi-Agent System (Mimir Sprint 12)

### Phase 3: Enterprise Edition (v2.0) 💰
> เป้าหมาย: **ขาย license ให้บริษัท**

```
Enterprise-Only Features:
├── 🔐 SSO (SAML, OIDC, LDAP) via Zitadel
├── 👥 Advanced RBAC (org → team → project)
├── 📊 Usage Analytics + Cost Dashboard
├── 📋 Audit Log + Compliance Reports
├── 🔄 HA Clustering (multi-node)
├── 🆘 Priority Support + SLA
├── 🏷️ White-Label / Custom Branding
└── 🤖 Advanced Agent Features
    ├── Agent Collaboration (multi-agent)
    └── Enterprise RAG (advanced chunking, PII redaction)
```

---

## 4. 📊 Licensing Strategy

> ✅ **ตัดสินใจแล้ว: AGPL-3.0** — Dual License (AGPL Community + Commercial Enterprise)

| Option | License | ข้อดี | ข้อเสีย | ตัวอย่าง |
|:--|:--|:--|:--|:--|
| **✅ เลือก** | AGPL-3.0 | Strong copyleft ป้องกัน cloud reselling | บาง SME กลัว GPL | GitLab, Mattermost |
| B | BSL 1.1 | ปกป้อง commercial แต่ยังเปิดให้ใช้ฟรี | ไม่ถือเป็น "true OSS" | Sentry, CockroachDB |
| C | Apache 2.0 + CLA | เปิดกว้างที่สุด | ป้องกัน competitor ยากกว่า | Kubernetes, TensorFlow |

---

## 5. 🎯 Competitive Positioning

| Feature | Asgard | Open WebUI | AnythingLLM | Dify |
|:--|:--|:--|:--|:--|
| LLM Gateway | ✅ Heimdall (Rust) | ❌ | ❌ | ❌ |
| RAG Pipeline | ✅ Mimir | ⚠️ Basic | ✅ | ✅ |
| Agent Runtime | ✅ Bifrost | ❌ | ⚠️ Basic | ✅ |
| Computer Use | ✅ Fenrir | ❌ | ❌ | ❌ |
| Apple Silicon | ✅ Native MLX | ❌ | ❌ | ❌ |
| NVIDIA GPU | 🟢 vLLM | ❌ | ❌ | ⚠️ Cloud |
| Self-Hosted | ✅ 100% | ✅ | ✅ | ⚠️ |
| Enterprise Ready | 🚧 | ❌ | ⚠️ | ✅ |

**USP (Unique Selling Point):**
> "แพลตฟอร์ม AI ครบวงจร self-hosted สำหรับทั้ง Apple Silicon และ NVIDIA GPU — ตั้งแต่ LLM Gateway จนถึง Computer Use Agent ข้อมูลไม่เคยออกจากบริษัท"

---

*📅 Last updated: March 2026*
