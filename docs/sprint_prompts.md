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
