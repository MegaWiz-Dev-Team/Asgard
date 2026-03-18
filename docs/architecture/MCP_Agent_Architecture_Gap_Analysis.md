# Asgard Ecosystem: MCP Architecture Gap Analysis

ตามแนวคิด **"Dual Layer Architecture"** (REST API สำหรับ Frontend UI และ MCP สำหรับ Agent-to-Agent) เพื่อให้ข้อกำหนดที่ว่า *"Agent แต่ละตัวต้องดูแลและใช้งาน API ของตัวเองเท่านั้น"* เป็นจริงอย่างสมบูรณ์แบบ นี่คือ **Gap Analysis อย่างละเอียด** สำหรับการปรับโครงสร้างทั้งระบบครับ:

---

## 🏗️ 1. สถาปัตยกรรมที่ตั้งเป้าไว้ (Target Architecture)

1. **Bifrost (Orchestrator Node):** ทำตัวเป็นแค่ **MCP Client** และ ADK Router จะไม่มีการเขียนโค้ด Business Logic ใดๆ ของ Agent อื่นไว้ใน Bifrost อีกต่อไป โค้ดในโฟลเดอร์ `bifrost/tools/*` ทั้งหมดจะต้องถูกลบทิ้ง!
2. **The 12 Sub-Services (Worker Nodes):** บริการทั้ง 12 ตัว (Mimir, Eir, Fenrir, Yggdrasil, etc.) จะต้องเปิดพอร์ต **SSE (Server-Sent Events) สำหรับ MCP Server** เพิ่มขึ้นมา 1 พอร์ตควบคู่กับ REST API เดิม
3. **The Bridge (ADK ↔ MCP):** เมื่อ Bifrost บูทระบบ มันจะวิ่งไปต่อท่อ SSE กับทั้ง 12 Services เพื่อขอดึงรายชื่อ Tools (Discovery) แล้วเอา Tools เหล่านั้นไปยัดใส่ `tools=[...]` ของตัวแปร `LlmAgent` ใน ADK อัตโนมัติ

---

## 🚨 2. Gap Analysis (ช่องโหว่ทางเทคนิคที่ต้องแก้)

### 🔴 GAP 1: ขาดแคลน MCP Servers (ฝั่ง Worker Nodes)
* **สถานะปัจจุบัน:** ตอนนี้มีแค่ `Fenrir` ตัวเดียวที่แอบมีการเขียนเปิดพอร์ต MCP ทิ้งไว้ (แต่พังอยู่ตาม Log) ส่วน Mimir, Yggdrasil, Eir, Vardr ฯลฯ มีแต่ REST API ทั่วไป
* **สิ่งที่ต้องทำ (The Gap):**
  - ต้องสร้าง **MCP Server Sidecar หรือ SDK Embed** เข้าไปในทุกๆ Repository
  - **Mimir (Rust):** พัฒนา MCP Server ด้วย Rust เพื่อ Expose ความสามารถ `search_knowledge`, `list_sources`
  - **Forseti (Python):** พัฒนา MCP Server เพื่อ Expose `run_e2e_tests`, `get_test_report`
  - **Yggdrasil (Go/Zitadel):** อาจต้องเขียนแรปเปอร์เล็กๆ ด้วย Go/Python เป็น MCP ที่ Expose `validate_token`, `get_user_roles`
  - **Eir (OpenEMR):** ให้ `eir-gateway` (FastAPI) เป็นตัวเปิดพอร์ต MCP Expose `get_patient_records`

### 🔴 GAP 2: Bifrost ขาด MCP ↔ ADK Bridge (ฝั่ง Client Node)
* **สถานะปัจจุบัน:** ใน `bifrost/main.py` โค้ดสามารถต่อ MCP Client ไปหา Fenrir ได้ (`_mcp_manager.add_server`) และโหลด Tool เข้า `registry` รุ่นเก่าได้ **แต่** ไม่ได้เอา Tool นั้นไปให้เฟรมเวิร์กใหม่ (`google-adk`) ใช้งาน! 
* **สิ่งที่ต้องทำ (The Gap):**
  - ต้องพัฒนา **ADK Tool Adapter** ที่แปลง `MCP Tool` (JSON RPC) ให้กลายเป็น `Python Callable` ที่มี Pydantic Schema แบบที่ `google-adk` ต้องการ
  - เมื่อ `bifrost/agents/<ชื่อ service>/agent.py` ทำงาน มันต้องดึง Tools เฉพาะที่มาจาก MCP Server ของตัวเองมาใส่ใน `LlmAgent(tools=...)` ตัวเองเท่านั้น ห้ามเอา Tool ของคนอื่นมาปนเด็ดขาด (Strict Isolation)

### 🟡 GAP 3: Context & Authentication Propagation 
* **สถานะปัจจุบัน:** MCP Protocol มาตรฐานไม่มีฟอร์แมตตายตัวในการส่ง Header `X-Tenant-ID` หรือ `Authorization: Bearer` ทุกครั้งที่เรียก Tool
* **สิ่งที่ต้องทำ (The Gap):**
  - ตกลงทำ **Custom Protocol Extension** ใน MCP รึเปล่า? หรือจะฝัง `tenant_id` ลงไปในตัวแปร Input ของทุกๆ Tool Schema กึ่งบังคับให้ LLM ส่งมาด้วย (ซึ่งไม่ปลอดภัย เพราะ LLM อาจเดามั่วได้)
  - **Best Practice:** Bifrost (Client) ควรสอดแทรก `Headers` หรือ `MetaContext` ห้อยเข้าไปใน MCP Request Payload อัตโนมัติทุกครั้งที่รัน Tool 

---

## 🏃 3. Implementation Roadmap (แผนการลงมือทำ)

หากต้องการลุยสถาปัตยกรรมระดับนี้ เราควรทยอยทำทีละระบบเพื่อป้องกันความเสี่ยง (Blast Radius):

**Phase 1: The Foundation (Bifrost + Mimir)**
* สร้าง MCP Server ฝั่ง Mimir (Rust) ให้สมบูรณ์แบบ
* แก้โค้ด `bifrost` ให้ทำ MCP Client ↔ ADK Adapter
* ทดสอบลบ `bifrost/tools/mimir.py` ทิ้ง และให้ Agent Mimir ใน ADK ทำงานได้เหมือนเดิม 100% ผ่าน MCP ล้วนๆ

**Phase 2: The Medical Expansion (Eir + Fenrir)**
* สร้าง/ซ่อม MCP Server ฝั่ง `eir-gateway` (FastAPI) และ `fenrir` (Browser Automation)
* ผสานเข้ากับระบบ ADK ใน Bifrost เพื่อให้ Asgard สั่งการรักษาโรค/หาข้อมูลยาได้

**Phase 3: The Platform Control (Yggdrasil + Forseti + Vardr)**
* ขยาย MCP ให้ครบ 12 แกนหลัก เพื่อให้ Asgard เป็น Orchestrator ที่มองเห็นจักรวาลทั้งหมดโดยที่โค้ดไม่มีการ Coupling กันอีกเลย
