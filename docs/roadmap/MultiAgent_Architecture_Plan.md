# Asgard Multi-Agent Ecosystem: Project Blueprint
**Version:** 2.0 — Updated 2026-04-10
**Vision:** Transforming Asgard into a comprehensive **Medical AI Agent ecosystem** for physicians — designed around real clinical workflows to reduce lookup time and improve treatment accuracy.

> [!NOTE]
> เอกสารนี้ออกแบบจากงานจริงของแพทย์ (Use-Case-First) ไม่ใช่เทคโนโลยี-First
> ทุก Agent, Protocol, และ Data Source ที่ปรากฏต้องตอบ Use Case อย่างน้อย 1 ข้อ มิเช่นนั้นไม่ควรมีอยู่ในแผน

---

## 🎯 1. Core Clinical Use Cases (ออกแบบจากงานจริงของหมอ)

ทุกสิ่งที่สร้างต้องตอบโจทย์ Use Cases เหล่านี้ ไม่ใช่สร้างเครื่องมือแล้วค่อยหาที่ใช้

| # | Use Case | ปัจจุบัน | เป้าหมาย | แหล่งข้อมูล | Trigger |
|---|----------|---------|----------|------------|---------|
| 1 | **Pre-Visit Summary** — สรุปประวัติก่อนตรวจ | 5-15 นาที/คนไข้ | < 30 วินาที | FHIR (Eir) | เปิดแฟ้มคนไข้ |
| 2 | **Drug Interaction Alert** — แจ้งเตือนยาตีกัน | เปิดคู่มือเอง | Real-time | PrimeKG + FHIR | สั่งยาใหม่ |
| 3 | **Differential Diagnosis** — เสนอ DD จากอาการ | 10-30 นาที ค้นตำรา | 1-2 นาที | PrimeKG + PubMed | บันทึก Dx |
| 4 | **Evidence Lookup** — หางานวิจัยสนับสนุน | 30-60 นาที | 2-3 นาที | PubMed RAG | หมอถามแชท |
| 5 | **Clinical Note Drafting** — ร่างเวชระเบียน | 5-10 นาที/คนไข้ | 1 นาที (แก้ไข) | FHIR + LLM | ปิด Encounter |
| 6 | **ตรวจสอบ & ส่ง Claim** — ตรวจความสอดคล้องและสั่งส่ง Claim เข้าระบบอัตโนมัติ | ถูกปฏิเสธ 10-15% | < 3% | Billing Masters + 🐺 Fenrir | ปิด Encounter |

---

## 📊 2. Data Requirements (ข้อมูลที่ต้องเตรียม)

### A. ข้อมูลโครงสร้างคนไข้ (Eir / OpenEMR Data)
* ตารางประวัติผู้ป่วยจาก OpenEMR ที่เราจะหุ้มด้วยมาตรฐาน **FHIR** ตลอดสาย
* **เป้าหมายระดับ Medical Agent:** AI ต้องสามารถอ่านประวัติยาวๆ (เช่น โรคร่วม, ยา 10 ชนิด) และสรุปความคลาดเคลื่อนทางการยา (Medication Error) ได้ทันที

### B. ข้อมูลค้นคว้าวิจัย (Mimir / PubMed RAG Data)
* ใช้กลยุทธ์ **Hybrid: Local Subset + Cloud Full Search**
    * **Local (เร็ว, < 2s):** ดาวน์โหลดบทความเฉพาะ Domain ผ่าน PubMed E-utilities API กรองด้วย MeSH Terms + Quality Filters (Publication Type, IF, ปีที่ตีพิมพ์) แล้วโยนเข้า Mimir Pipeline ทำ Embedding เก็บใน Vector DB
    * **Cloud (ครอบคลุม, < 5s):** ใช้ BigQuery Semantic Search สำหรับกรณีที่ต้องการค้นหาข้ามสาขาวิชาหรือข้อมูลที่ไม่ได้อยู่ใน Local Subset
* **3-Tier Article Curation:**
    * 🟢 **Guidelines** (~500 บทความ) — Practice Guidelines, Consensus Statements → AI ใช้เป็นกฎเกณฑ์หลัก
    * 🔵 **Evidence** (~5,000-20,000 บทความ) — Meta-analyses, Clinical Trials → AI ใช้ตอบคำถามเชิงค้นคว้า
    * 🟡 **Context** (~10,000-50,000 บทความ) — Review articles → AI ใช้เป็นพื้นหลังความรู้ทั่วไป

### C. ข้อมูลองค์ความรู้กราฟ (Mimir / Precision Medicine Knowledge Graph - PrimeKG)
* **[NEW]** นำเข้าข้อมูล `mims-harvard/PrimeKG` (17,000+ โรค และ 4 ล้านความสัมพันธ์ที่ดึงมาจาก 20 ฐานข้อมูลเกรด A)
* เปลี่ยนกระบวนทัศน์การค้นคว้าเข้าสู่ยุค **GraphRAG** อัดแน่นด้วยคำบรรยายแนวทางการรักษา (Text Descriptions) เพื่อให้ AI สามารถนำไปอธิบายเชื่อมโยงระหว่างตัวยา, ผลข้างเคียง, และการรักษาโรคระดับ Precision Medicine ได้อย่างแม่นยำ

### D. ข้อมูลกฎเกณฑ์ด้านความปลอดภัย (Yggdrasil / Security)
* กลุ่มของ Regex (Regular Expressions) สำหรับการดักจับและปิดบัง PII/PHI (Data Anonymization) ก่อนส่งข้อมูลคนไข้ให้ AI ประมวลผล

### E. ข้อมูลรหัสวินิจฉัยโรค (ICD-10 Multi-Locale)
* ออกแบบเป็น **Namespace แยกตาม Locale** เพื่อรองรับการขาย Multi-market:

| Namespace | ตลาด | แหล่งข้อมูล | ภาษา | อัปเดต |
|-----------|------|------------|------|--------|
| `icd10:cm` | 🇺🇸 สากล (Base) | CMS FY2026 (72,000+ รหัส) | EN | ปีละ 1 ครั้ง (1 ต.ค.) |
| `icd10:tm` | 🇹🇭 ไทย | สมสส. ICD-10-TM | TH/EN | ปีละ 1 ครั้ง |
| `icd10:jp` | 🇯🇵 ญี่ปุ่น | MEDIS 標準病名マスター | JA/EN | ปีละ 2 ครั้ง (1 มิ.ย. / 1 ม.ค.) |

* **Tenant Config:** แต่ละคลินิกเลือก Locale ตอน Onboarding → Odin โหลด Namespace ที่ตรงกันให้อัตโนมัติ
* **Cross-locale Mapping:** รหัส ICD-10 แกนกลาง (WHO) เหมือนกันทุก Locale ต่างกันแค่ Sub-codes และชื่อโรค → AI สามารถ Fallback ไป `icd10:cm` ได้เสมอถ้า Locale เฉพาะไม่มีข้อมูล
* **Target Customers:**
    * 🇹🇭 คลินิกไทย (Mega Care) → `icd10:tm`
    * 🇯🇵 คลินิกญี่ปุ่นในไทย / ขายผ่าน Sojitz・Sakura → `icd10:jp`
* **Odin (Knowledge Lifecycle):** ตรวจสอบเวอร์ชันใหม่ของแต่ละ Locale ตามรอบอัปเดต และ Trigger Mimir ให้ Re-index อัตโนมัติ

### F. ข้อมูลเบิกจ่ายประกัน (Billing & Insurance Master Data — per Locale)

> [!IMPORTANT]
> นอกจาก ICD-10 แล้ว แต่ละประเทศยังมีชุดรหัสเฉพาะสำหรับการเบิกจ่ายประกัน ถ้าขาดหรือไม่ตรง จะถูกปฏิเสธ (Reject/返戻) ทันที

#### 🇹🇭 ไทย: e-Claim Master Data

| Master | ชื่อไทย | หน้าที่ | แหล่งข้อมูล |
|--------|---------|--------|------------|
| **TMT** | รหัสยาไทย (Thai Medicines Terminology) | ระบุรายการยา + ราคา + สิทธิเบิก | สมสท. / `this.or.th` |
| **TMLT** | รหัส Lab ไทย (Thai Medical Lab Terminology) | รหัสการตรวจทางห้องปฏิบัติการ | สมสท. / `this.or.th` |
| **Drug Catalogue** | บัญชียา สปสช. | รายการยาที่ สปสช. อนุมัติเบิกจ่าย | `drug.nhso.go.th` |
| **รหัสหัตถการ** | รหัสการรักษา/หัตถการ | Mapping กับสิทธิเบิกจ่ายแต่ละกองทุน | กรมบัญชีกลาง / ประกันสังคม |

#### 🇯🇵 ญี่ปุ่น: レセプト電算処理 (Rezept) Master Data

| Master | ชื่อญี่ปุ่น | หน้าที่ | แหล่งข้อมูล |
|--------|---------|--------|------------|
| **診療行為マスター** | Procedure Master | รหัสหัตถการ + คะแนน (点数) + กฎการคำนวณ | `shinryohoshu.mhlw.go.jp` |
| **医薬品マスター** | Drug Master | รหัสยา + ราคา (薬価) ตามที่รัฐกำหนด | `shinryohoshu.mhlw.go.jp` |
| **特定器材マスター** | Medical Material Master | รหัสวัสดุ/อุปกรณ์ทางการแพทย์ | `shinryohoshu.mhlw.go.jp` |
| **コメントマスター** | Comment Master | รหัสข้อความเสริมประกอบ Claim | `shinryohoshu.mhlw.go.jp` |
| **修飾語マスター** | Modifier Master | คำขยายชื่อโรค (ซ้าย/ขวา/เฉียบพลัน) | MEDIS |

#### การทำงานของ AI (Use Case #6: Claim Pre-Check & Auto-Submit)
```
แพทย์ปิด Encounter
    → AI ดึงข้อมูล: ชื่อโรค (ICD-10) + หัตถการ + ยา
    → ตรวจสอบ Cross-reference: โรคนี้เบิกหัตถการนี้ได้มั๊ย? ยานี้อยู่ในบัญชีมั๊ย?
    → ถ้าไม่ตรง: แจ้งเตือน + แนะนำรหัสที่ถูกต้อง
    → ถ้าตรง: Bifrost สั่งให้ 🐺 Fenrir (Computer Use Agent) ทำการ Navigation เข้าเว็บ e-Claim / レセプト เพื่อกรอกฟอร์มนำส่งอัตโนมัติ
```
* **ประโยชน์ทางธุรกิจ:** ลดอัตราการถูกปฏิเสธจาก 10-15% เหลือ < 3% (และลดเวลาแอดมิน) → คลินิกได้เงินเร็วขึ้น เป็น Selling Point หลักสำหรับตลาดญี่ปุ่น (返戻率削減)

---

## 🤖 3. Agent Registry (ทะเบียน Agent ทั้งระบบ)

| Agent | Codename | บทบาท | Runtime | MCP Strategy | Allowlisted Tools |
|-------|----------|-------|---------|--------------|-------------------|
| ⚡ **Bifrost** | หัวหน้าทีม | Orchestrator — รับคำถาม วิเคราะห์เจตนา มอบหมายงาน ประกอบคำตอบ | **Rust (Axum + rig.rs)** | MCP Client | `delegate_*`, `route_*` |
| 📨 **Hermóðr** | ผู้ส่งสาร | Universal MCP Sidecar — Bridge ระหว่าง MCP Protocol กับ Legacy REST | Rust (standalone) | MCP Server | N/A (Proxy) |
| 🏥 **Eir** | ผู้รักษา | FHIR Gateway — ดึง/เขียนข้อมูลคนไข้จาก OpenEMR | Rust (Axum) | via Hermóðr | `read_fhir`, `write_clinical_note`, `book_appointment` |
| 🧠 **Mimir** | ผู้จัดการความรู้ | Dual-Role: Curator (Batch Ingest) + Researcher (RAG Query) | Rust (Axum) | Native MCP | `search_knowledge`, `search_primekg`, `ingest_pubmed` |
| 🐺 **Fenrir** | ผู้ช่วยธุรการ | Computer Use — AI Agent สั่ง Browser ด้วย LLM (ใช้ Ratatoskr เป็น Engine) | **Rust (Axum) + Python sidecar** (browser-use) | Native MCP | `navigate_browser`, `click_element`, `fill_form` |
| 🐿️ **Ratatoskr** | กระรอกผู้ส่งข่าว | Shared Headless Browser Service — ให้บริการ Chromium ผ่าน REST API แก่ทุก Agent | Rust (Axum) + Python (Playwright) | Native MCP | `crawl_url`, `screenshot_page` |
| 🛡️ **Heimdall** | ยามเฝ้าประตู | LLM Gateway — Proxy/Route ไปยังโมเดลที่เหมาะสม | Rust (Axum) | via Hermóðr | `get_model_info`, `switch_model` |
| 🌳 **Yggdrasil** | ต้นไม้แห่งโลก | Identity & Auth — SSO, JWT, Tenant Isolation | Go (Zitadel) | via Hermóðr | `validate_token`, `get_user_roles` |
| 🔱 **Odin** | ผู้ดูแลระบบ | Platform Supervisor — Scheduling, Health, QA, Knowledge Lifecycle | **Rust (Axum)** | Internal | `schedule_job`, `health_check`, `circuit_breaker` |
| 🛡️ **Várðr** | ยามรักษาการณ์ | Monitoring & Observability — Metrics, Logs, Alerts | Rust | via Hermóðr | `query_metrics`, `get_alerts` |

> [!IMPORTANT]
> คอลัมน์ **Allowlisted Tools** คือหัวใจของ Security Model — Agent แต่ละตัวสามารถเรียกได้ **เฉพาะ Tools ที่ระบุไว้เท่านั้น** (Deny-by-default) ดูรายละเอียดในหัวข้อ 10

### 🧰 Technical Stack Policy: Rust-First

> [!NOTE]
> **Rust เป็น Priority หลักสำหรับ Backend ทุกตัว** — เพื่อ Memory Safety, Performance (< 30MB RAM), และ Concurrency ที่เหมาะสมกับ Medical Workload

| ภาษา | ใช้เมื่อ | เหตุผล |
|------|---------|--------|
| 🦀 **Rust** (Primary) | ทุก Backend Service, Orchestrator, Gateway, MCP Server | Memory safety, < 30MB RAM, ไม่มี GC pause, Single binary deploy |
| 🐍 **Python** (Sidecar only) | เฉพาะ Library ที่ไม่มีใน Rust (`browser-use`, `zeroclaw-tools`) | ครอบด้วย Rust Axum shell เสมอ ไม่รัน standalone |
| 🐹 **Go** (Exception) | Yggdrasil เท่านั้น (เพราะ Zitadel เป็น Go) | ไม่สร้างใหม่ ใช้ของที่มีอยู่ |
| 🌐 **TypeScript** | Frontend (Next.js Dashboard) เท่านั้น | ไม่ใช้กับ Backend |

---

## 🧠 4. Context-Aware Triggering (AI ที่รู้จักจังหวะ)

> [!IMPORTANT]
> แทนที่จะรอให้หมอเปิดแชทถาม AI ต้อง **"ดันข้อมูลมาหาหมอ"** โดยอัตโนมัติตามบริบท

### Event-Driven Architecture

```
┌─────────────────────────────────────────────────────┐
│              OpenEMR (Mega Care EHR)                 │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ เปิดแฟ้ม  │  │ สั่งยา   │  │ บันทึก Diagnosis  │  │
│  └────┬─────┘  └────┬─────┘  └──────┬────────────┘  │
│       │ Event        │ Event         │ Event         │
└───────┼──────────────┼───────────────┼───────────────┘
        ▼              ▼               ▼
┌─────────────────────────────────────────────────────┐
│    Eir Gateway (Webhook) & Hermóðr (MCP Bridge)     │
│  ┌─────────────────────────────────────────────────┐ │
│  │ Context Router: ตรวจจับ Event → เรียก Agent     │ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌═════════════════════════════════════════════════════┐
║              🔱 ODIN (Platform Supervisor)           ║
║  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌──────────┐ ║
║  │📋 Job    │ │🏥 Health │ │📊 QA   │ │🔄 Know-  │ ║
║  │Scheduler │ │Monitor   │ │Auditor │ │ledge Mgr │ ║
║  └──────────┘ └──────────┘ └────────┘ └──────────┘ ║
╚════════════════════════╦════════════════════════════╝
                         ▼
┌──────────────────────────────────────────────────────┐
│                Bifrost (Orchestrator)                │
│  ┌────────────┐ ┌─────────────────┐ ┌──────────────┐ │
│  │ 📨 Hermóðr │ │ Mimir           │ │ 🐺 Fenrir    │ │
│  │(MCP Sidecar│ │ (Dual Role)     │ │(Computer Use)│ │
│  │ / Bridge)  │ │                 │ └──────────────┘ │
│  │      ▼     │ │ 📥 Curator:     │ ┌──────────────┐ │
│  │ Eir (FHIR) │ │  Ingest/Filter  │ │ Yggdrasil    │ │
│  │ REST APIs  │ │  Embed/Index    │ │(Privacy Guard│ │
│  └──────┬─────┘ │                 │ └──────────────┘ │
│         │       │ 🔍 Researcher:  │                  │
│         │       │  Query/Retrieve │                  │
│         │       │  Cite/Score     │                  │
│         │       └──┬──────────────┘                  │
│         │          ├─ PrimeKG (GraphRAG / Neo4j)     │
│         │          ├─ PubMed Local (Vector DB Subset)│
│         │          └─ PubMed Cloud (BigQuery Fallback│
└─────────┼──────────┼─────────────────────────────────┘
      ▼         ▼
┌─────────────────────────────────────────────────────┐
│   Response + Confidence Score + Citations             │
│  ┌────────────────────────────────────────┐          │
│  │ 💊 Drug X อาจเกิด Interaction กับ Y    │          │
│  │ 📊 Confidence: 92% (Source: PrimeKG)   │          │
│  │ 📄 Ref: DrugBank DB00945               │          │
│  │ [✅ ถูกต้อง] [✏️ แก้ไข] [⚠️ อันตราย]    │          │
│  └────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────┘
```

### Odin: 4 หน้าที่หลัก

| หน้าที่ | รายละเอียด | ตัวอย่างงาน |
|---------|-----------|------------|
| 📋 **Job Scheduler** | จัดตารางงาน Batch สั่ง Agent ทำงานตามเวลา | สั่ง Mimir รัน PubMed Ingestion ทุกสัปดาห์, Warmup Cache ก่อนเปิดคลินิก |
| 🏥 **Health Monitor** | ตรวจสุขภาพ Agent ทุกตัว | Ping Latency, ถ้า Agent ล่ม → แจ้งแอดมิน + เปิด Fallback |
| 📊 **QA Auditor** | วิเคราะห์ Feedback จากแพทย์ | ถ้าพบ ⚠️ อันตราย เกิน Threshold → หยุด Pattern ทันที (Circuit Breaker) |
| 🔄 **Knowledge Lifecycle** | ดูแลวงจรชีวิตข้อมูล | ลด Confidence ของบทความเก่า, ตรวจจับ Retraction, จัดการ Versioning |

### Trigger Mapping (ปรับปรุง — เพิ่ม Odin)

| Event | AI Action | Agent |
|-------|----------|-------|
| เปิดแฟ้มคนไข้ | สรุป Pre-Visit Summary โผล่ใน Sidebar | Eir Agent → Bifrost |
| สั่งยาใหม่ | ตรวจสอบ Drug Interactions ทันที | Eir + PrimeKG → Bifrost |
| บันทึก Diagnosis | แนะนำ ICD-10 + DD เพิ่มเติม | PrimeKG + PubMed → Bifrost |
| ปิด Encounter | ร่าง Clinical Note อัตโนมัติ | Eir Agent → Bifrost |
| ส่ง Claim ประกัน | อนุมัติ & สั่งบอทกรอกฟอร์มนำส่ง e-Claim อัตโนมัติ | Bifrost → Fenrir |
| พิมพ์ถามในแชท (OpenEMR) | Full Multi-Agent Research | Bifrost (ทุกตัว) |
| **รับแชทจากมือถือ (LINE/Teams)** | **Secure Messaging Webhooks: ถาม-ตอบได้ทุกที่ (Auth ผ่าน Yggdrasil)** | **Eir Gateway → Bifrost** |
| **Cron: ทุกสัปดาห์** | **รัน PubMed Ingestion Pipeline** | **Odin → Mimir (Curator)** |
| **Cron: ทุกวัน 02:00** | **Cron Job Scheduler: ร่าง Pre-Visit Summary รอไว้สำหรับเข้าตรวจวันพรุ่งนี้** | **Odin → Eir + Bifrost** |
| **Cron: ทุก 5 นาที** | **Health Check ทุก Agent** | **Odin (Monitor)** |
| **Threshold: ⚠️ > 3 ครั้ง/สัปดาห์** | **Circuit Breaker → หยุด Pattern** | **Odin (QA Auditor)** |

---

## 🚀 5. Construction Phases (แผนการทำงานจริง 5 เฟส)

### 🟢 เฟส 1: Toolsmithing (สร้างเครื่องมือให้ AI)
* **Action Items:**
    * **Hermóðr & Eir:** นำ **Hermóðr (Universal MCP Sidecar)** มาประกบเป็น Bridge ครอบ Eir Gateway ไว้ เพื่อรองรับการคุยท่า MCP Protocol ออกไปหา AI โดยไม่ต้องแกะ Legacy Code ของ Eir จำนวนมาก
    * **Eir:** เพิ่ม **Context Router** module ที่รับ Webhook Events จาก OpenEMR (เปิดแฟ้ม, สั่งยา, บันทึก Dx) แล้วกระจายงานให้ Agent
    * **Mimir (Curator):** สร้าง PubMed Ingestion Pipeline:
        1. ดึง PMIDs ตาม MeSH Terms ผ่าน E-utilities API
        2. กรอง Publication Type + ปี + Impact Factor
        3. ดาวน์โหลด Full-text (PMC OA) หรือ Abstract
        4. จัดกอง (Guidelines / Evidence / Context)
        5. โยนเข้า Mimir Pipeline ทำ Chunking + Embedding พร้อมแนบ Metadata (PMID, Journal, IF, MeSH, Citation Count)
    * **Mimir (Researcher):** เขียนเครื่องมือเชื่อมต่อ GraphRAG (Cypher → PrimeKG) และ `search_medical_literature` (Local Vector DB → BigQuery Fallback)
    * **Yggdrasil:** เตรียม JWT + RBAC สำหรับ Agent Authentication — แต่ละ Agent ต้องมี Machine-User Token เป็นของตัวเอง

### 🟡 เฟส 2: Agent Assembly (สร้างทีมแพทย์ AI)
* สร้าง AI Specialists โดยจัดสรรโมเดลแยกหน้าที่:
    * **Bifrost (หัวหน้าทีม):** ใช้ `MedGemma 4B it` เพื่อความนุ่มนวลและเข้าใจเจตนาแพทย์
    * **🐺 Fenrir (ผู้ช่วยธุรการ / Computer Use):** เป็น Agent ที่มีท่าร่าง Browser Automation ทำหน้าที่ส่งเคลม กรอกฟอร์มเข้าระบบเบิกจ่าย หรือดึงข้อมูลจาก Web Portal ภายนอก — **ต้องรันใน Docker Sandbox** แยก Container ต่อ Task เพื่อป้องกันการเข้าถึงข้อมูลคนไข้โดยตรง
    * **Mimir (ผู้จัดการคลังความรู้ + นักวิจัย):** ใช้ `Qwen 3.5 35B` — ทำหน้าที่ 2 อย่าง:
        * 📥 **Curator Mode:** รัน Batch Pipeline เป็นระยะ (Cron/Manual) เพื่อดึงบทความใหม่จาก PubMed กรอง คัดสรร แล้ว Index เข้า Vector DB อัตโนมัติ
        * 🔍 **Researcher Mode:** ตอบคำถามเชิงค้นคว้าจาก Bifrost โดยค้นหาจาก Local Vector DB ก่อน ถ้าไม่เจอจึง Fallback ไป BigQuery Cloud
    * **Heimdall (ผู้ทรงคุณวุฒิ / LLM Step-up Router):** ปกติระบบจะใช้โมเดล Local (Qwen 3.5 / MedGemma) ผ่าน `llama.cpp` แต่เมื่อ Bifrost ตรวจพบว่าเคสมีความอันตราย (เช่น Drug Interaction ระดับ Major, Oncology) จะ Step-up ไปยัง `Gemini 2.5 Pro` ผ่าน Heimdall เพื่อ Second Opinion ระดับโลก
* สร้าง **Agent Persona Files** ตามมาตรฐาน AIEOS (ดูหัวข้อ 9) สำหรับทุก Agent

### 🟠 เฟส 3: Orchestration & Observability (Bifrost Brain)
* ติดตั้งระบบตรรกะหัวหน้าวง ใช้ **Rust Agent Framework** (`rig.rs` + custom orchestration) ให้ Bifrost สามารถคิด สั่งงาน Eir และประกอบร่างคำตอบจาก Mimir ก่อนจะฉายขึ้นหน้าจอ
* **Trajectory Context Compressor:** เมื่อ Context ประวัติคนไข้ยาวเกินขีดจำกัด Bifrost ตัวบีบอัดจะสรุปผล Lab และประวัติย้อนหลังลด 70% ก่อนส่งให้ LLM ประหยัด Token และกันความสับสน
* เพิ่มระบบ **Confidence Scoring** ให้คะแนนความน่าเชื่อถือของทุกคำตอบก่อนส่งหาแพทย์
* เพิ่ม **A2A Protocol** (Agent-to-Agent) ให้ Bifrost สามารถค้นพบ Agent ภายนอกได้ผ่าน Agent Card (ดูหัวข้อ 11)
* เชื่อมต่อ **Várðr** (Monitoring) เพื่อ Trace ทุก Agent call chain ด้วย **OpenTelemetry** — แพทย์ต้องสามารถดู "AI คิดยังไง" ได้ย้อนหลัง (ดูหัวข้อ 12)

### 🔴 เฟส 4: Frontend Integration & Feedback Loop
* ส่งผลงานเข้าสู่ Chat Interface และ Sidebar ของ OpenEMR
* เพิ่มระบบ Feedback 3 ระดับ (ดูหัวข้อที่ 8)
* บันทึก **Structured Audit Trail** ทุกคำตอบที่ AI สร้างขึ้น ลงฐานข้อมูลพร้อม Hash สำหรับตรวจสอบย้อนหลัง (ดูหัวข้อ 13)

### 🟣 เฟส 5: Hardening & Compliance
* ตรวจสอบความปลอดภัยทุก Agent ด้วย Red-Team Testing (Prompt Injection, Tool Misuse)
* จัดทำเอกสาร **Clinical Safety Case** ตามมาตรฐาน IEC 62304 (Software Life Cycle for Medical Devices)
* เปิดให้คลินิกนำร่อง (Pilot) ใช้งานแบบ Shadow Mode (AI แนะนำแต่ไม่ Execute) ก่อนเปิดใช้งานจริง

---

## 📊 6. Confidence Scoring & Source Hierarchy (ระดับความน่าเชื่อถือ)

> [!WARNING]
> ทุกคำตอบของ AI ที่แสดงต่อแพทย์ **ต้อง** แนบระดับความเชื่อมั่นและแหล่งอ้างอิงเสมอ ไม่มีข้อยกเว้น

### ลำดับชั้นข้อมูล (Source Hierarchy)

| ระดับ | แหล่งข้อมูล | ตัวอย่าง | Badge สี |
|-------|------------|---------|---------|
| 🟢 1 (สูงสุด) | ข้อมูลจาก OpenEMR โดยตรง | ผลแล็บจริง, ประวัติจริง | เขียว |
| 🔵 2 | ข้อมูลจาก PrimeKG (Peer-reviewed) | ยาตีกัน, ความสัมพันธ์โรค-ยีน | น้ำเงิน |
| 🟡 3 | ข้อมูลจาก PubMed RAG | งานวิจัย (ดู Impact Factor) | เหลือง |
| 🔴 4 (ต่ำสุด) | การอนุมาน (Inference) จาก LLM | AI สรุปเอง ไม่มีแหล่งอ้างอิงตรง | แดง + Warning |

### ตัวอย่าง Response ที่แพทย์จะเห็น
```
💊 Metformin อาจเพิ่มความเสี่ยง Lactic Acidosis ในผู้ป่วยที่มี eGFR < 30
   📊 Confidence: 94%
   🟢 Patient eGFR: 28 ml/min (ผลแล็บ 3 วันก่อน — OpenEMR)
   🔵 Drug-Disease Link: PrimeKG Node #DG-4521 (DrugBank + SIDER)
   🟡 Supporting Evidence: PMID:31243891 (NEJM, IF: 91.2)
   
   [✅ ถูกต้อง] [✏️ แก้ไข] [⚠️ อันตราย]
```

---

## ⏱️ 7. Latency Budget (งบเวลาที่ยอมรับได้)

> [!IMPORTANT]
> ถ้าหมอถามแล้วต้องรอนานเกิน 10 วินาที หมอจะเลิกใช้ — ต้องกำหนดเพดานให้ชัดเจน

| เส้นทาง | Agent ที่เกี่ยวข้อง | งบเวลาสูงสุด | กลยุทธ์ |
|---------|-------------------|-------------|---------|
| FHIR Query เดี่ยว (Pre-Visit Summary) | Eir via Hermóðr | **< 500ms** | Cache ล่วงหน้า |
| PrimeKG Lookup (Drug Interaction) | Mimir | **< 2s** | Pre-indexed Cypher |
| PubMed Search (Evidence) | Mimir | **< 5s** | BigQuery Warm Pool |
| Full Multi-Agent (Complex Query) | Bifrost + ทุกตัว | **< 10s** | Streaming + Skeleton UI |
| Claim Auto-Submit (Browser) | Fenrir (Sandbox) | **< 30s** | Pre-authenticated Session |
| LLM Step-up (Second Opinion) | Heimdall → Cloud | **< 15s** | Async + Notification |

สำหรับ Use Cases ที่ใช้เวลาเกิน 2 วินาที ต้องแสดง **Progressive Loading** เช่น:
- *"กำลังดึงประวัติคนไข้..."* → *"กำลังตรวจสอบยาตีกัน..."* → *"กำลังค้นหางานวิจัยสนับสนุน..."*

---

## 🔄 8. Medical Feedback Loop (ระบบ Feedback 3 ระดับ)

> [!CAUTION]
> ปุ่ม 👍👎 ธรรมดาไม่เพียงพอสำหรับสายแพทย์ ต้องมี 3 ระดับ

| ปุ่ม | ความหมาย | ผลลัพธ์ในระบบ |
|------|---------|-------------|
| ✅ **ถูกต้อง** | คำตอบถูกต้อง นำไปใช้ได้ | บันทึกเป็น Positive Training Signal |
| ✏️ **แก้ไข** | คำตอบใกล้เคียงแต่ต้องปรับ | **Preference Memory:** หากมีการแก้ข้อความสไตล์เดิมๆ บ่อย (เช่น "ทำให้สั้นลง") ระบบจะเสนอให้แอดมินหรือแพทย์อัปเดตนิสัย (Identity) ของ Agent ถาวร (Human-in-the-loop) |
| ⚠️ **อันตราย** | คำตอบอาจเป็นอันตรายต่อคนไข้ | **Alert ทันที** → เข้าสู่ Safety Review Queue → ปิดการใช้งาน Pattern นี้ชั่วคราว |

---

## 🎭 9. Agent Persona Architecture (ระบบจัดการตัวตน AI)

> [!NOTE]
> ดัดแปลงจากมาตรฐาน **AIEOS (AI Entity Object Specification)** ของ OpenClaw/ZeroClaw — ปรับให้เหมาะกับบริบท Medical AI

แต่ละ Agent ในระบบจะมี **Persona Files** แยกเป็น 3 ไฟล์ เก็บไว้ที่ `asgard/personas/{agent_name}/`:

| ไฟล์ | หน้าที่ | ตัวอย่าง (Eir Agent) |
|------|--------|---------------------|
| `IDENTITY.md` | กำหนดบทบาท ขอบเขตหน้าที่ สิ่งที่ **ห้าม** ทำ | *"คุณคือ Eir พยาบาลผู้สรุปประวัติคนไข้ คุณ **ห้าม** วินิจฉัยโรคหรือสั่งยาเอง"* |
| `TONE.md` | กำหนดน้ำเสียง ศัพท์ ภาษา ความยาว | *"ใช้ศัพท์แพทย์ (Medical Terminology) สั้น กระชับ หลีกเลี่ยงคำเยิ่นเย้อ ตอบเป็น Bullet Points"* |
| `CONTEXT.md` | ปรับตาม Tenant/หมอ — โหลดตอน Login | *"แพทย์ผู้ใช้: กุมารแพทย์ → เน้น Growth Chart, วัคซีน, Developmental Milestones"* |

### ประโยชน์
* **ลด Hallucination:** Agent มีขอบเขตที่ชัดเจน ไม่หลุดบทบาท
* **Portable:** ย้าย Persona ข้ามโมเดลได้ (เช่น จาก MedGemma → Qwen) โดยนิสัยไม่เปลี่ยน
* **GitOps Persona Synchronization (Audit Trail):** ทุกครั้งที่มีการแก้ไขหรืออัปเดต Identity ระบบ Studio จะบันทึกไฟล์ Persona นี้ลง Git repository ด้วย ทำให้แพทย์และ Admin สามารถตรวจสอบประวัติการเปลี่ยนพฤติกรรมของ AI ได้ (ข้อควรระวังตามมาตรฐาน IEC 62304)
* **Per-Tenant Customization:** คลินิกแต่ละแห่งสามารถ Override `CONTEXT.md` เพื่อปรับ AI ให้ตรงกับ Specialty ของแพทย์

---

## 🔒 10. Security Sandbox — Deny-by-Default (กรอบความปลอดภัย Agent)

> [!CAUTION]
> ในสภาพแวดล้อมทางการแพทย์ Agent ที่ "ทำได้ทุกอย่าง" = ความเสี่ยงระดับชีวิต
> ต้องใช้หลักการ **Deny-by-default** — Agent ทำได้ **เฉพาะ** สิ่งที่อนุญาตเท่านั้น

### สถาปัตยกรรม 3 ชั้นป้องกัน

```
┌─────────────────────────────────────────────────────────┐
│  ชั้น 1: Tool Allowlist (MCP Level)                     │
│  แต่ละ Agent มี Allowlist ของ Tools ที่เรียกได้           │
│  เช่น Mimir: [search_knowledge, search_primekg]        │
│       Eir:   [read_fhir, write_clinical_note]           │
│       Fenrir: [navigate_browser, fill_form]             │
│  ถ้าเรียก Tool นอก Allowlist → REJECT + Log ทันที        │
├─────────────────────────────────────────────────────────┤
│  ชั้น 2: Data Boundary (Tenant Isolation)               │
│  Yggdrasil JWT + X-Tenant-Id → Agent เข้าถึงเฉพาะข้อมูล  │
│  ของ Tenant ตัวเอง ข้ามไม่ได้                             │
├─────────────────────────────────────────────────────────┤
│  ชั้น 3: Execution Sandbox (Container Level)            │
│  Fenrir: Docker container per-task (ไม่มี network ไป DB) │
│  Yggdrasil: PII/PHI scrubbing ก่อนส่งข้อมูลไป LLM       │
└─────────────────────────────────────────────────────────┘
```

### ตัวอย่างสถานการณ์ที่ป้องกันได้
| สถานการณ์ | ถ้าไม่มี Sandbox | ด้วย Deny-by-default |
|-----------|-----------------|---------------------|
| Bifrost วิเคราะห์เจตนาผิด สั่งให้ Mimir ลบข้อมูล | ข้อมูลคนไข้หาย | Mimir ไม่มี `delete_*` ใน Allowlist → REJECT |
| Prompt Injection ใน Chat สั่งให้ Fenrir เปิดเว็บอันตราย | เปิดเว็บได้ | Fenrir อยู่ใน Docker sandbox ไม่มี network access ไปหา DB |
| หมอ A ถาม AI เรื่องคนไข้ของหมอ B | เห็นข้อมูลข้ามคน | JWT + Tenant Isolation → เห็นเฉพาะของตัวเอง |

---

## 🔗 11. Communication Protocols (MCP + A2A)

### MCP: Agent ↔ Tools (ใช้แล้ว — Sprint 33)
| ลักษณะ | รายละเอียด |
|--------|------------|
| **มาตรฐาน** | Model Context Protocol (Anthropic) |
| **Transport** | JSON-RPC over SSE |
| **การใช้งาน** | Bifrost (Client) → Hermóðr / Mimir / Fenrir (Server) |
| **ขอบเขต** | เรียก Tool เดี่ยวๆ เช่น `search_knowledge`, `fill_form` |

### A2A: Agent ↔ Agent (แผนเฟส 3)
| ลักษณะ | รายละเอียด |
|--------|------------|
| **มาตรฐาน** | Agent-to-Agent Protocol (Google / Linux Foundation) |
| **Transport** | HTTP + JSON-RPC + SSE |
| **Agent Card** | ไฟล์ JSON ที่อธิบายความสามารถของ Agent → ใช้สำหรับ Discovery |
| **Task Lifecycle** | `submitted → working → completed / failed` |
| **การใช้งาน** | Bifrost (A2A Client) ค้นพบและมอบหมายงานข้าม Agent |

```
MCP  = Agent คุยกับ "เครื่องมือ" (Tool Calling)
A2A  = Agent คุยกับ "Agent ตัวอื่น" (Task Delegation)
ทั้งสองเสริมกัน — Asgard ต้องรองรับทั้งคู่
```

| Where | Action | Phase |
|-------|--------|-------|
| 🧠 Mimir | A2A Server — expose agents + Agent Card registry | เฟส 3 |
| ⚡ Bifrost | A2A Client — call external agents + multi-skill routing | เฟส 3 |
| 🛡️ Heimdall | A2A proxy + auth — route + validate A2A requests | เฟส 3 |

---

## 📡 12. Observability & Tracing (ระบบตรวจสอบย้อนหลัง)

> [!IMPORTANT]
> ในทางการแพทย์ "AI ตอบอะไร" สำคัญพอๆ กับ "AI คิดยังไง" — ต้อง Trace ได้ทุก Step

### สถาปัตยกรรม Observability

| ชั้น | เครื่องมือ | ข้อมูลที่เก็บ |
|------|----------|---------------|
| **Tracing** | OpenTelemetry + Várðr | Trace ID → แต่ละ Agent call chain (Bifrost → Mimir → Heimdall) |
| **Metrics** | Prometheus + Grafana | Latency per agent, Token usage, Error rate, Confidence distribution |
| **Logging** | Structured JSON Logs | ทุก Tool call, ทุก LLM prompt/response (redacted PII) |
| **Alerting** | Odin Health Monitor | Agent down, Latency > SLA, ⚠️ Feedback > threshold |

### Clinical Trace Example
```json
{
  "trace_id": "tr-20260410-001",
  "encounter_id": "enc-5521",
  "physician_id": "dr-tanaka",
  "steps": [
    {"agent": "eir",    "tool": "read_fhir",         "latency_ms": 120, "status": "ok"},
    {"agent": "mimir",  "tool": "search_primekg",     "latency_ms": 850, "status": "ok", "nodes_found": 3},
    {"agent": "mimir",  "tool": "search_knowledge",    "latency_ms": 1200, "status": "ok", "chunks": 5},
    {"agent": "bifrost","tool": "generate_response",   "latency_ms": 2100, "model": "medgemma-4b", "confidence": 0.94},
    {"agent": "bifrost","action": "step_up_rejected",  "reason": "confidence >= 0.90, no step-up needed"}
  ],
  "total_latency_ms": 4270,
  "feedback": null
}
```

---

## 📋 13. Structured Audit Trail (บันทึกตรวจสอบ)

> [!WARNING]
> ทุกคำแนะนำที่ AI สร้างขึ้นต้องมี **Immutable Audit Record** — เป็นข้อกำหนดทางกฎหมายสำหรับซอฟต์แวร์ทางการแพทย์

| Field | Type | Purpose |
|-------|------|--------|
| `audit_id` | UUID | Primary key |
| `trace_id` | String | เชื่อมกลับไป Observability Trace |
| `encounter_id` | String | เชื่อมกลับไป OpenEMR Encounter |
| `physician_id` | String | แพทย์ที่เห็นคำแนะนำ |
| `agent_chain` | JSON | ลำดับ Agent ที่เกี่ยวข้อง + Tools ที่เรียก |
| `ai_recommendation` | Text | คำแนะนำที่ AI สร้างขึ้น (Full text) |
| `confidence_score` | Float | คะแนนความเชื่อมั่น |
| `sources` | JSON[] | แหล่งอ้างอิง (PMID, PrimeKG Node, FHIR Resource) |
| `model_version` | String | โมเดลที่ใช้ + Version |
| `persona_version` | String | Git commit hash ของ Persona files |
| `feedback` | Enum | `approved` / `corrected` / `dangerous` / `null` |
| `correction_text` | Text | ถ้าหมอกด ✏️ แก้ไข — เก็บคำแก้ไข |
| `content_hash` | SHA-256 | Hash ของ `ai_recommendation` — ป้องกันการแก้ไขย้อนหลัง |
| `created_at` | Timestamp | เวลาที่สร้าง |

---

## ⚠️ 14. ขอบเขตความปลอดภัย (Liability & Compliance)

> [!CAUTION]
> เมื่อ Asgard ขยับจากการเป็น "สรุปเอกสาร" ขึ้นมาเป็น **"คู่คิดแพทย์"** ต้องมีมาตรการเหล่านี้ครบถ้วน

### กฎเหล็ก 5 ข้อ

1. **Explainability สูง:** กราฟ PrimeKG จะตอบโจทย์ตรงนี้ เพราะ AI สามารถบอกได้ว่า *"นำคำตอบนี้มาจาก Node ไหนใน Graph"* และแนบ Guideline ที่ชัดเจนกลับมาได้
2. **เน้นเป็น Draft เสมอ:** การสั่งจ่ายยา หรือแผนการรักษาที่ AI สรุป ต้องอยู่ในรูปของคำแนะนำ และแพทย์จะต้องเป็นคนประทับตราอนุมัติขั้นสุดท้ายเท่านั้น (**Human-in-the-loop**)
3. **Disclaimer ชัดเจน:** ทุกหน้าจอต้องแสดงข้อความว่า *"ระบบนี้เป็นเครื่องมือสนับสนุนการตัดสินใจ ไม่ใช่การวินิจฉัยโรค"*
4. **Shadow Mode ก่อนเปิดจริง:** ช่วง Pilot ต้องรันแบบ Shadow (AI แนะนำแต่ไม่ Execute) เพื่อเก็บสถิติความแม่นยำก่อนเปิดใช้งานจริง
5. **Audit Trail ครบถ้วน:** ทุกคำแนะนำต้องบันทึกลง Immutable Audit Log พร้อม Content Hash (ดูหัวข้อ 13)

### Compliance Checklist
| มาตรฐาน | ขอบเขต | สถานะ |
|---------|--------|-------|
| **IEC 62304** | Software Life Cycle for Medical Devices | 📋 Planned (เฟส 5) |
| **ISO 29110** | Software Engineering for VSE | ✅ Active (ใช้อยู่แล้วทั้ง Ecosystem) |
| **PDPA / HIPAA** | ข้อมูลส่วนบุคคล / PHI | ✅ Yggdrasil PII Scrubbing |
| **FDA SaMD** | Software as a Medical Device (ถ้าขาย US) | 📋 Evaluate in เฟส 5 |

---

## 🛡️ 15. Guardrails & Responsible AI (จุดวาง Guardrail ตลอดสาย)

> [!CAUTION]
> ระบบ Medical AI ที่ไม่มี Guardrail = ระเบิดเวลา
> ต้องวาง Guardrail **ทุกจุดที่ข้อมูลไหลผ่าน** ไม่ใช่แค่ขาออก

### แผนผัง Guardrail 6 จุดตลอด Data Flow

```
  ผู้ใช้ (แพทย์ / Chat)
        │
        ▼
  ┌─ 🚧 G1: INPUT GUARDRAIL ──────────────────────────────┐
  │  ตำแหน่ง: Eir Gateway / Hermóðr                        │
  │  ✦ Prompt Injection Detection (Regex + Classifier)     │
  │  ✦ Input Sanitization (HTML/Script stripping)          │
  │  ✦ Rate Limiting per-physician (Heimdall)              │
  │  ✦ ภาษาอันตราย / Self-harm Detection                   │
  └────────────────────────────────────────────────────────┘
        │
        ▼
  ┌─ 🔐 G2: PRIVACY GUARDRAIL ────────────────────────────┐
  │  ตำแหน่ง: Yggdrasil (Privacy Guard)                     │
  │  ✦ PII/PHI Scrubbing ก่อนส่งข้อมูลคนไข้ให้ LLM         │
  │  ✦ De-identification: ชื่อ → [PATIENT], HN → [ID]      │
  │  ✦ Tenant Boundary Enforcement (JWT + X-Tenant-Id)     │
  │  ✦ Consent Verification — คนไข้ยินยอมใช้ AI หรือไม่     │
  └────────────────────────────────────────────────────────┘
        │
        ▼
  ┌─ 🧠 G3: ORCHESTRATOR GUARDRAIL ───────────────────────┐
  │  ตำแหน่ง: Bifrost (Orchestrator)                        │
  │  ✦ Intent Classification — คำถามนี้ MedGemma ตอบได้     │
  │    หรือต้อง Step-up ไป Gemini 2.5 Pro?                  │
  │  ✦ Scope Guard — คำถามอยู่ในขอบเขตทางการแพทย์หรือไม่    │
  │    (ถ้าถามเรื่องอื่น → ปฏิเสธสุภาพ)                      │
  │  ✦ Tool Allowlist Enforcement (Deny-by-default)         │
  │  ✦ Max Agent Hop Limit — ป้องกัน Infinite Delegation    │
  │  ✦ Dangerousness Classifier — ตรวจว่าคำถามเกี่ยวกับ     │
  │    เรื่องเสี่ยง (เช่น ยาเคมีบำบัด, เด็ก) → บังคับ Step-up │
  └────────────────────────────────────────────────────────┘
        │
        ▼
  ┌─ 📡 G4: LLM GUARDRAIL ────────────────────────────────┐
  │  ตำแหน่ง: Heimdall (LLM Gateway)                        │
  │  ✦ Model Safety Filters (built-in ของแต่ละโมเดล)        │
  │  ✦ Token Budget Limiter — ป้องกัน Context Overflow       │
  │  ✦ Temperature Clamping — บังคับ temp ≤ 0.3             │
  │    สำหรับงาน Medical (ลด Creative Hallucination)         │
  │  ✦ System Prompt Injection — ใส่ Persona Files          │
  │    (IDENTITY.md + TONE.md) ก่อน User Prompt เสมอ         │
  │  ✦ Timeout + Fallback — ถ้า LLM ค้างเกิน SLA → ตัดทิ้ง  │
  └────────────────────────────────────────────────────────┘
        │
        ▼
  ┌─ ✅ G5: OUTPUT GUARDRAIL ──────────────────────────────┐
  │  ตำแหน่ง: Bifrost (ก่อนแสดงผลหาแพทย์)                   │
  │  ✦ Citation Enforcement — คำตอบต้องมีแหล่งอ้างอิง ≥ 1    │
  │    ถ้าไม่มี → Badge แดง + Warning (ดูหัวข้อ 6)           │
  │  ✦ Confidence Threshold — ถ้า < 60% → ปฏิเสธแสดง        │
  │    แจ้ง "ข้อมูลไม่เพียงพอ กรุณาปรึกษาแพทย์ผู้เชี่ยวชาญ"   │
  │  ✦ Contraindication Double-Check — ถ้าคำตอบมีชื่อยา      │
  │    cross-check กับ Drug Interaction อีกครั้งอัตโนมัติ      │
  │  ✦ Disclaimer Injection — แนบ Disclaimer ทุกคำตอบ       │
  │  ✦ Harmful Content Filter — ตรวจคำตอบที่อาจเป็นอันตราย   │
  │    เช่น แนะนำหยุดยาเอง, ปรับโดสเกินขนาด                  │
  └────────────────────────────────────────────────────────┘
        │
        ▼
    แพทย์เห็นคำตอบ → กด [✅] [✏️] [⚠️]
        │
        ▼
  ┌─ 🔄 G6: FEEDBACK GUARDRAIL ───────────────────────────┐
  │  ตำแหน่ง: Odin (QA Auditor)                             │
  │  ✦ Circuit Breaker — ⚠️ อันตราย > 3 ครั้ง/สัปดาห์        │
  │    → หยุด Pattern นั้นทันที + แจ้ง Admin                  │
  │  ✦ Drift Detection — ตรวจจับว่า Confidence เฉลี่ยลดลง    │
  │    เรื่อยๆ หรือไม่ → อาจหมายถึง Knowledge เก่า           │
  │  ✦ Bias Monitoring — ตรวจว่า AI แนะนำยาบางยี่ห้อ         │
  │    มากผิดปกติหรือไม่ (Pharmaceutical Bias)                │
  │  ✦ Correction Learning — เก็บ Correction Pairs → ใช้     │
  │    ปรับ Persona / Prompt ใน Cycle ถัดไป                  │
  └────────────────────────────────────────────────────────┘
```

### สรุปจุดวาง Guardrail ↔ Service ที่รับผิดชอบ

| จุด | Guardrail | Service ที่รับผิดชอบ | เฟส |
|-----|-----------|---------------------|-----|
| G1 | **Input Guardrail** — Prompt Injection, Sanitization, Rate Limit | Eir + Hermóðr + Heimdall | เฟส 1 |
| G2 | **Privacy Guardrail** — PII/PHI Scrubbing, Consent, Tenant Isolation | Yggdrasil | เฟส 1 |
| G3 | **Orchestrator Guardrail** — Scope Guard, Dangerousness Classifier, Tool Allowlist | Bifrost | เฟส 2-3 |
| G4 | **LLM Guardrail** — Safety Filters, Temperature Clamp, Token Budget, Timeout | Heimdall | เฟส 1-2 |
| G5 | **Output Guardrail** — Citation Check, Confidence Gate, Contraindication Verify, Disclaimer | Bifrost | เฟส 3-4 |
| G6 | **Feedback Guardrail** — Circuit Breaker, Drift Detection, Bias Monitoring | Odin | เฟส 4-5 |

### Responsible AI Principles สำหรับ Asgard

| หลักการ | การปฏิบัติจริง | Guardrail ที่เกี่ยว |
|---------|---------------|-------------------|
| 🏥 **Beneficence** (ทำประโยชน์) | ทุก Use Case ต้องลดเวลาหมอจริง ไม่สร้างภาระเพิ่ม | ทุก G |
| ⚖️ **Non-maleficence** (ไม่ทำอันตราย) | ห้ามแนะนำยาเกินขนาด, ห้ามวินิจฉัยเอง, Confidence Gate | G3, G5 |
| 🔍 **Transparency** (โปร่งใส) | ทุกคำตอบต้องมี Source + Confidence + Trace ID | G5, 12 |
| 🔒 **Privacy** (ความเป็นส่วนตัว) | PII Scrubbing, Tenant Isolation, Consent Check | G2 |
| 🎯 **Fairness** (เป็นธรรม) | Bias Monitoring, ไม่โปรแกรมยี่ห้อยา | G6 |
| 👨‍⚕️ **Autonomy** (แพทย์ตัดสินใจ) | Human-in-the-loop, Draft Only, Disclaimer | G5, 14 |
| 📋 **Accountability** (ตรวจสอบได้) | Audit Trail + Content Hash, Persona version tracking | G6, 13 |
