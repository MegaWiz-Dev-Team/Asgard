# MOPH-PC1 → FHIR R5 Element Mapping (Canonical Reference)

**Status:** Active reference
**Version:** v1 (2026-05-23)
**Source:** [MOPH-PC1 Data Element Mapping](https://docs.google.com/spreadsheets/d/1n9FvDjd0Wnyx91g-X9UIFnFjLUUp3D6cLZH5OByGPh0/edit?gid=1809761923) — Thailand MOH Primary Care 1 dataset
**FHIR Version:** R5 (per [ADR-013](../decisions/ADR-013-fhir-r5-canonical-version.md))
**Scope:** All Asgard FHIR adapter implementations, Hermodr MCP tool schemas, and `mimir-fhir` ingest/emit paths MUST conform to this mapping.

## Purpose

This document is the canonical reference for **how MOPH-PC1 data elements map to FHIR R5 resources** and **how legacy MOPH 43-Files columns project into FHIR R5**. Adapter implementers, Hermodr tool authors, and `mimir-fhir` reviewers consult this file for ground truth. Updates require PR + ADR amendment if scope changes.

## How to read this table

| Column | Meaning |
|---|---|
| **ID** | MOPH-PC1 element identifier (1-78) |
| **Element** | English data element name (clinical concept) |
| **คำอธิบาย** | Thai description (clinical concept) |
| **FHIR Resource** | R5 resource type |
| **FHIR Path** | R5 element path (uses R5 names, not R4) |
| **Profile** | Profile binding layer — see [Profile Layers](#profile-layers) |
| **Code System** | LOINC / SNOMED code if specified (e.g., for vital signs) |
| **43Files Source** | Legacy MOPH 43-Files column (migration source); `—` if no source exists |
| **Notes** | Caveats, R4↔R5 differences, profile constraints |

**Three profile layers** (see [Profile Layers](#profile-layers)): `MoPH-PC` > `TH Core` > `FHIR base`. Adapters MUST validate against the tightest binding available.

## Resource scope summary

This mapping requires **17 distinct FHIR R5 resources** (12 in original [ADR-006](../decisions/ADR-006-fhir-canonical-design.md) + 5 added in Amendment 1):

| Resource | Element IDs | Count | In ADR-006 v1? |
|---|---|---|---|
| Patient | 1-9 | 9 | ✓ |
| Observation (8 sub-profiles) | 10, 11-18, 29-31, 33, 47-53 | 19 | ✓ |
| AllergyIntolerance | 19-22 | 4 | ✓ |
| DocumentReference | 23-27 | 5 | ✓ |
| DiagnosticReport | 28 | 1 | ✓ |
| **ImagingStudy** | 32 | 1 | **Added Amendment 1** |
| Encounter | 34-39 | 6 | ✓ |
| Organization | 40, 42 | 2 | ✓ |
| **Location** | 41 | 1 | **Added Amendment 1** |
| Coverage | 43-46 | 4 | ✓ |
| **Immunization** | 54 | 1 | **Added Amendment 1** |
| **Specimen** | 62-64 | 3 | **Added Amendment 1** |
| **Device** | 65 | 1 | **Added Amendment 1** |
| MedicationRequest | 66-71 | 6 | ✓ |
| MedicationStatement | 72 | 1 | ✓ |
| Condition | 73-75 | 3 | ✓ |
| Procedure | 76-78 | 3 | ✓ |

`Practitioner` and `Claim`/`ClaimResponse` are in ADR-006 scope but not in MOPH-PC1 (Practitioner needed for `requester`/`participant` references; Claim/ClaimResponse belong to `asgard_insurance` tenant).

## Element mapping (78 rows)

### Patient demographic (IDs 1-10)

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | Profile | 43Files Source | Notes |
|---|---|---|---|---|---|---|---|
| 1 | First name | ชื่อ | Patient | `name.given` | MoPH-PC Patient | `PERSON.NAME` | |
| 2 | Last name | นามสกุล | Patient | `name.family` | MoPH-PC Patient | `PERSON.LNAME` | |
| 3 | Date of birth | วันเดือนปีเกิด | Patient | `birthDate` | MoPH-PC Patient | `PERSON.BIRTH` | |
| 4 | Sex | เพศสรีระ | Patient | `gender` | MoPH-PC Patient | `PERSON.SEX` | Biological sex; gender identity is separate (not in PC1) |
| 5 | Current address | ที่อยู่ปัจจุบัน | Patient | `address` | MoPH-PC Patient | `ADDRESS` | Thai address structure via TH Core extensions |
| 6 | Phone number | หมายเลขโทรศัพท์ | Patient | `telecom` (system=phone) | MoPH-PC Patient | `PERSON.TELEPHONE` | |
| 7 | Email address | อีเมล | Patient | `telecom` (system=email) | MoPH-PC Patient | — | New in FHIR era |
| 8 | Related person's name | ชื่อบุคคลสำหรับติดต่อ | Patient | `contact.name` | MoPH-PC Patient | — | Alternative: RelatedPerson resource |
| 9 | Relationship type | ความสัมพันธ์กับบุคคลนั้น | Patient | `contact.relationship` | MoPH-PC Patient | — | |
| 10 | Occupation | อาชีพ | Observation | `valueCodeableConcept` | TH Core Observation: Occupation (no specific MoPH-PC profile) | `PERSON.OCCUPATION_NEW` | Code system: Thai occupation codes |

### Vital Signs (IDs 11-18) — `TH Core Observation: Vital Signs`

All vital signs use the same FHIR profile with different LOINC codes. Blood pressure uses `component` for SBP/DBP within a single Observation.

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | LOINC | 43Files Source | Notes |
|---|---|---|---|---|---|---|---|
| 11 | Systolic blood pressure | ความดันเลือดซิสโตลิก | Observation | `component:sbp.valueQuantity` | 8480-6 | `SERVICE.SBP` or `NCDSCREEN.SBP_1` or `NCDSCREEN.SBP_2` | Multiple legacy sources; adapter must reconcile |
| 12 | Diastolic blood pressure | ความดันเลือดไดแอสโตลิก | Observation | `component:dbp.valueQuantity` | 8462-4 | `SERVICE.DBP` or `NCDSCREEN.DBP_1` or `NCDSCREEN.DBP_2` | Same Observation as ID 11 (paired component) |
| 13 | Heart rate | อัตราการเต้นของหัวใจ | Observation | `valueQuantity` | 8867-4 | `SERVICE.PR` | |
| 14 | Respiratory rate | อัตราการหายใจ | Observation | `valueQuantity` | 9279-1 | `SERVICE.RR` | |
| 15 | Body temperature | อุณหภูมิร่างกาย | Observation | `valueQuantity` | 8310-5 | `SERVICE.BTEMP` | Celsius default; convert from Fahrenheit on ingest |
| 16 | Body height | ส่วนสูง | Observation | `valueQuantity` | 8302-2 | `CHRONICFU.HEIGHT` or `NCDSCREEN.HEIGHT` | cm |
| 17 | Body weight | น้ำหนัก | Observation | `valueQuantity` | 29463-7 | `CHRONICFU.WEIGHT` or `NCDSCREEN.WEIGHT` | kg |
| 18 | Oxygen saturation | ความเข้มข้นของออกซิเจนในเลือด | Observation | `valueQuantity` | 2708-6 | — | SpO2 % |

### Allergies and Intolerances (IDs 19-22) — `TH Core AllergyIntolerance`

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | Category | 43Files Source | Notes |
|---|---|---|---|---|---|---|---|
| 19 | Substance (medication) | ชนิดยาที่แพ้ | AllergyIntolerance | `code` | medication | `DRUGALLERGY.DRUGALLERGY` | Use TMT code |
| 20 | Substance (environment) | สิ่งแวดล้อมที่แพ้ | AllergyIntolerance | `code` | environment | — | New in FHIR era |
| 21 | Substance (food, other) | อาหาร และอื่น ๆ | AllergyIntolerance | `code` | food, biologic | — | New in FHIR era |
| 22 | Reaction | ลักษณะอาการ | AllergyIntolerance | `reaction.manifestation` | — | `DRUGALLERGY.SYMPTOM` | SNOMED code preferred |

### Clinical Documents (IDs 23-28)

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | Profile | 43Files Source | Notes |
|---|---|---|---|---|---|---|---|
| 23 | History and physical exam note | บันทึกประวัติและการตรวจร่างกาย | DocumentReference | `content` | TH Core DocumentReference (no specific MoPH-PC profile) | — | LOINC type code |
| 24 | Consultation note | บันทึกการปรึกษา | DocumentReference | `content` | TH Core DocumentReference | — | |
| 25 | Discharge summary note | บันทึกสรุปการจำหน่าย | DocumentReference | `content` | TH Core DocumentReference | — | |
| 26 | Procedure note | บันทึกหัตถการ | DocumentReference | `content` | TH Core DocumentReference | — | |
| 27 | Progress note | บันทึกความก้าวหน้าการรักษา | DocumentReference | `content` | TH Core DocumentReference | — | |
| 28 | Test report | รายงานผลการตรวจต่าง ๆ | DiagnosticReport | `conclusion` | MoPH-PC DiagnosticReport | — | Different resource (DiagnosticReport, not DocumentReference) |

### Clinical Information & Tests (IDs 29-31) — `TH Core Observation` (no specific MoPH-PC profile)

| ID | Element | คำอธิบาย | FHIR Path (R5) | LOINC | Notes |
|---|---|---|---|---|---|
| 29 | History | บันทึกประวัติ | `valueString` or `valueCodeableConcept` | 35090-0 (Patient history) | |
| 30 | Physical examination | บันทึกการตรวจร่างกาย | `valueString` or `valueCodeableConcept` | 35091-8 (Patient physical) | |
| 31 | Clinical test | ผลการตรวจทางคลินิก | `valueString` or `valueCodeableConcept` | — | `value[x]` choice depends on text vs coded result |

### Diagnostic Imaging (IDs 32-33)

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | Profile | 43Files | Notes |
|---|---|---|---|---|---|---|---|
| 32 | Diagnostic imaging test | การตรวจทางรังสีวิทยา | **ImagingStudy** | `code` | TH Core ImagingStudy (no specific MoPH-PC profile) | — | **Added Amendment 1** |
| 33 | Diagnostic imaging report | ผลการตรวจทางรังสีวิทยา | Observation | `valueString` | TH Core Observation: Imaging Result | — | Image **interpretation text**, not the DICOM (handled by Syn DICOM) |

### Encounter Information (IDs 34-39) — `TH Core Encounter` / `MoPH-PC Encounter`

⚠️ **R5 vs R4 element renames** here are most numerous — see Notes column.

| ID | Element | คำอธิบาย | FHIR Path (R5) | R4 Equivalent | 43Files Source | Notes |
|---|---|---|---|---|---|---|
| 34 | Encounter type | ชนิดการเข้ารับบริการ | `class` | `class` (same) | `SERVICE` or `ADMISSION` | OPD vs IPD distinction |
| 35 | Encounter identifier | หมายเลขการรับบริการ | `identifier` | `identifier` | `SERVICE.SEQ` or `ADMISSION.AN` | Visit number (VN) or admission number (AN) |
| 36 | Encounter diagnosis | ผลการวินิจฉัย | `diagnosis` | `diagnosis` | `DIAGNOSIS_OPD.DIAGCODE` or `DIAGNOSIS_IPD.DIAGCODE` | ICD-10-TM |
| 37 | Encounter time | วันเวลาที่รับบริการ | **`actualPeriod.start`** | **`period.start`** (R4) | `SERVICE.DATE_SERV` + `SERVICE.TIME_SERV` or `ADMISSION.DATETIME_ADMIT` | **R5 renamed period → actualPeriod** |
| 38 | Encounter location | สถานที่รับบริการ | `location` | `location` (same) | `ADMISSION.WARDADMIT` (OPD has none) | Reference to Location resource |
| 39 | Encounter disposition | สถานที่รับผู้ป่วยหลังจำหน่าย | **`admission.dischargeDisposition`** | **`hospitalization.dischargeDisposition`** (R4) | `SERVICE.REFEROUTHOSP` or `ADMISSION.REFEROUTHOSP` or `SERVICE.TYPEOUT` or `ADMISSION.DISCHTYPE` | **R5 renamed hospitalization → admission**; 43Files mapping is imperfect |

### Facility Information (IDs 40-42)

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | Profile | 43Files | Notes |
|---|---|---|---|---|---|---|---|
| 40 | Facility identifier | หมายเลขระบุสถานบริการ | Organization | `identifier` | MoPH-PC Organization: Provider | `SERVICE.MAIN` | `SERVICE.MAIN` is NOT a location code (per spec note) |
| 41 | Facility type | ชนิดสถานบริการ | **Location** | `type` | TH Core Location (no specific MoPH-PC profile) | — | **Added Amendment 1** |
| 42 | Facility name | ชื่อสถานบริการ | Organization | `name` | MoPH-PC Organization: Provider | — | |

### Health Insurance Information (IDs 43-46) — `TH Core Coverage`

| ID | Element | คำอธิบาย | FHIR Path (R5) | 43Files Source | Notes |
|---|---|---|---|---|---|
| 43 | Coverage status | สถานะของสิทธิการรักษา | `status` | — | active/cancelled/etc |
| 44 | Coverage type | ชนิดของสิทธิการรักษา | `type` | `CARD.INSTYPE_NEW` | UC/SSO/CSMBS/private |
| 45 | Payer identifier | หมายเลขระบุกองทุนหรือผู้จ่าย | `identifier` | `CARD.INSTYPE_NEW` | May be inferred from coverage type |
| 46 | Group identifier | กลุ่มย่อยในสิทธิการรักษานั้น ๆ | `class` | — | |

### Health Status Assessment (IDs 47-53) — Various `TH Core Observation` sub-profiles

| ID | Element | คำอธิบาย | FHIR Path (R5) | Profile | 43Files Source | Notes |
|---|---|---|---|---|---|---|
| 47 | Functional status | ความสามารถในการทำกิจกรรม | `valueCodeableConcept` | TH Core Observation (no specific) | `ICF.ICF` | ICF (Intl Classification of Functioning) code |
| 48 | Mental/cognitive status | สถาวะสุขภาพจิต | `valueCodeableConcept` | TH Core Observation (no specific) | `SPECIALPP` (usable) | |
| 49 | Pregnancy status | การตั้งครรภ์ | `valueCodeableConcept` | TH Core Observation: Pregnancy Status | `PRENATAL.GRAVIDA` or `LABFU.LABRESULT` | May infer from prenatal files |
| 50 | Alcohol use | การใช้แอลกอฮอล์ | `valueCodeableConcept` | TH Core Observation: Alcohol Status | `NCDSCREEN.ALCOHOL` | |
| 51 | Substance use | การใช้สารเสพติด | `valueCodeableConcept` | TH Core Observation (no specific) | — | New in FHIR era |
| 52 | Physical activity | ระดับกิจกรรมทางกาย | `valueCodeableConcept` | TH Core Observation (no specific) | — | New in FHIR era |
| 53 | Smoking status | การสูบบุหรี่ | `valueCodeableConcept` | TH Core Observation: Smoking Status | `NCDSCREEN.SMOKE` | |

### Immunizations (ID 54) — **Added Amendment 1**

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | 43Files Source | Notes |
|---|---|---|---|---|---|---|
| 54 | Immunizations | การรับวัคซีน | **Immunization** | `vaccineCode` | `EPI.VACCINETYPE` | Spec sheet says `valueCodeableConcept` but the canonical Immunization resource uses `vaccineCode` — sheet appears to mis-paste from Observation row. **Adapter MUST use `vaccineCode`.** |

### Laboratory (IDs 55-64)

IDs 55-61 = `TH Core Observation: Laboratory Result`. IDs 62-64 = `TH Core Specimen` (added Amendment 1).

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | 43Files Source | Notes |
|---|---|---|---|---|---|---|
| 55 | Tests | ชนิดการตรวจทางห้องปฏิบัติการ | Observation | `code` | `LABFU.LABTEST` | LOINC preferred |
| 56 | Values/results | ผลการตรวจ | Observation | `valueQuantity.value` | `LABFU.LABRESULT` | Numeric; `valueString` for text |
| 57 | Specimen type | สิ่งส่งตรวจ | Observation | `specimen` (Reference to Specimen) | — | |
| 58 | Result status | สถานะผลการตรวจ | Observation | `status` | — | preliminary/final/amended |
| 59 | Result unit of measure | หน่วยนับของผลการตรวจ | Observation | `valueQuantity.unit` | — | UCUM unit |
| 60 | Result reference range | ค่าอ้างอิงของการตรวจ | Observation | `referenceRange` | — | |
| 61 | Result interpretation | การแปลผลการตรวจ | Observation | `interpretation` | — | normal/high/low/critical |
| 62 | Specimen source site | อวัยวะที่เก็บสิ่งส่งตรวจ | **Specimen** | `collection.bodysite` | — | **Added Amendment 1** |
| 63 | Specimen identifier | หมายเลขระบุสิ่งส่งตรวจ | **Specimen** | `identifier` | — | **Added Amendment 1** |
| 64 | Specimen condition acceptability | คุณภาพของสิ่งส่งตรวจ | **Specimen** | `condition` | — | **Added Amendment 1** |

### Medical Devices (ID 65) — **Added Amendment 1**

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | 43Files | Notes |
|---|---|---|---|---|---|---|
| 65 | Unique device identifier | หมายเลขระบุอุปกรณ์ | **Device** | `udiCarrier` | — | **Added Amendment 1**; UDI per FDA / Thai FDA |

### Medications (IDs 66-72) — `TH Core MedicationRequest` / `TH Core MedicationStatement`

⚠️ Significant R5 changes vs R4 — see Notes.

| ID | Element | คำอธิบาย | FHIR Resource | FHIR Path (R5) | R4 Difference | 43Files Source | Notes |
|---|---|---|---|---|---|---|---|
| 66 | Medications | ชื่อยา | MedicationRequest | `medication` (CodeableReference) | R4: `medicationCodeableConcept` + `medicationReference` polymorphism | `DRUG_OPD.DIDSTD` or `DRUG_IPD.DIDSTD` | **R5 unified into single CodeableReference**; use TMT code |
| 67 | Dose | ขนาดยา | MedicationRequest | `dosageInstruction.doseAndRate.doseQuantity.value` | same | — | |
| 68 | Dose unit of measure | หน่วยนับของขนาดยา | MedicationRequest | `dosageInstruction.doseAndRate.doseQuantity.unit` | same | — | |
| 69 | Indication | ข้อบ่งชี้การใช้ยา | MedicationRequest | `reason` (CodeableReference) | R4: `reasonCode` + `reasonReference` | — | **R5 unified** |
| 70 | Fill status | สถานะการจ่ายยา | MedicationRequest | `status` | same | — | active/completed/cancelled |
| 71 | Medication instructions | ข้อปฏิบัติการใช้ยา | MedicationRequest | `dosageInstruction` | same | — | |
| 72 | Medication adherence | ความร่วมมือในการใช้ยา | MedicationStatement | **`adherence`** | **DOES NOT EXIST in R4** | — | **R5-only field**; R4-emit drops with extension hint per [ADR-013](../decisions/ADR-013-fhir-r5-canonical-version.md) D4 |

### Problems (IDs 73-75) — `TH Core Condition` / `MoPH-PC Condition`

| ID | Element | คำอธิบาย | FHIR Path (R5) | 43Files Source | Notes |
|---|---|---|---|---|---|
| 73 | Problems | โรคหรือปัญหาของผู้ป่วย | `code` | `DIAGNOSIS_OPD.DIAGCODE` or `DIAGNOSIS_IPD.DIAGCODE` | ICD-10-TM; SNOMED preferred |
| 74 | Date of diagnosis | วันที่ได้รับการวินิจฉัย | `recordedDate` | `DIAGNOSIS_OPD.DATE_SERV` (no IPD equivalent) | |
| 75 | Date of resolution | วันที่หายจากโรค | `abatementDateTime` | — | |

### Procedures (IDs 76-78) — `TH Core Procedure` / `MoPH-PC Procedure`

| ID | Element | คำอธิบาย | FHIR Path (R5) | 43Files Source | Notes |
|---|---|---|---|---|---|
| 76 | Procedures | หัตถการ | `code` | `PROCEDURE_OPD.PROCEDCODE` or `PROCEDURE_IPD.PROCEDCODE` | ICD-9-CM-Vol3 or SNOMED |
| 77 | Performance time | วันเวลาที่ทำหัตถการ | `occurrenceDateTime` | `PROCEDURE_OPD.DATE_SERV` or `PROCEDURE_IPD.DATE_SERV` | |
| 78 | Reason for procedure | เหตุผลที่ทำหัตถการ | `reason` (CodeableReference) | — | R5: `reason` unified (R4 had `reasonCode` + `reasonReference`) |

---

## Profile Layers

MOPH-PC1 uses three profile binding layers in priority order:

| Layer | Identifier | Binding Strength | Element Coverage |
|---|---|---|---|
| **1. MoPH-PC** | `MoPH-PC Patient`, `MoPH-PC Observation: Vital`, etc. | Tightest — bound to MOPH Primary Care use case | ~30 elements |
| **2. TH Core** | `TH Core Patient`, `TH Core Observation: ...`, etc. | Broader — HL7 Thailand IG baseline | ~78 elements (all) |
| **3. FHIR base** | "ไม่มี profile ที่จำเพาะ" = no specific profile | Unconstrained R5 | ~25 elements (no specific MoPH-PC binding) |

**Adapter rule:** validate against the **tightest** binding available. If MoPH-PC profile exists for the element, use it; else TH Core; else base FHIR R5.

**Storage rule:** `mimir-fhir` canonical store accepts the union (validates against tightest binding present on ingest, persists as base R5 shape).

## R4 → R5 element name diff (full list)

Implementers of the R4 adapter boundary ([ADR-013](../decisions/ADR-013-fhir-r5-canonical-version.md) D2) MUST translate these:

| MOPH-PC1 ID | Resource | R4 path | R5 path | Translation cost |
|---|---|---|---|---|
| 37 | Encounter | `period.start` | `actualPeriod.start` | rename only |
| 39 | Encounter | `hospitalization.dischargeDisposition` | `admission.dischargeDisposition` | rename only |
| 66 | MedicationRequest | `medicationCodeableConcept` OR `medicationReference` | `medication` (CodeableReference) | merge polymorphism |
| 69 | MedicationRequest | `reasonCode` OR `reasonReference` | `reason` (CodeableReference) | merge polymorphism |
| 78 | Procedure | `reasonCode` OR `reasonReference` | `reason` (CodeableReference) | merge polymorphism |
| 72 | MedicationStatement | (n/a, field new in R5) | `adherence` | drop on R4-emit with extension hint |

## 43Files Migration Coverage

Coverage statistics over 78 elements:

| 43Files mapping status | Count | % |
|---|---|---|
| Has direct 43Files source | ~47 | 60% |
| No 43Files source (new in FHIR era) | ~31 | 40% |

**Net implication:** the OpenEMR / HOSxP adapter for legacy data can populate ~60% of MOPH-PC1 elements automatically. The remaining 40% (email, related person, oxygen saturation, all DocumentReference notes, environment/food allergies, specimen detail, device UDI, etc.) require either new data capture surfaces in Asgard or remain empty until the hospital starts collecting them.

**Gold-value 43Files sources** (used by ≥2 elements):

- `PERSON.*` → Patient demographics (IDs 1-6)
- `SERVICE.*` / `ADMISSION.*` → Encounter (IDs 34-39) and vital signs subsets
- `DIAGNOSIS_OPD.*` / `DIAGNOSIS_IPD.*` → Condition + Encounter.diagnosis (IDs 36, 73-74)
- `DRUG_OPD.*` / `DRUG_IPD.*` → MedicationRequest (ID 66)
- `PROCEDURE_OPD.*` / `PROCEDURE_IPD.*` → Procedure (IDs 76-77)
- `NCDSCREEN.*` → BP, height, weight, smoking, alcohol (multiple IDs)
- `LABFU.*` → Lab Observation (IDs 55-56)

## Known Issues / Discrepancies in the source spec

These items in the source MOPH-PC1 spreadsheet appear inconsistent or ambiguous — adapter implementers should follow this canonical doc, not the raw spreadsheet:

1. **ID 54 (Immunization)** — spreadsheet shows FHIR Path = `valueCodeableConcept`, but `Immunization` is its own resource, not an Observation. Canonical use is `Immunization.vaccineCode`. Spreadsheet likely auto-pasted from preceding Observation row.
2. **ID 39 (Encounter disposition)** — spreadsheet note says "ใน profile ไม่ได้ระบุให้มี element นี้" (the MoPH-PC profile does not specify this element) — Asgard stores it anyway under base R5 conformance.
3. **ID 39 43Files mapping** — spreadsheet remark "ไม่ตรงกันเสียทีเดียว" (not a perfect match) — `SERVICE.TYPEOUT` / `ADMISSION.DISCHTYPE` need a value-set crosswalk. Defer to Phase 3 detail design.
4. **ID 40 (Facility identifier)** — spreadsheet remark "ไม่ใช่รหัสสถานที่" (`SERVICE.MAIN` is NOT a location code) — confirms Organization, not Location.
5. **ID 49 (Pregnancy status)** — 43Files source is inferred (`PRENATAL.GRAVIDA` or `LABFU.LABRESULT`); spreadsheet says "อาจใช้แฟ้มกลุ่มการตั้งครรภ์อนุมานว่า..." (can infer from prenatal file group). Adapter prefers explicit field; inference is fallback.

## Open Questions

1. **Practitioner mapping** — not in MOPH-PC1 but required for `Encounter.participant`, `MedicationRequest.requester`, `DocumentReference.author`. Add a non-PC1 row set?
2. **Thai citizen ID** — `Patient.identifier` slice for the 13-digit Thai national ID needs a specific profile slice. Defer to TH Core profile review.
3. **Address structure** — Thai address (province/district/sub-district hierarchy) needs TH Core address extension. Verify extension URL.
4. **TMT / SNOMED bindings** — drug allergy uses TMT (Thai Medication Terminology), medication uses TMT, diagnosis uses ICD-10-TM. Codify code system URLs.
5. **Time zone** — Thailand is UTC+7 with no DST. Standard ISO 8601 with offset is sufficient; confirm.

## Maintenance

This file is the canonical reference. Changes require:

1. Pull request with rationale
2. ADR amendment if scope (resource list or core decision) changes
3. Adapter test fixture updates in `mimir-fhir/tests/moph_pc1/`

The source spreadsheet may be updated by MOPH independently — when that happens, re-run the audit and produce a v2 of this file with a diff.

## References

- [MOPH-PC1 Data Element Mapping Spreadsheet](https://docs.google.com/spreadsheets/d/1n9FvDjd0Wnyx91g-X9UIFnFjLUUp3D6cLZH5OByGPh0/edit?gid=1809761923)
- [ADR-006: FHIR R5 canonical type design](../decisions/ADR-006-fhir-canonical-design.md) (amended 2026-05-23)
- [ADR-012: FHIR-native data plane (no EHR replacement)](../decisions/ADR-012-fhir-native-data-plane-no-ehr-replacement.md)
- [ADR-013: FHIR R5 as canonical version](../decisions/ADR-013-fhir-r5-canonical-version.md)
- [FHIR R5 spec](http://hl7.org/fhir/R5/)
- [FHIR Thailand IG](https://fhir.moph.go.th)
- MOPH 43-Files dataset standard — Thai Ministry of Public Health
