# 🧠 MCP Architecture Review by Antigravity Skills Panel

ตามที่คุณต้องการ นี่คือการรีวิวแผนการทำ **"MCP Dual Layer & Hybrid RAG" (Sprint 31-34)** อย่างละเอียด โดยใช้มุมมองและข้อกำหนดจาก 9 Skills ที่ฝังอยู่ใน `.agent/skills/` ของ Project Mimir ครับ:

---

### 🦀 1. Rust Backend Patterns
* **Feedback:** แผนการฝัง `model-context-protocol` crate เข้าไปใน Axum (Mimir) เป็นแผนที่ยอดเยี่ยมด้าน Memory แต่มีความเสี่ยงร้ายแรงเรื่อง **"Cross-Tenant Data Leakage"** 
* **Action Required:** มาตรฐานเราบังคับว่าทุก Route ต้องผ่าน `tenant_auth_middleware` ดังนั้น ท่อ SSE ของ MCP (`/mcp/sse`) ต้องเช็ค `X-Tenant-Id` ตั้งแต่จังหวะ Handshake และ **ต้อง** ส่ง `tenant_id` แนบเข้าไปใน Context ของ Tool `search_knowledge` เสมอ ห้ามให้ LLM เป็นคนกำหนด `tenant_id` เองเด็ดขาด (ป้องกันการแฮ็กข้ามข้อมูล)

### 📈 2. Agile Scrum Master
* **Feedback:** แผน Sprint 31-34 ถูกสับย่อยได้ดี (Minimizing Blast Radius) แต่ผิดกฎเรื่อง "Backlog Management" เล็กน้อย
* **Action Required:** ก่อนจะเริ่มเขียนโค้ด Sprint 31 เราต้องเอาหัวข้อใน `task.md` ไปเปิดเป็น **GitHub Issues** ก่อน เพื่อให้มี 1 Issue = 1 PR ตามกฎ Traceability และตามกฎประเมินบริบท (1 Sprint = 1 Conversation) ควรเตรียมตัว **ปิดแชทนี้และเปิด Conversation ใหม่** เพื่อเริ่มเขียนโค้ด Sprint 31 สดๆ ครับ

### 📑 3. ISO 29110 Documentation
* **Feedback:** อัปเดต `PM_01_Project_Plan.md` ไปแล้วถือว่าดีมาก แต่งาน Design ระดับสถาปัตยกรรม (Architecture) ขาดหายไป
* **Action Required:** ใน Sprint 31 ต้องเริ่มจากการเข้าไปแก้ไฟล์ `SI_02_Software_Design_Document.md` ก่อน เพื่อวาด Sequence Diagram ของท่อ MCP (Asgard -> Go Sidecar -> Zitadel) เก็บไว้เป็นหลักฐานการออกแบบ

### 🧪 4. TDD & Testing Workflow
* **Feedback:** เมื่อเราย้ายทุกอย่างไปอยู่บน MCP การทำ Unit Test แบบเรียก Function ปกติจะพังหมด (เพราะมันกลายเป็น JSON-RPC ข้าม Network)
* **Action Required:** ต้องใช้ Test-Driven Development (TDD) ในการเขียน **Mock MCP Server** ด้วย Rust/Python เพื่อทดสอบว่า Agent ใน Bifrost โยน Parameter ได้ถูกต้องตาม Schema ค่อยเริ่มเขียนของจริง

### 🎨 5. Next.js Frontend Patterns & UX Designer
* **Feedback:** แผนของ Hybrid RAG ระบุถึง "Ensemble Playground" แต่ยังเห็นภาพไม่ชัดว่าผู้ใช้จะรู้ได้ไงว่า AI เอาข้อมูลมาจาก Vector หรือ Graph
* **Action Required:** แนะนำให้ใช้คอมโพเนนต์แบบ "Source Badge" ใน Next.js แยกสีตามแหล่งที่มา (เช่น เขียว=Tree, ม่วง=Graph, ฟ้า=Vector) และต้องมีหน้า Setting UI ที่ให้ User เลื่อน Slider เปอร์เซ็นต์ (Weighting) ระหว่าง Semantic Search กับ Graph Search ได้

### 🕵️ 6. Code Review
* **Feedback:** การทำ "Universal Go Sidecar" สำหรับหุ้ม OpenEMR (PHP) มีความเสี่ยงเรื่อง Error Handling
* **Action Required:** ถ้า PHP พ่น 500 Internal Error ตัว Go Sidecar ต้องจับ Error นั้นมาครอบด้วยฟอร์แมต `JSON-RPC Error Code` (เช่น รหัส -32603) แล้วค่อยพ่นกลับไปหา LLM เพื่อให้ Agent รู้ตัวว่าระบบพังจะได้ไม่ Hallucinate 

### 📚 7. PageIndex Integration
* **Feedback:** การแก้ `tree_search` จาก Sequential เป็น Async Parallel จะทำให้เร็วขึ้นมาก แต่ต้องระวังสูญเสียข้อมูล Hierarchical Hierarchy
* **Action Required:** ใน Chunk ที่โผล่มาจาก PageIndex ต้องดึง "Parent Nodes" ผสมเข้าไปด้วยเสมอ เพื่อให้ Agent รับรู้ถึงโครงสร้างหน้าเว็บ (Contextual Path) ไม่ใช่แค่ได้ Text โดดๆ

---

### 🎯 บทสรุป 
สถาปัตยกรรมสอบผ่านทุกเกณฑ์ (Approved) แข็งแกร่ง สเกลได้ และป้องกันปัญหา Memory บวมได้ดีเยี่ยมครับ! สิ่งที่ต้องระวังที่สุดมีเพียงเรื่อง **"การแอบส่ง `X-Tenant-Id` ผ่านทะลุ MCP Protocol อย่างปลอดภัย"** เท่านั้นครับ
