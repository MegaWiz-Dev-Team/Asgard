# 43Files / HOSxP → FHIR R5 Mapping Matrix

**Version:** v0.1 (Sprint 8 baseline)
**Last updated:** 2026-05-26
**Status:** Living document — updated per mapping landing
**Companion to:** [ADR-020](../decisions/ADR-020-43files-hosxp-fhir-adapter.md)
**Profile family:** Asgard FHIR Profile (see [ADR-016](../decisions/ADR-016-asgard-fhir-profile-family.md))

## Purpose

Authoritative field-level mapping from HOSxP 4.x Standard tables (which conform to the Thai MOPH 43Files schema) to FHIR R5 resources under the Asgard FHIR Profile family. Drives the `mimir-43files-adapter` Rust crate's `map/*` modules.

## Phase 1 scope summary

| Tier | HOSxP table(s) | FHIR resource(s) | Sprint 8 week |
|---|---|---|---|
| 1 | PERSON, HOME, ADDRESS | Patient | Week 1 |
| 1 | SERVICE | Encounter (ambulatory) | Week 2 |
| 1 | ADMISSION, DISCHARGE_IPD | Encounter (inpatient) | Week 2 |
| 1 | DIAGNOSIS_OPD, DIAGNOSIS_IPD | Condition | Week 2 |
| 2 | DRUG_OPD, DRUG_IPD | MedicationRequest, MedicationStatement | Week 3 |
| 2 | DRUG_ALLERGY | AllergyIntolerance | Week 3 |
| 2 | PROCEDURE_OPD, PROCEDURE_IPD | Procedure | Week 3 |
| 2 | LABFU | Observation (lab), DiagnosticReport | Week 3 |
| 2 | NCDSCREEN | Observation (vital signs × 8 sub-profiles) | Week 3 |
| 3 | EPI | Immunization | Week 4 |
| 3 | INSURANCE | Coverage | Week 4 |

## Convention

- `→` lossless mapping
- `→ derive` requires computation (date arithmetic, code lookup, etc.)
- `→ bridge` requires a Mimir KB lookup table (lab, vaccine, etc.)
- `→ extension` stored as Asgard extension (no native FHIR field)
- `(unmapped)` field exists in HOSxP but no FHIR target in Phase 1

## Table 1: PERSON + HOME + ADDRESS → Patient

| HOSxP field | FHIR R5 path | Note |
|---|---|---|
| `PERSON.CID` | `identifier[slice=citizenId].value` | system=`https://fhir.moph.go.th/identifier/citizen-id`; 13-digit validation |
| `PERSON.HN` | `identifier[slice=hn].value` | per-hospital MRN; type=`MR` |
| `PERSON.PID` | `identifier[slice=pid].value` | per-hospital internal ID |
| `PERSON.FNAME` + `LNAME` | `name[slice=thai].given` + `name[slice=thai].family` | use=`official`; Thai script |
| `PERSON.FNAME_ENG` + `LNAME_ENG` | `name[slice=english].given` + `name[slice=english].family` | use=`usual`; Latin transliteration |
| `PERSON.PRENAME` | `name[slice=thai].prefix` | นาย/นาง/นางสาว/เด็กชาย/เด็กหญิง |
| `PERSON.SEX` | `gender` | 1→`male`, 2→`female`, else→`unknown` |
| `PERSON.BIRTH` | `birthDate` | → derive Buddhist→Gregorian (year > 2500) |
| `PERSON.STATUS` + `PERSON.DEATH` | `deceasedBoolean` or `deceasedDateTime` | STATUS=`D` → derive deceased |
| `PERSON.NATION` | `extension[nationality]` | bound to MOPH nationality ValueSet |
| `PERSON.MOO` + `HOME.MOO` | `address.line[0]` | หมู่ที่ |
| `PERSON.SOI` + `HOME.SOI` | `address.line[1]` | ซอย |
| `PERSON.ROAD` + `HOME.ROAD` | `address.line[2]` | ถนน |
| `HOME.TAMBOL` | `address.extension[subDistrict]` | ตำบล (no native FHIR field) |
| `HOME.AMPHUR` | `address.district` | อำเภอ |
| `HOME.CHANGWAT` | `address.state` | จังหวัด |
| `HOME.ZIPCODE` | `address.postalCode` | |
| `PERSON.PHONE` + `HOME.PHONE` | `telecom[system=phone].value` | |
| `PERSON.BLOOD_GROUP` | `extension[bloodGroup]` | A/B/AB/O |
| `PERSON.OCCUPATION` | `extension[occupation]` | bound to MOPH occupation ValueSet |
| `PERSON.MARRY_STATUS` | `maritalStatus` | bound to HL7 marital-status |
| `PERSON.RELIGION` | `extension[religion]` | bound to MOPH religion ValueSet |
| `PERSON.EDUCATION` | `extension[education]` | bound to MOPH education ValueSet |
| `PERSON.UPDATE_DATETIME` | `meta.lastUpdated` | UTC normalize |
| `Patient.id` | `uuid_v5(ASGARD_NS, "{hospital_id}|{CID or HN fallback}")` | → derive (deterministic, stable across re-ingest) |

## Table 2: SERVICE → Encounter (ambulatory)

| HOSxP field | FHIR R5 path | Note |
|---|---|---|
| `SERVICE.VN` | `identifier[slice=vn].value` | per-hospital visit number |
| `SERVICE.HN` | `subject.reference` | resolve to `Patient/{uuid}` via identity table |
| `SERVICE.SERVICEDATE` + `SERVICE.SERVICETIME` | `actualPeriod.start` | combine + Buddhist→Gregorian + timezone normalize |
| `SERVICE.END_VISIT` | `actualPeriod.end` | when null + same-day visit → derive end-of-day |
| `SERVICE.DEPARTMENT` | `serviceType.concept.coding` | bind to MOPH department ValueSet |
| `SERVICE.CLINIC` | `location.location.reference` | resolve to `Location/{uuid}` |
| `SERVICE.PTTYPE` | `extension[patientType]` | OPD/ER/Walk-in classification |
| `class` | `class[0].coding` | Fixed: `ambulatory` per R5 EncounterClass; → derive |
| `status` | `status` | → derive: ACTIVE if no end, COMPLETED otherwise |
| `SERVICE.UPDATE_DATETIME` | `meta.lastUpdated` | |

## Table 3: ADMISSION + DISCHARGE_IPD → Encounter (inpatient)

| HOSxP field | FHIR R5 path | Note |
|---|---|---|
| `ADMISSION.AN` | `identifier[slice=an].value` | admission number |
| `ADMISSION.HN` | `subject.reference` | resolve to Patient |
| `ADMISSION.REGTIME` | `actualPeriod.start` | datetime |
| `DISCHARGE_IPD.DISCHARGE_TIME` | `actualPeriod.end` | datetime |
| `ADMISSION.WARD` | `location[0].location.reference` | resolve to Location ward |
| `ADMISSION.ADMIT_DIAG` | `reason[0].value.concept` | initial admit diagnosis (CodeableReference) |
| `ADMISSION.PRE_DIAG` | `extension[preAdmissionDiagnosis]` | pre-admission impression (Asgard extension) |
| `ADMISSION.ADMIT_TYPE` | `admission.admitSource.coding` | bound to MOPH admit-source ValueSet |
| `DISCHARGE_IPD.DISCHARGE_STATUS` | `admission.dischargeDisposition.coding` | bound to discharge disposition |
| `class` | `class[0].coding` | Fixed: `inpatient encounter`; → derive |
| `Encounter.id` | `uuid_v5(ASGARD_NS, "{hospital_id}|admission|{AN}")` | → derive |

## Table 4: DIAGNOSIS_OPD + DIAGNOSIS_IPD → Condition

| HOSxP field | FHIR R5 path | Note |
|---|---|---|
| `DIAGNOSIS_*.HN` | `subject.reference` | resolve to Patient |
| `DIAGNOSIS_*.ICD10` | `code.coding[0].code` | system=`https://terminology.moph.go.th/CodeSystem/icd10-tm` |
| `DIAGNOSIS_*.VN` or `AN` | `encounter.reference` | resolve to Encounter |
| `DIAGNOSIS_*.DXTYPE` | `category[0].coding` | 1=Principal→`problem-list-item`; 2-5=Comorbidity / Other→`encounter-diagnosis` |
| `DIAGNOSIS_*.DIAGDATE` | `recordedDate` | + Buddhist→Gregorian |
| `clinicalStatus` | `clinicalStatus.coding` | Fixed: `active` for current admissions; → derive |
| `verificationStatus` | `verificationStatus.coding` | Fixed: `confirmed`; → derive |
| `Condition.id` | `uuid_v5(ASGARD_NS, "{hospital_id}|diagnosis_{opd|ipd}|{VN or AN}|{ICD10}|{DXTYPE}")` | → derive |

## Table 5: DRUG_OPD + DRUG_IPD → MedicationRequest + MedicationStatement

| HOSxP field | MedicationRequest path | MedicationStatement path | Note |
|---|---|---|---|
| `DRUG_*.HN` | `subject.reference` | `subject.reference` | resolve to Patient |
| `DRUG_*.VN`/`AN` | `encounter.reference` | `context.reference` | resolve to Encounter |
| `DRUG_*.DIDSTD` | `medication.concept.coding[0].code` | `medication.concept.coding[0].code` | TMT, pass-through; system=`...tmt` |
| `DRUG_*.DRUGNAME` | `medication.concept.coding[0].display` | same | local name |
| `DRUG_*.AMOUNT` + `DRUG_*.UNIT` | `dispenseRequest.quantity` | — | numeric + unit |
| `DRUG_*.USAGE_CODE` | `dosageInstruction[0].text` | `dosage[0].text` | bind to MOPH SIG ValueSet |
| `DRUG_*.STARTDATE` | `authoredOn` | `effectivePeriod.start` | + Buddhist→Gregorian |
| `DRUG_*.ENDDATE` | — | `effectivePeriod.end` | — |
| `DRUG_*.STATUS` | `status` | `status` + `adherence` | → derive: STATUS=active→`active`/`taking`; stopped→`stopped`/`not-taking`; on-hold→`on-hold`/`on-hold` |
| `DRUG_*.DOCTOR_CODE` | `requester.reference` | — | resolve to Practitioner |
| `MedicationRequest.id` | — | — | `uuid_v5(...|drug_*|{VN or AN}|{DIDSTD}|{STARTDATE})` |

**Note D5-only:** MedicationStatement.adherence is R5-new and derived from HOSxP STATUS (see ADR-017 Encounter section for similar pattern).

## Table 6: DRUG_ALLERGY → AllergyIntolerance

| HOSxP field | FHIR R5 path | Note |
|---|---|---|
| `DRUG_ALLERGY.HN` | `patient.reference` | resolve to Patient |
| `DRUG_ALLERGY.DIDSTD` | `code.coding[0].code` | TMT; system=`...tmt` |
| `DRUG_ALLERGY.SYMPTOM` | `reaction[0].manifestation[0].concept.text` | free text + Thai |
| `DRUG_ALLERGY.LEVEL` | `criticality` | 1→`low`, 2→`high`, 3→`unable-to-assess` |
| `DRUG_ALLERGY.REPORT_DATE` | `recordedDate` | + Buddhist→Gregorian |
| `clinicalStatus` | `clinicalStatus.coding` | Fixed: `active`; → derive |
| `verificationStatus` | `verificationStatus.coding` | Fixed: `confirmed` if doctor-reported else `unconfirmed`; → derive |
| `type` | `type` | Fixed: `allergy` |
| `category[0]` | `category` | Fixed: `medication` |

## Table 7: PROCEDURE_OPD + PROCEDURE_IPD → Procedure

| HOSxP field | FHIR R5 path | Note |
|---|---|---|
| `PROCEDURE_*.HN` | `subject.reference` | resolve to Patient |
| `PROCEDURE_*.ICDCM` | `code.coding[0].code` | system=ICD-9-CM or ICD-10-PCS (varies by HOSxP version) |
| `PROCEDURE_*.OPERDATE` | `occurrencePeriod.start` | + Buddhist→Gregorian |
| `PROCEDURE_*.OPERTIME` | `occurrencePeriod.start` (combine) | |
| `PROCEDURE_*.OPERATOR` | `performer[0].actor.reference` | resolve to Practitioner |
| `PROCEDURE_*.WARD` | `location.reference` | resolve to Location |
| `PROCEDURE_*.VN`/`AN` | `encounter.reference` | resolve to Encounter |
| `status` | `status` | Fixed: `completed`; → derive |
| `category` | `category[0].coding` | bind to MOPH procedure category |

## Table 8: LABFU → Observation (laboratory) + DiagnosticReport

| HOSxP field | Observation path | DiagnosticReport path | Note |
|---|---|---|---|
| `LABFU.HN` | `subject.reference` | `subject.reference` | resolve to Patient |
| `LABFU.LABCODE` | `code.coding[0].code` | — | → bridge to LOINC via Mimir KB |
| `LABFU.LABRESULT_NAME` | `code.coding[0].display` | — | local lab name |
| `LABFU.LABRESULT` | `valueQuantity.value` or `valueString` | — | numeric if parseable else string |
| `LABFU.LABRESULT_UNIT` | `valueQuantity.unit` | — | normalize to UCUM |
| `LABFU.NORMAL_VALUE` | `referenceRange[0].text` | — | parse low/high if format known |
| `LABFU.RESULTDATE` | `effectiveDateTime` | `effectiveDateTime` | + Buddhist→Gregorian |
| `LABFU.LAB_NO` | — | `identifier[slice=labNo].value` | report-level grouping key |
| `category` | `category[0].coding` | `category[0].coding` | Fixed: `laboratory` |
| `status` | `status` | `status` | Fixed: `final`; → derive |
| abnormal-flag | `interpretation[0].coding` | — | → derive from `LABRESULT` vs `NORMAL_VALUE` |

DiagnosticReport groups all `Observation`s with the same `LAB_NO`.

## Table 9: NCDSCREEN → Observation (vital signs × 8 sub-profiles)

| HOSxP field | FHIR Observation sub-profile | LOINC code |
|---|---|---|
| `NCDSCREEN.BPS` + `BPD` | blood-pressure | 85354-9 (panel), 8480-6 (systolic), 8462-4 (diastolic) |
| `NCDSCREEN.HEIGHT` | body-height | 8302-2 |
| `NCDSCREEN.WEIGHT` | body-weight | 29463-7 |
| `NCDSCREEN.WAIST` | body-circumference (waist) | 56086-2 |
| `NCDSCREEN.BMI` | bmi | 39156-5 (or → derive from height+weight) |
| `NCDSCREEN.PULSE` | heart-rate | 8867-4 |
| `NCDSCREEN.RR` | respiratory-rate | 9279-1 |
| `NCDSCREEN.TEMP` | body-temperature | 8310-5 |
| `NCDSCREEN.HN` | `subject.reference` | — |
| `NCDSCREEN.SCREEN_DATE` | `effectiveDateTime` | + Buddhist→Gregorian |
| `category` | Fixed: `vital-signs` | — |

When `NCDSCREEN.BPS > 140` or `BPD > 90` repeatedly → adapter additionally emits `Condition` with ICD-10-TM I10 if not already present. Triple-reading rule per Thai HT guideline.

## Table 10: EPI → Immunization

| HOSxP field | FHIR R5 path | Note |
|---|---|---|
| `EPI.HN` | `patient.reference` | resolve to Patient |
| `EPI.VACCINETYPE` | `vaccineCode.coding[0].code` | → bridge: HOSxP local code → CVX or MOPH official |
| `EPI.VACCINEDATE` | `occurrenceDateTime` | + Buddhist→Gregorian |
| `EPI.LOT_NO` | `lotNumber` | |
| `EPI.SITE` | `site.coding` | bind to HL7 administration-site ValueSet |
| `EPI.PROVIDER` | `performer[0].actor.reference` | resolve to Practitioner |
| `status` | `status` | Fixed: `completed`; → derive |

## Table 11: INSURANCE → Coverage

| HOSxP field | FHIR R5 path | Note |
|---|---|---|
| `INSURANCE.HN` | `beneficiary.reference` | resolve to Patient |
| `INSURANCE.INSCL` | `class[0].value` + `class[0].type.coding` | MOPH insurance class code; bind to `moph-insurance-class` |
| `INSURANCE.MAIN_INSCL` | `type.coding` | main coverage type |
| `INSURANCE.HOSPMAIN` | `payor[0].reference` | resolve to Organization (รพ.หลัก) |
| `INSURANCE.HOSPSUB` | `network[0].coverage.reference` | resolve to Organization (รพ.รอง) |
| `INSURANCE.STARTDATE` | `period.start` | + Buddhist→Gregorian |
| `INSURANCE.EXPIRE_DATE` | `period.end` | + Buddhist→Gregorian |
| `status` | `status` | → derive: active if today within period else cancelled |
| `kind` | `kind` | Fixed: `insurance`; → derive |

## Code system bridges (Mimir KB lookups)

The adapter calls Mimir KB at runtime for these bridges. Missing entries emit `fhir.ingest.unmapped_code` to Tyr + Mimir Curator queue.

| Bridge | HOSxP source | FHIR target | Mimir KB table |
|---|---|---|---|
| Lab code | `LABFU.LABCODE` (local) | LOINC | `lab_code_bridge` |
| Vaccine code | `EPI.VACCINETYPE` (local) | CVX or MOPH-official | `vaccine_code_bridge` |
| Department | `SERVICE.DEPARTMENT` (local) | MOPH department ValueSet | `department_code_bridge` |
| SIG (drug usage) | `DRUG_*.USAGE_CODE` (local) | MOPH SIG ValueSet | `sig_code_bridge` |

Pass-through (no bridge needed) — these are already standard:
- TMT (`DRUG_*.DIDSTD`)
- ICD-10-TM (`DIAGNOSIS_*.ICD10`)
- ICD-9-CM / ICD-10-PCS (`PROCEDURE_*.ICDCM`)
- MOPH insurance class (`INSURANCE.INSCL`)

## Open mapping questions

1. **PROCEDURE_*.ICDCM versioning** — some HOSxP installations use ICD-9-CM, some ICD-10-PCS. Need detection rule. Sprint 8 Day 12 task.
2. **LABFU.LABRESULT** parsing — when text contains both numeric + unit (e.g., "120 mg/dL"), need extraction. Defer to ad-hoc regex with Curator fallback.
3. **NCDSCREEN repeat-reading rule** for HT diagnosis — triple-reading threshold needs guideline confirmation with cardio team.
4. **EPI vaccine route** — not all HOSxP installs populate `EPI.ROUTE`. Default to vaccine-specific route from `vaccine_code_bridge.default_route` when missing.
5. **INSURANCE.HOSPMAIN vs HOSPSUB** semantics — need confirmation against MOPH 43Files dictionary v2024.

## Updating this matrix

Mappings are PR-reviewed. Any change to an existing field mapping requires:

1. Update this matrix table row
2. Update corresponding `mimir-43files-adapter` `map/{table}.rs`
3. Add or update golden test case
4. Verify golden case passes ADR-019 profile validators

Adding a new field to existing table → matrix row + mapper update + test, no ADR amendment.

Adding a new table → ADR amendment (or new ADR per scope-change rules in ADR-016 D4).
