# จดหมายขออนุญาตใช้ ICD-10-TM 2017 — Megawiz Limited

**สถานะ:** Draft v1 · Sprint 48 B-48a critical-path
**วันที่:** 2026-05-07
**ผู้รับ:** กองยุทธศาสตร์และแผนงาน · สำนักงานปลัดกระทรวงสาธารณสุข
**ผู้ส่ง:** บริษัท เมก้าวิซ จำกัด · ติดต่อ: paripol@megawiz.co.th

---

## ฉบับภาษาไทย (สำหรับส่งจริง)

```
เรียน  ผู้อำนวยการกองยุทธศาสตร์และแผนงาน
       สำนักงานปลัดกระทรวงสาธารณสุข

เรื่อง  ขออนุญาตใช้ข้อมูล ICD-10-TM 2017 ในระบบ AI ทางการแพทย์ของเมก้าวิซ
        และขอแนวทางการ attribute / referencing ที่เหมาะสม

ด้วยบริษัท เมก้าวิซ จำกัด เป็นผู้พัฒนา Asgard AI Platform ซึ่งเป็น
แพลตฟอร์ม AI ทางการแพทย์แบบ open-source (AGPL-3.0) ที่ออกแบบมาเพื่อให้
โรงพยาบาลในประเทศไทยใช้งานในระดับ production ได้ โดยมีคุณสมบัติ
local-first, multi-tenant, audit-friendly และไม่ต้องส่งข้อมูลผู้ป่วย
ออกนอกประเทศ

โครงการของเรากำลังจะเริ่ม Sprint 48 — Thai Clinical Coding Foundation
(เริ่มประมาณกลาง พ.ค. 2569) ซึ่งจะเพิ่มความสามารถในการค้นหา ICD-10
และ ICD-10-TM ในรูปแบบ semantic search ภาษาไทย เพื่อรองรับการเขียน
encounter records ตามมาตรฐาน FHIR และการเชื่อมต่อกับระบบ HIS/DRG
ของโรงพยาบาล

จึงขอความอนุเคราะห์จากกระทรวงสาธารณสุข ในประเด็นดังต่อไปนี้

1. ขอเข้าถึง dataset ICD-10-TM ฉบับล่าสุด (ICD-10-TM 2017 หรือฉบับ
   ปรับปรุงล่าสุด) ในรูปแบบ digital (Excel / CSV / database export)
   เพื่อนำมา ingest เข้าระบบของบริษัทฯ

2. ขอความชัดเจนเรื่องเงื่อนไขการใช้งาน:
   • ใช้งานเชิง commercial (ผ่าน Enterprise license ของ Asgard) ได้หรือไม่
   • ต้องระบุ attribution ในลักษณะใด เช่น "Powered by ICD-10-TM 2017
     จากกระทรวงสาธารณสุข"
   • หากมี version update ในอนาคต ขั้นตอนการขอ refresh dataset เป็นอย่างไร

3. ขอความเห็นจากผู้รับผิดชอบเกี่ยวกับการ map ICD-10-TM ↔ DRG (สปสช. v6)
   และข้อจำกัดด้าน license ของ DRG หากจะนำมาใช้คู่กัน

บริษัทฯ พร้อมที่จะปฏิบัติตามเงื่อนไขที่กระทรวงสาธารณสุขกำหนด รวมถึงพร้อม
จะส่ง summary ผลการใช้งาน (เช่น จำนวน hospital deployment ที่ใช้
ICD-10-TM ผ่าน Asgard) กลับไปยังหน่วยงานเป็นระยะ เพื่อสนับสนุนการพัฒนา
มาตรฐานการแพทย์ของไทยต่อไป

หากต้องการเอกสารเพิ่มเติม เช่น สำเนาหนังสือรับรองนิติบุคคลของบริษัทฯ
รายละเอียดทางเทคนิคของ Asgard AI Platform หรือต้องการประสานงานทาง
โทรศัพท์ ขอความกรุณาติดต่อกลับที่:

  ปริพล [นามสกุล]
  Megawiz Limited
  อีเมล: paripol@megawiz.co.th
  เว็บไซต์: https://asgard.megawiz.co.th
  GitHub: https://github.com/MegaWiz-Dev-Team/Asgard

จึงเรียนมาเพื่อโปรดพิจารณา

ขอแสดงความนับถือ

(ลงชื่อ)
ปริพล [นามสกุล]
ตำแหน่ง [CEO / Founder]
Megawiz Limited
2026-05-07
```

---

## English summary (for internal record / partner share)

```
Dear Bureau of Health Information / Strategy and Planning Division,
Office of the Permanent Secretary, Ministry of Public Health, Thailand,

Subject: Request for ICD-10-TM 2017 dataset access and licensing guidance
         for Megawiz Asgard AI Platform integration.

Megawiz Limited develops Asgard AI Platform — a production-grade,
AGPL-3.0-licensed medical AI platform designed for Thai hospitals.
Asgard is local-first, multi-tenant, audit-friendly, and avoids
cross-border patient-data transfer.

Our upcoming Sprint 48 (Thai Clinical Coding Foundation) integrates
ICD-10-TM 2017 to enable native Thai semantic search, FHIR Condition
coding, and HIS/DRG interoperability for our hospital partners.

We request:

1. Access to the latest ICD-10-TM dataset in digital form (Excel / CSV
   / DB export) for one-time ingest.

2. Clarification of licensing terms:
   - Eligibility for commercial use (under our Enterprise license tier)
   - Required attribution format (e.g. "Powered by ICD-10-TM 2017 by
     Thai Ministry of Public Health")
   - Update / refresh process for future TM revisions

3. Guidance on the joint use of ICD-10-TM with NHSO (สปสช.) DRG v6
   mapping for billing-ready output.

Megawiz commits to all conditions set by the Ministry and is willing
to share periodic deployment summaries (number of hospital sites,
representative use-cases) to support continued development of Thai
medical-coding standards.

We would be grateful for the opportunity to discuss next steps and
provide any additional documentation required.

Sincerely,
Paripol [last name]
[CEO / Founder], Megawiz Limited
paripol@megawiz.co.th
https://asgard.megawiz.co.th
https://github.com/MegaWiz-Dev-Team/Asgard
2026-05-07
```

---

## ✅ Sender checklist (before sending)

- [ ] Replace `[นามสกุล]` and `[CEO / Founder]` with actual values
- [ ] Confirm the Bureau name — current Thai gov restructure may have
      moved ICD-10-TM ownership; verify on phyo.moph.go.th
- [ ] Verify recipient email (กองยุทธศาสตร์และแผนงาน contact directory)
- [ ] Attach: หนังสือรับรองนิติบุคคล + GitHub link + 1-page Asgard summary
- [ ] CC: legal@megawiz (if exists) for license-terms record
- [ ] Send via official email channel (not Gmail) if available
- [ ] Set follow-up reminder for **2026-05-21** (2 weeks turnaround)

## 📎 Suggested attachments

1. หนังสือรับรองนิติบุคคล (Megawiz Limited business registration)
2. **Asgard 1-pager** — ใช้ของที่อยู่ใน `Asgard-Medical-AI-OnePager.pdf`
   (referenced in memory `med_open_claw_initiative.md`)
3. Sprint 48 spec excerpt (เฉพาะ ICD-10-TM scope, ไม่ต้องใส่ full sprint plan)

## 🔄 Workflow after sending

1. Day 0 — send letter
2. Day 1-3 — confirm receipt (call/email follow-up)
3. Day 7-14 — expected response window
4. Mark **B-48a complete** when:
   - License terms clarified in writing
   - Dataset received OR access path confirmed
   - DRG joint-use clarified

If no response by day 21:
- Escalate via Bureau hotline
- Consider parallel approach: contact NHSO (สปสช.) for DRG portion separately
- Alternative path: collaborate with hospital partner who already holds
  the dataset under their own institutional license

## 🚦 Sprint 48 dev decision tree

```
B-48a status     │ Sprint 48 dev path
─────────────────┼─────────────────────────────────────────────
✅ approved      │ Full plan: int'l ICD-10 wk1 + ICD-10-TM wk2-3
🟡 partial       │ Ship int'l ICD-10; defer TM until full clarity
❌ denied/silent │ Ship int'l ICD-10 only; revisit TM post-MoPH
                 │ via hospital-partner institutional license
```

International ICD-10 dev (B-48b/c/e/f without TM) can ship in week 1
**regardless of B-48a outcome** — no critical-path block.
