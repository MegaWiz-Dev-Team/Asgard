# Asgard Ecosystem — Sprint Execution Prompts
> Copy-paste ทีละ Sprint แล้วเปิด Conversation ใหม่ส่งได้เลย

---

## 🚀 Sprint 31: Mimir Hybrid RAG & MCP Server

```
เริ่ม Sprint 31: Mimir Hybrid RAG & MCP Server Foundation

กฎเหล็กที่ต้องปฏิบัติตลอด Sprint:
1. ทำ TDD 100% (เขียน Test ให้ Fail ก่อนเขียนโค้ดเสมอ)
2. เมื่อจบ Sprint → รัน Unit/E2E Test + push ผลเข้า Forseti
3. ส่งโค้ดสแกน Huginn (Semgrep/Trivy) ก่อนปิด Sprint
4. อัปเดต ISO docs (SI-02, PM-02, SI-04) + Tag Release Version

เอกสารอ้างอิง:
- Master Sprint Plan: Asgard/docs/iso_29110/pm/PM_01_Ecosystem_Roadmap_S31_S34.md
- Architecture: Asgard/docs/architecture/MCP_Ecosystem_Implementation_Plan.md
- Hybrid RAG Design: Mimir/docs/02_architecture_and_integration/02_14_Hybrid_RAG_Sprint31_Design.md
- Gap Analysis: Asgard/docs/architecture/MCP_Agent_Architecture_Gap_Analysis.md

Backend (Mimir Rust — ro-ai-bridge):
1. แก้ vector_search ให้ query Qdrant จริง (แทน SQL fallback)
2. แก้ tree_search ให้ทำงาน parallel + ดึง parent context
3. เพิ่ม Neo4j graph_search integration
4. สร้าง Ensemble Retrieval Engine (parallel 3-source + reranker)
5. สร้าง Axum SSE MCP transport (/api/v1/mcp/sse + /message)
6. บังคับ X-Tenant-Id ผ่าน tenant_auth_middleware บน SSE endpoint

Frontend (Mimir Dashboard — Next.js):
7. เพิ่มหน้า RAG Ensemble Playground
8. Source Badge component (Vector=ฟ้า, Graph=ม่วง, Tree=เขียว)
9. Weight Slider สำหรับปรับน้ำหนัก retrieval source
10. Graph ingestion status indicator

เริ่มจาก Backend ข้อ 1 ก่อนเลยครับ ทำ TDD
```

---

## 🧠 Sprint 32: Bifrost/Asgard MCP Orchestrator

```
เริ่ม Sprint 32: Bifrost/Asgard MCP Orchestrator Upgrade

กฎเหล็กที่ต้องปฏิบัติตลอด Sprint:
1. ทำ TDD 100% (เขียน Test ให้ Fail ก่อนเขียนโค้ดเสมอ)
2. เมื่อจบ Sprint → รัน Unit/E2E Test + push ผลเข้า Forseti
3. ส่งโค้ดสแกน Huginn (Semgrep/Trivy) ก่อนปิด Sprint
4. อัปเดต ISO docs (SI-02, PM-02, SI-04) + Tag Release Version

เอกสารอ้างอิง:
- Master Sprint Plan: Asgard/docs/iso_29110/pm/PM_01_Ecosystem_Roadmap_S31_S34.md
- Bifrost Gap Analysis: Bifrost/docs/Bifrost_Gap_Analysis_Sprint32.md
- MCP Implementation Plan: Asgard/docs/architecture/MCP_Ecosystem_Implementation_Plan.md

Pre-requisite: Sprint 31 เสร็จแล้ว (Mimir MCP Server ต้องรันได้)

งานหลัก (Bifrost — Python):
1. สร้าง GitHub Issues สำหรับทุก task (1 Issue = 1 PR)
2. สร้าง bifrost/core/mcp_adapter.py (MCP JSON-RPC → ADK callable bridge)
3. Auto-discover tools จาก Mimir MCP server ตอน startup
4. Implement Dynamic X-Tenant-ID injection ผ่าน ADK session context
5. ลบ legacy bifrost/tools/mimir.py
6. E2E test: Asgard → Mimir Agent → MCP → Hybrid Search → Response

เริ่มจากสร้าง GitHub Issues ก่อน แล้วทำ TDD ข้อ 2 เลยครับ
```

---

## 🏥 Sprint 33: Ecosystem Gateways (Auth & Medical)

```
เริ่ม Sprint 33: Ecosystem Gateways — Yggdrasil & Eir MCP Sidecars

กฎเหล็กที่ต้องปฏิบัติตลอด Sprint:
1. ทำ TDD 100% (เขียน Test ให้ Fail ก่อนเขียนโค้ดเสมอ)
2. เมื่อจบ Sprint → รัน Unit/E2E Test + push ผลเข้า Forseti
3. ส่งโค้ดสแกน Huginn (Semgrep/Trivy) ก่อนปิด Sprint
4. อัปเดต ISO docs (SI-02, PM-02, SI-04) + Tag Release Version

เอกสารอ้างอิง:
- Master Sprint Plan: Asgard/docs/iso_29110/pm/PM_01_Ecosystem_Roadmap_S31_S34.md
- MCP Implementation Plan: Asgard/docs/architecture/MCP_Ecosystem_Implementation_Plan.md
- Skill Review: Asgard/docs/architecture/MCP_Architecture_Skill_Review.md

Pre-requisite: Sprint 31-32 เสร็จแล้ว (Mimir MCP + Bifrost Adapter ทำงานได้)

งานหลัก:
1. Hermóðr (Rust MCP Sidecar, `MegaWiz-Dev-Team/Hermodr`) — universal proxy สำหรับหุ้ม REST
2. Implement JSON-RPC error wrapping (HTTP 500 → code -32603) ป้องกัน LLM hallucinate
3. สร้าง yggdrasil-mcp sidecar (Go) → เปิด tools: validate_token, get_user_roles
4. Deploy sidecar หุ้ม Eir/OpenEMR → เปิด tools: get_patient_medical_history, book_appointment
5. Wire MCP tools ใหม่เข้า Bifrost agents (Eir Agent + Yggdrasil Agent)
6. E2E test: Asgard → Eir Agent → MCP Sidecar → OpenEMR FHIR

เริ่มจาก scaffold Go project ข้อ 1 ก่อนเลยครับ
```

---

## ⚙️ Sprint 34: Platform Automation (8 Remaining Services)

```
เริ่ม Sprint 34: Platform Automation — MCP for Fenrir, Forseti, Huginn, Muninn, Ratatoskr, Heimdall, Vardr, PageIndex

กฎเหล็กที่ต้องปฏิบัติตลอด Sprint:
1. ทำ TDD 100% (เขียน Test ให้ Fail ก่อนเขียนโค้ดเสมอ)
2. เมื่อจบ Sprint → รัน Unit/E2E Test + push ผลเข้า Forseti
3. ส่งโค้ดสแกน Huginn (Semgrep/Trivy) ก่อนปิด Sprint
4. อัปเดต ISO docs (SI-02, PM-02, SI-04) + Tag Release Version

เอกสารอ้างอิง:
- Master Sprint Plan: Asgard/docs/iso_29110/pm/PM_01_Ecosystem_Roadmap_S31_S34.md
- MCP Implementation Plan: Asgard/docs/architecture/MCP_Ecosystem_Implementation_Plan.md

Pre-requisite: Sprint 31-33 เสร็จแล้ว (Mimir, Bifrost, Yggdrasil, Eir MCP ทำงานได้)

งานหลัก:
1. Fenrir: ซ่อม Python SSE MCP server + expose tools: navigate_browser, click_element
2. Forseti: Python MCP server + expose tools: run_test_suite, get_test_report
3. Ratatoskr: Rust MCP (model-context-protocol crate) + expose: crawl_url
4. Huginn: Rust/Go MCP + expose: scan_vulnerability
5. Muninn: Rust/Go MCP + expose: generate_code_fix
6. Heimdall: Go sidecar ครอบ Python/MLX + expose: get_gpu_vram_usage, switch_active_model
7. Register MCP servers ทั้งหมดใน Bifrost initialization manifest
8. Final E2E test ผ่าน Dashboard UI ครบทั้ง 12 services

เริ่มจาก Fenrir ข้อ 1 ก่อนเลยครับ (ซ่อม SSE ที่พัง) ทำ TDD
```

---

## 🧠 Sprint 35: Agent Intelligence Foundation (Skills, Memory, Context)

```
เริ่ม Sprint 35: Agent Intelligence Foundation — Skills, Memory, Context Engineering

Reference Research:
- DeerFlow (ByteDance): https://github.com/bytedance/deer-flow
- HiClaw (Alibaba): https://github.com/alibaba/hiclaw

กฎเหล็กที่ต้องปฏิบัติตลอด Sprint:
1. ทำ TDD 100% (เขียน Test ให้ Fail ก่อนเขียนโค้ดเสมอ)
2. เมื่อจบ Sprint → รัน Unit/E2E Test + push ผลเข้า Forseti
3. ส่งโค้ดสแกน Huginn (Semgrep/Trivy) ก่อนปิด Sprint
4. อัปเดต ISO docs (SI-02, PM-02, SI-04) + Tag Release Version

เอกสารอ้างอิง:
- Master Sprint Plan: Asgard/docs/iso_29110/pm/PM_01_Ecosystem_Roadmap_S35_S36.md
- DeerFlow Architecture: https://github.com/bytedance/deer-flow/blob/main/backend/CLAUDE.md
- HiClaw Architecture: https://github.com/alibaba/hiclaw/blob/main/docs/architecture.md

Pre-requisite: Sprint 31-34 เสร็จแล้ว (MCP infrastructure ครบ 12 services)

งานหลัก:

Part A — Skills System (ต้นแบบ: DeerFlow):
1. สร้าง Asgard/skills/{public,custom}/ directory + SKILL.md format spec
2. เขียน built-in skills 5 ตัว: medical-research, patient-summary, iso-doc-generator, security-audit, deployment
3. สร้าง Bifrost skills_loader.py — scan, parse YAML frontmatter, progressive loading
4. Integrate skills เข้า agent system prompt (load เฉพาะ skill ที่เกี่ยวกับ task)

Part B — Long-Term Memory (ต้นแบบ: DeerFlow):
5. สร้าง Bifrost memory/ module — schema (facts, context, history, medical), updater (LLM extraction), store
6. Multi-tenant isolation — memory per tenant_id จัดเก็บผ่าน RustFS (S3-compatible, Rust-native — ตัวเดียวกับที่ Mimir ใช้อยู่)
7. Memory middleware — inject top 15 facts ใน system prompt, queue async extraction

Part C — Context Engineering (ต้นแบบ: DeerFlow):
8. สร้าง Bifrost context/ module — summarization middleware
9. Configurable triggers (token limit, message count)

Part D — Shared Storage (ใช้ RustFS ตัวเดิมของ Mimir แทน MinIO ใหม่):
10. ย้าย RustFS จาก Mimir docker-compose → Asgard docker-compose.yml เป็น shared service
11. สร้าง asgard-storage bucket: tasks/, skills/, memory/, artifacts/, knowledge/
12. สร้าง Bifrost storage.py — S3-compatible client wrapper (ใช้ endpoint เดียวกับ Mimir)
13. กำหนด Task Spec Format: meta.json + spec.md + progress/ + result.md

14. E2E test: skill loaded → agent uses skill → memory persists across sessions

เริ่มจากข้อ 1 ก่อนเลยครับ — สร้าง skills directory + format spec แล้วทำ TDD
```

---

## ⚔️ Sprint 36: Multi-Agent Orchestration (Odin)

```
เริ่ม Sprint 36: Multi-Agent Orchestration — Odin Coordinator, IM Channels, Sandbox

Reference Research:
- DeerFlow Sub-Agents: https://github.com/bytedance/deer-flow/blob/main/backend/CLAUDE.md
- HiClaw Manager-Workers: https://github.com/alibaba/hiclaw/blob/main/docs/architecture.md

กฎเหล็กที่ต้องปฏิบัติตลอด Sprint:
1. ทำ TDD 100% (เขียน Test ให้ Fail ก่อนเขียนโค้ดเสมอ)
2. เมื่อจบ Sprint → รัน Unit/E2E Test + push ผลเข้า Forseti
3. ส่งโค้ดสแกน Huginn (Semgrep/Trivy) ก่อนปิด Sprint
4. อัปเดต ISO docs (SI-02, PM-02, SI-04) + Tag Release Version

เอกสารอ้างอิง:
- Master Sprint Plan: Asgard/docs/iso_29110/pm/PM_01_Ecosystem_Roadmap_S35_S36.md
- DeerFlow Sub-Agent System: packages/harness/deerflow/subagents/
- HiClaw Security Model: docs/architecture.md → Security Model section

Pre-requisite: Sprint 35 เสร็จแล้ว (Skills, Memory, Context Engineering, RustFS shared storage ทำงานได้)

งานหลัก:

Part A — Odin Agent Coordinator (ต้นแบบ: DeerFlow Lead Agent + HiClaw Manager):
1. สร้าง Bifrost agents/odin/ module — coordinator, planner, registry, executor
2. Implement task decomposition — Odin วิเคราะห์ request → แตก sub-tasks
3. Sub-agent execution engine — max 3 concurrent, 15-min timeout
4. Register sub-agent types: general-purpose, researcher, coder, medical, devops
5. Integrate memory + skills + context engineering จาก Sprint 35

Part B — Per-Agent Credential Isolation (ต้นแบบ: HiClaw):
6. เพิ่ม consumer token endpoint ใน Yggdrasil: POST /api/v1/agents/token
7. Scoped tokens: agent_id, tenant_id, allowed_tools[], ttl
8. Sub-agents ผ่าน Yggdrasil proxy — ไม่เห็น credentials จริง

Part C — IM Channel Integration (ต้นแบบ: DeerFlow):
9. เพิ่ม channel modules ใน Ratatoskr: Telegram, Slack, LINE
10. Message bus + channel:chat → thread mapping
11. Commands: /new, /status, /models, /health, /help

Part D — Sandbox Execution (ต้นแบบ: DeerFlow):
12. เพิ่ม sandbox mode ใน Fenrir: Docker container per-task
13. Virtual filesystem + MCP tools: execute_sandbox_command, read/write_sandbox_file

14. E2E test: Odin decomposes task → spawns sub-agents → synthesizes output → via Telegram

เริ่มจากข้อ 1 ก่อนเลยครับ — scaffold Odin coordinator module แล้วทำ TDD
```

---

## 🚀 Sprint 37: Production Deployment (K3s + Helm + CI/CD)

```
เริ่ม Sprint 37: Production Deployment — K3s Cluster, Helm Charts, CI/CD Pipeline

กฎเหล็กที่ต้องปฏิบัติตลอด Sprint:
1. ทำ TDD 100% (เขียน Test ให้ Fail ก่อนเขียนโค้ดเสมอ)
2. เมื่อจบ Sprint → รัน Unit/E2E Test + push ผลเข้า Forseti
3. ส่งโค้ดสแกน Huginn (Semgrep/Trivy) ก่อนปิด Sprint
4. อัปเดต ISO docs (SI-02, PM-02, SI-04) + Tag Release Version

เอกสารอ้างอิง:
- Master Sprint Plan: Asgard/docs/iso_29110/pm/PM_01_Ecosystem_Roadmap_S35_S37.md
- Existing Dockerfiles: ทุก service มี Dockerfile อยู่แล้ว
- Asgard docker-compose.yml: Asgard/docker-compose.yml

Pre-requisite: Sprint 31-36 เสร็จแล้ว (Platform features ครบ, agents ทำงานได้)

งานหลัก:

Part A — K3s Cluster Setup:
1. ติดตั้ง K3s บน Mac Mini (single-node) พร้อม Traefik Ingress
2. สร้าง Asgard/k8s/ directory structure: namespaces/, deployments/, services/, configmaps/, secrets/
3. สร้าง namespace: asgard-platform, asgard-infra, asgard-monitoring
4. Migrate docker-compose services → K8s Deployment + Service manifests ทั้ง 14 services

Part B — Helm Charts:
5. สร้าง Asgard/charts/asgard/ Helm chart (umbrella chart)
6. Sub-charts: mimir, bifrost, heimdall, eir, fenrir, ratatoskr, huginn, muninn, mjolnir, forseti, odin, vardr, yggdrasil, hermodr
7. values.yaml: configurable replicas, resource limits, image tags, env vars
8. values-dev.yaml vs values-prod.yaml สำหรับแยก environment

Part C — CI/CD Pipeline (GitHub Actions):
9. สร้าง .github/workflows/build-and-push.yml — build Docker images → push to GitHub Container Registry (ghcr.io)
10. สร้าง .github/workflows/deploy.yml — auto-deploy to K3s via kubectl/helm on merge to main
11. สร้าง .github/workflows/integration-test.yml — run E2E tests post-deploy
12. Implement GitOps: ArgoCD หรือ Flux สำหรับ declarative deployment

Part D — Observability Stack:
13. Deploy Prometheus + Grafana บน K3s (kube-prometheus-stack Helm chart)
14. สร้าง Grafana dashboards สำหรับ: Heimdall GPU metrics, Mimir RAG latency, Bifrost agent throughput
15. Configure alerting rules: service down, high error rate, GPU memory > 90%

Part E — Security & Networking:
16. Setup cert-manager + Let's Encrypt สำหรับ TLS certificates
17. Network Policies: isolate asgard-infra namespace, restrict inter-service communication
18. Secrets management: migrate .env files → K8s Secrets (sealed-secrets หรือ external-secrets)

19. E2E test: full platform running on K3s → Forseti runs all test suites → Grafana dashboards populated

เริ่มจากข้อ 1 ก่อนเลยครับ — ติดตั้ง K3s แล้วทำ TDD
```

