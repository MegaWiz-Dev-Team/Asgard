# Asgard Ecosystem: Master Master Sprint Plan (Sprint 31-34)

แผนยุทธศาสตร์ภาพรวมสำหรับผลักดันทั้ง 12 โปรเจคใน Asgard Ecosystem ให้ก้าวสู่ **"Hybrid RAG + MCP Dual Layer Architecture"** อย่างสมบูรณ์แบบ (อัปเดตเพิ่มเติมตาม **Action Required** จากทีมตรวจสอบ 9 สายทักษะ):

---

### 🛡️ Global Rules (กฎเหล็กประจำทุก Sprint)
- **[Action - Test-Driven Development (TDD)]:** การพัฒนาฟีเจอร์ใหม่ทั้งหมดในทุก Sprint จะต้องทำแบบ TDD แบบ 100% (เขียน Test ให้ Fail ก่อนเริ่มเขียนโค้ดเสมอ) เพื่อรับประกันความเสถียร
- **[Action - Testing Workflow]:** ทุกครั้งที่ปิด Sprint จะต้องมีการรัน **Unit Test, UI Test, และ E2E Test** และต้องบังคับส่ง (Push) ผลลัพธ์ทั้งหมดเข้าไปบันทึกเป็นประวัติไว้ในฐานข้อมูลของ **Forseti** เสมอ เพื่อรักษามาตรฐานความถูกต้องของทั้ง Platform
- **[Action - Security Review]:** โค้ดที่เขียนเสร็จในทุกๆ Sprint จะต้องถูกส่งเข้าสแกนช่องโหว่ (SAST/DAST/Container) ผ่านระบบของ **Huginn** (Semgrep, Trivy, ZAP) ให้ผ่านการประเมิน Security ก่อนขึ้น Production
- **[Action - Release & ISO Closing]:** เมื่อจบ Sprint ทุกครั้ง จะต้องมีการอัปเดตเอกสาร **ISO 29110 (เช่น SI-02, PM-02)** ให้สอดคล้องกับฟีเจอร์ปัจจุบัน พร้อมทั้งต้องดำเนินการ **Tag Release Version ใหม่ (เช่น v1.2.x)** บน GitHub ทุกครั้งที่ปิดรอบการทำงาน

---

### 🚀 Sprint 31: The Foundation (Mimir Hybrid RAG & MCP Server)
เป้าหมาย: สร้างเอนจินค้นหาแบบผสมผสาน (Hybrid RAG) และเปิดประตู MCP ฝั่ง Data Layer ให้พร้อมที่สุด 

- **[ISO Documentation & TDD]**
  - **SI-02 & SI-04 Design:** วาด Sequence Diagram การทำงานของ MCP ข้าม Service และเตรียม Test Script (JSON-RPC) ลงเอกสาร ISO
  - **Mock MCP Server:** เขียน Rust TDD Mock Server ก่อนเริ่มของจริง เพื่อเช็คว่า LLM ส่ง Tool Parameters มาถูก Schema หรือไม่
- **[Project Mimir - Backend]**
  - Implement **Ensemble Retrieval Engine**: ค้นหาพร้อมกัน 3 แหล่ง (True Vector + Parallel PageIndex Tree + Neo4j Graph) + Reranker
  - **[Action - PageIndex]:** นำข้อมูล Parent Nodes (Hierarchy Context) ปะติดเข้าไปในชุดข้อมูล Chunk ที่ดึงมาจาก Tree เสมอ
  - ปลูกถ่าย **Rust MCP Server (SSE)** เพื่อเปิด Tools (`search_knowledge`) 
  - **[Action - Security]:** บังคับใช้ `tenant_auth_middleware` กับท่อ SSE (`/mcp/sse`) แบบเข้มงวด และดักจับ `X-Tenant-Id` ยัดลงไปใน MetaContext ของทุก Tool Request 
- **[Project Mimir - Frontend]**
  - เพิ่มหน้า **RAG Ensemble Playground** ใน Mimir Dashboard 
  - **[Action - UX]:** ออกแบบ Source Badge แยกสีชัดเจน (ฟ้า=Vector, ม่วง=Graph, เขียว=Tree) และเพิ่ม Slider ให้ User ปรับค่าน้ำหนัก (Weight) ให้แต่ละแหล่งข้อมูลได้เอง

---

### 🧠 Sprint 32: The Orchestrator Upgrade (Asgard/Bifrost)
เป้าหมาย: ผ่าตัดระบบ Agent ทั้งหมดให้เป็น Pure ADK-MCP และรองรับผู้ใช้งานหลาย Tenant ได้อย่างปลอดภัย

- **[Agile Scrum Process]**
  - สับย่อยงานอัปเกรด Bifrost/Asgard ทั้งหมดเข้า **GitHub Issues** เพื่อให้ติดตามได้แบบ 1 Issue = 1 PR
- **[Project Bifrost]**
  - **The Great Purge:** ลบโค้ดตระกูล Tool แบบเก่าทิ้งทั้งหมด
  - **ADK-MCP Adapter:** พัฒนาตัวเชื่อม (Adapter) ที่แปลงสัญญาณ JSON-RPC ของ Tool ยัดใส่ `LlmAgent` ใน ADK อัตโนมัติ
  - **Dynamic Context Isolation:** แพตช์ระบบ MCP Request Meta ให้ส่ง `X-Tenant-ID` ผ่าน Session User เสมอ
  - **Testing:** ทดสอบให้ตัวแทน Agent วิ่งไปดึงข้อมูลด้วยไฮบริดค้นหา ผ่านท่อ MCP ได้สำเร็จ
- **[Project Muninn — ✅ Completed]**
  - **Review Mode:** เพิ่ม `FIX_MODE=review` ให้ AI propose fix แล้วรอ approve ก่อนสร้าง PR
  - **Configurable LLM:** `LLM_PROVIDER`, `GEMINI_MODEL=gemini-2.5-flash`, `LLM_TEMPERATURE=0.1`
  - **Odin API:** endpoints `approve`/`reject`/`config` สำหรับ dashboard
  - **TDD:** 76 tests all passing (17 ใหม่)
- **[Project Odin — ✅ Created]**
  - **Commercial Dashboard:** Unified Security Command Center (แยก repo private)
  - **Open-Core Model:** Community OSS agents + Commercial Odin dashboard
  - **3 UX Modes:** Dashboard (review), Auto-Pilot (autonomous), Chat-Driven (MCP)
- **[Forseti — 📋 Planned]**
  - เพิ่ม test types: Unit, Integration, E2E, Security Regression, Contract, Performance

---

### 🏥 Sprint 33: Ecosystem Gateways (Auth & Medical Expansion)
เป้าหมาย: ขยายการเชื่อมต่อปลั๊กอินไปยังบริการความปลอดภัยและการแพทย์ (Zitadel & OpenEMR) 

- **[Global Tooling - Error Handling]**
  - **[Action - Code Review]:** เขียน `asgard-mcp-sidecar` (Go) ให้ดักจับ HTTP 500 Error จาก Service เก่า (เช่น PHP) และแปลงฟอร์แมตกลับเป็นมาตรฐาน **JSON-RPC Error Code -32603** คืนให้ LLM ป้องกันบอทเพ้อเจ้อเมื่อระบบล่ม
- **[Project Yggdrasil & Eir]**
  - สร้าง `yggdrasil-mcp` (Go Sidecar) เปิด Tools: `validate_token`, `get_user_roles`
  - จับ `asgard-mcp-sidecar` หุ้ม `eir-gateway` (PHP) เปิด Tools: `get_patient_medical_history`, `book_appointment`
- **[Project Bifrost]**
  - จ่าย Tools ด้านสุขภาพและสิทธิใช้งานให้ Eir Agent และ Yggdrasil Agent

---

### ⚙️ Sprint 34: Platform Automation (Testing, Browsing & Security)
เป้าหมาย: เชื่อมต่อ 8 หน่วยรบย่อยที่เหลือให้ครบจบในลูปเดียว

- **[Project Fenrir & Forseti]**
  - ซ่อม Python SSE MCP เดิมที่พังอยู่ และ Expose Browser Tools
  - พัฒนา Python MCP ฝังเข้าไป Expose Automated Testing Tools
- **[Project Ratatoskr, Huginn, Muninn]**
  - ฝัง `model-context-protocol` Rust crate Expose Web Crawling / Security Scanners Tools
- **[Project Heimdall]**
  - เอา Go Sidecar ครอบ Python/MLX Inference Node เปิดแจ้งสถานะ GPU โดยไม่เปลืองแรม
