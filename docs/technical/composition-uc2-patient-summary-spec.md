# UC2 — Cross-Encounter Patient Summary: Design Spec

**Status:** Draft (paired with [ADR-015](../decisions/ADR-015-add-composition-and-uc2-patient-summary.md) + [ADR-021](../decisions/ADR-021-patient-summary-as-skill.md))
**Date:** 2026-05-26
**Owner:** paripol@megawiz.co
**Sprints affected:** 4 (Composition type), 7 (profile validator), 9 (UI binding), 10 (demo)

## Purpose

Define the concrete schema, section structure, agent preamble, and contracts for the **UC2 Cross-Encounter Patient Summary** demo in Sprint 10. This spec is the implementation handoff for the type-level work (Sprint 4) and the demo wiring (Sprint 10).

## 0. Terminology mapping (ADR-016 alignment)

This spec was originally written assuming an `eir-summary` boundary agent (legacy 19-agent roster pattern). Per [ADR-021](../decisions/ADR-021-patient-summary-as-skill.md), the execution unit is reclassified as the **`patient-summary` skill** hosted on the **`eir-clinical`** boundary agent (per [ADR-010](../decisions/ADR-010-agents-as-boundaries-skills-as-expertise.md) framework).

The sections below retain "eir-summary" wording where it reads naturally — interpret per this mapping:

| In this spec | Skill mode (ADR-021 Accepted) | Fallback mode (ADR-010 not Accepted) |
|---|---|---|
| "eir-summary agent" | `patient-summary` skill composed on `eir-clinical` boundary agent | legacy `agent_configs` row `eir-summary`, model `gemma-4-26b` |
| "agent preamble" (§5) | skill `preamble_fragment` — composed on top of `eir-clinical` system prompt | full `agent_configs.system_prompt` value |
| "tool allowlist" | skill `tool_subset` — intersect with `eir-clinical` ceiling | row tool allowlist JSON |
| `Device(asgard-eir-summary-v1)` (§1.2, §6) | `[Device/asgard-eir-clinical-v{N}, Device/asgard-patient-summary-skill-v1]` in `Composition.author` | `Device(asgard-eir-summary-v1)` single-element author array |
| `Bifrost POST /agents/eir-summary/invoke` | `POST /agents/eir-clinical/invoke?skill=patient-summary` (or cosine-retrieved activation) | `POST /agents/eir-summary/invoke` |
| "agent_configs row" registration step | skill registry record via Bifrost skill-loader API | `agent_configs` row insert |

Output contract (Composition profile, JSON schema, acceptance criteria) is **identical** in both modes — only registration mechanism and author attribution differ.

## 1. Profile: `Composition-asgard-patient-summary`

**Canonical URL:** `http://asgard.local/fhir/StructureDefinition/Composition-asgard-patient-summary`
**Base:** `http://hl7.org/fhir/StructureDefinition/Composition` (R5)
**Derivation:** `constraint`
**Future migration target:** [IPS R5](http://hl7.org/fhir/uv/ips/) when normative

### 1.1 Constraints on Composition

| Field | Cardinality | Constraint |
|---|---|---|
| `meta.profile` | 1..* | MUST include the canonical URL above |
| `type` | 1..1 | LOINC `60591-5` (Patient summary Document) — fixed |
| `status` | 1..1 | `preliminary` (LLM-only) or `final` (clinician-attested); `amended` / `entered-in-error` allowed post-attest |
| `subject` | 1..1 | `Reference(Patient)` |
| `date` | 1..1 | Composition generation timestamp |
| `author` | 1..* | `Reference(Device)` for LLM-only; `Reference(Practitioner)` adds on attestation; both allowed |
| `title` | 1..1 | Free text, recommended pattern: `Patient Summary — {patient.name.text} — {date}` |
| `confidentiality` | 0..1 | `N` (normal) default; `R` (restricted) if Skuggi flags sensitive PII categories |
| `section` | 6..6 | Exactly six sections in the order defined below |

### 1.2 LLM-as-Device author identifier

```json
{
  "resourceType": "Device",
  "id": "asgard-eir-summary-v1",
  "manufacturer": "MegaWiz Co., Ltd.",
  "deviceName": [{"name": "Asgard Eir Summary", "type": "manufacturer-name"}],
  "version": [{"type": {"text": "model"}, "value": "gemma-4-26b"}],
  "type": {
    "coding": [{
      "system": "http://terminology.hl7.org/CodeSystem/device-kind",
      "code": "software"
    }]
  }
}
```

One `Device` row per LLM model + Asgard version combination. Stored in mimir-fhir like any other resource. Tyr audit chains every Composition to its authoring Device, providing model-attribution traceability.

## 2. The 6 Sections

Order matters — section position is part of the profile contract. Section codes are LOINC unless noted.

| # | Section | LOINC | Entry resource types | Required (R) / Recommended (S) |
|---|---|---|---|---|
| 1 | **Problems / Active conditions** | `11450-4` | `Condition` (clinicalStatus=active) | R |
| 2 | **Medications** | `10160-0` | `MedicationRequest` (status=active), `MedicationStatement` (status=recorded/active) | R |
| 3 | **Allergies & Intolerances** | `48765-2` | `AllergyIntolerance` | R |
| 4 | **Recent vital signs** | `8716-3` | `Observation` (8 vital-sign sub-profiles, most recent of each) | S |
| 5 | **Recent results** | `30954-2` | `Observation` (lab sub-profile, last 90 days) + `DiagnosticReport` | S |
| 6 | **Plan of care / Assessment** | `18776-5` | `CarePlan` if available else narrative-only | S |

**Why 3R + 3S (not full IPS 3R + ~14 optional):** Sprint 10 demo focus; UC2 patient summary use case does not need immunization history (covered by UC3), past illness, social history, devices, pregnancy, etc., for the initial demo. Asgard profile keeps the door open — adding sections is non-breaking.

### 2.1 Section structure invariants

For every section:

1. `section.title` — human-readable (Thai or English depending on UI locale)
2. `section.code` — LOINC from table above
3. `section.text.div` — XHTML narrative, language-agnostic content (use Thai if patient context is Thai, English otherwise; never mixed within one section)
4. `section.text.status` — `generated` (LLM-authored) or `extensions` (post-edit)
5. `section.entry[]` — references to resources in the same Bundle or in mimir-fhir store; `reference` form is `{resourceType}/{id}`
6. `section.emptyReason` — required when `entry` is empty (e.g., `unavailable` if data not in EHR, `notasked` if not collected, `nilknown` if explicitly negative)

### 2.2 Section empty-reason value set

```
http://terminology.hl7.org/CodeSystem/list-empty-reason
  - nilknown    — "nothing to report" (e.g., patient has no known allergies)
  - notasked    — clinician did not assess
  - withheld    — information withheld (Skuggi-redacted)
  - unavailable — data exists somewhere but not accessible
  - notstarted  — care plan section before any plan exists
  - closed      — section closed for this episode (uncommon for summary)
```

The LLM MUST emit an explicit `emptyReason` rather than omitting a section. Sections are fixed 6.

## 3. JSON Schema (subset, ABRIDGED for spec — full schema in `mimir-fhir/schemas/`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "http://asgard.local/fhir/Composition-asgard-patient-summary.schema.json",
  "type": "object",
  "required": ["resourceType", "meta", "type", "status", "subject", "date", "author", "title", "section"],
  "properties": {
    "resourceType": {"const": "Composition"},
    "meta": {
      "type": "object",
      "required": ["profile"],
      "properties": {
        "profile": {
          "type": "array",
          "contains": {"const": "http://asgard.local/fhir/StructureDefinition/Composition-asgard-patient-summary"}
        }
      }
    },
    "type": {
      "type": "object",
      "properties": {
        "coding": {
          "type": "array",
          "contains": {
            "type": "object",
            "properties": {
              "system": {"const": "http://loinc.org"},
              "code": {"const": "60591-5"}
            },
            "required": ["system", "code"]
          }
        }
      }
    },
    "status": {"enum": ["preliminary", "final", "amended", "entered-in-error"]},
    "subject": {"$ref": "#/$defs/Reference"},
    "date": {"type": "string", "format": "date-time"},
    "author": {
      "type": "array",
      "minItems": 1,
      "items": {"$ref": "#/$defs/Reference"}
    },
    "title": {"type": "string"},
    "section": {
      "type": "array",
      "minItems": 6,
      "maxItems": 6,
      "items": {"$ref": "#/$defs/Section"}
    }
  },
  "$defs": {
    "Reference": {
      "type": "object",
      "required": ["reference"],
      "properties": {
        "reference": {"type": "string", "pattern": "^(Patient|Practitioner|Device|Condition|MedicationRequest|MedicationStatement|AllergyIntolerance|Observation|DiagnosticReport|CarePlan)/[A-Za-z0-9\\-\\.]+$"}
      }
    },
    "Section": {
      "type": "object",
      "required": ["title", "code", "text"],
      "properties": {
        "title": {"type": "string"},
        "code": {"$ref": "#/$defs/LoincCode"},
        "text": {
          "type": "object",
          "required": ["status", "div"],
          "properties": {
            "status": {"enum": ["generated", "extensions", "additional", "empty"]},
            "div": {"type": "string"}
          }
        },
        "entry": {
          "type": "array",
          "items": {"$ref": "#/$defs/Reference"}
        },
        "emptyReason": {"$ref": "#/$defs/EmptyReason"}
      },
      "anyOf": [
        {"required": ["entry"], "properties": {"entry": {"minItems": 1}}},
        {"required": ["emptyReason"]}
      ]
    },
    "LoincCode": {
      "type": "object",
      "properties": {
        "coding": {
          "type": "array",
          "contains": {
            "type": "object",
            "properties": {
              "system": {"const": "http://loinc.org"},
              "code": {"enum": ["11450-4", "10160-0", "48765-2", "8716-3", "30954-2", "18776-5"]}
            }
          }
        }
      }
    },
    "EmptyReason": {
      "type": "object",
      "properties": {
        "coding": {
          "type": "array",
          "contains": {
            "type": "object",
            "properties": {
              "system": {"const": "http://terminology.hl7.org/CodeSystem/list-empty-reason"},
              "code": {"enum": ["nilknown", "notasked", "withheld", "unavailable", "notstarted", "closed"]}
            }
          }
        }
      }
    }
  }
}
```

Full schema with `meta`, `text` (Composition-level narrative), `confidentiality`, and all FHIR base properties lives at `Mimir/ro-ai-bridge/mimir-fhir/schemas/Composition-asgard-patient-summary.schema.json` (Sprint 4 deliverable).

## 4. Input contract — `openemr_patient_bundle_fetch` MCP tool

Phase 1 demo uses **mimir-fhir REST** directly (not eir-gateway → OpenEMR translation). 43Files adapter (Sprint 8) pre-populates mimir-fhir from the demo HOSxP dump.

```json
{
  "name": "openemr_patient_bundle_fetch",
  "description": "Fetch a patient's longitudinal FHIR R5 Bundle from mimir-fhir for summarization.",
  "input_schema": {
    "type": "object",
    "required": ["patient_id", "tenant_id"],
    "properties": {
      "patient_id": {"type": "string", "description": "FHIR Patient.id"},
      "tenant_id": {"type": "string", "description": "asgard_medical | asgard_insurance | asgard_wellness"},
      "since": {
        "type": "string",
        "format": "date-time",
        "description": "Optional: only include data after this date (default = no filter)"
      },
      "max_observations": {
        "type": "integer",
        "default": 30,
        "description": "Cap on Observation entries to control context length"
      },
      "max_encounters": {
        "type": "integer",
        "default": 15
      }
    }
  },
  "output_schema": {
    "type": "object",
    "properties": {
      "resourceType": {"const": "Bundle"},
      "type": {"const": "collection"},
      "entry": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "fullUrl": {"type": "string"},
            "resource": {"oneOf": [
              {"$ref": "Patient"},
              {"$ref": "Encounter"},
              {"$ref": "Condition"},
              {"$ref": "MedicationRequest"},
              {"$ref": "MedicationStatement"},
              {"$ref": "AllergyIntolerance"},
              {"$ref": "Observation"},
              {"$ref": "DiagnosticReport"},
              {"$ref": "CarePlan"}
            ]}
          }
        }
      }
    }
  }
}
```

Context budget guideline: `max_observations=30 + max_encounters=15` keeps Bundle ≤ ~25k tokens for gemma-4-26b (32k context window). For P2 chronic-complex patient with 3y history, this may need to be adjusted; defer tuning to Sprint 10 demo prep.

## 5. Agent preamble (Thai/English bilingual)

Stored as `agent_configs.system_prompt` for `eir-summary` row. Truncated here to spec-relevant portions:

```
You are Asgard Eir Summary — a clinical AI that generates structured patient summaries from longitudinal FHIR data, for use by Thai clinicians at the point of care.

# Your task

Given a FHIR R5 Bundle (`openemr_patient_bundle_fetch` tool output) for one patient, produce a FHIR `Composition` resource conformant to the `Composition-asgard-patient-summary` profile (canonical URL: http://asgard.local/fhir/StructureDefinition/Composition-asgard-patient-summary).

# Hard rules

1. Output MUST be valid JSON conforming to the provided JSON schema. Do not output Markdown, prose, or any text outside the JSON object.
2. Output `status` MUST be `preliminary` — you are an LLM, not a clinician. Only a human clinician can attest the summary to `final`.
3. Output `author` MUST be a single-element array referencing the Device that represents you: `[{"reference": "Device/asgard-eir-summary-v1"}]`. Do not add Practitioner authors — those are added on clinician attestation, not by you.
4. Output MUST have exactly 6 sections in the fixed order: Problems, Medications, Allergies, Recent vital signs, Recent results, Plan of care / Assessment. Use the LOINC codes from the profile.
5. If a section has no source data, emit `emptyReason` rather than omitting the section. Choose from: `nilknown`, `notasked`, `withheld`, `unavailable`, `notstarted`, `closed`. Bias toward `unavailable` when uncertain — never claim `nilknown` ("nothing to report") unless the EHR explicitly records absence.
6. `section.entry[]` MUST reference resources present in the input Bundle. Do not invent references. Use the form `{resourceType}/{id}` from the input.
7. `section.text.div` MUST be valid XHTML (root `<div xmlns="http://www.w3.org/1999/xhtml">`). Content language matches the patient's context — if the patient has Thai names or address, write narrative in Thai; otherwise English.
8. Do not fabricate clinical facts. Every claim in narrative must be traceable to a resource in `section.entry[]`. If you would say "patient has X" but no entry supports it, omit the claim.
9. Output MUST be a single JSON object. No code fences, no comments.

# Sectioning guidance

**Problems (LOINC 11450-4):** Active Conditions only (`clinicalStatus = active | recurrence | relapse`). Order by clinical priority — chronic disease state (DM, HT, CKD, COPD) first, then acute. Group by ICD-10 chapter is OK but not required.

**Medications (LOINC 10160-0):** Active MedicationRequest + active MedicationStatement, deduplicated by TMT code. If MedicationStatement.adherence indicates non-adherence, note in narrative ("Patient reports non-adherence to ...").

**Allergies (LOINC 48765-2):** All AllergyIntolerance, grouped by category (medication / food / environment / biologic). Severity in narrative.

**Recent vital signs (LOINC 8716-3):** Most recent Observation per vital-sign sub-profile (BP, HR, RR, T, SpO2, BMI, height, weight). Include observation date.

**Recent results (LOINC 30954-2):** Last 90 days of lab Observations and DiagnosticReports. Bias toward labs relevant to active problems (HbA1c if DM, eGFR if CKD, lipids if dyslipidemia).

**Plan of care (LOINC 18776-5):** If CarePlan resource exists, reference it. Otherwise emit `emptyReason = notstarted` and short narrative summarizing the next clinical step inferred from active problems (e.g., "Continue current HT/DM regimen; HbA1c rechecked at next 3-month visit").

# Language

If patient name or address contains Thai script, narrate in Thai. Otherwise narrate in English. Never mix languages within one section. Code system identifiers (LOINC, SNOMED, ICD-10-TM, TMT) are always in their canonical English/Latin form regardless of narrative language.

# Output format

Single JSON object, no surrounding text.
```

## 6. Acceptance tests for Sprint 10 demo

Each demo patient (P1, P2, P3) must produce a Composition that satisfies all of:

1. JSON parses cleanly
2. Validates against `Composition-asgard-patient-summary.schema.json`
3. Validates against the StructureDefinition profile (HAPI R5 validator)
4. All `section.entry[]` references resolve to resources in mimir-fhir store
5. All 6 sections present (with `emptyReason` if no data)
6. `author = [Device/asgard-eir-summary-v1]`, `status = preliminary`
7. Narrative (`text.div`) does not contain content unsupported by `section.entry[]`
8. p50 latency from tool-call → final JSON < 30 s on Mac mini for P2

Additional acceptance for the demo as a whole:

9. Smart-on-FHIR app fetches the Composition by ID and renders 6-section navigation
10. Tyr audit chain has one event per Composition with: `input_bundle_hash`, `model = gemma-4-26b`, `agent_version = asgard-eir-summary-v1`, `output_composition_hash`, `latency_ms`
11. Demo deck slide pair (before/after) recorded for prospect conversations

## 7. Out of scope (deferred to Phase 2)

- Strict IPS R5 conformance (waits for IPS R5 normative)
- Clinician attestation workflow (`status = preliminary` → `final` UI)
- Composition versioning (`amend` workflow + `Composition.relatesTo`)
- Real-time refresh / caching strategy (regenerate-on-demand for MVP)
- Multi-lingual narrative within one section
- Skuggi-driven section redaction (`confidentiality = R` + section-level `withheld`)
- Patient-facing summary export (different profile, simpler language)
- Specialty-flavoured summaries (eir-cardio-summary, eir-sleep-summary — Phase 2 router)

## 8. Open questions to close before Sprint 4 start

| # | Question | Owner | Decision needed by |
|---|---|---|---|
| Q1 | Should `Device(asgard-eir-summary-v1)` be auto-created on mimir-fhir startup, or seeded via migration? | mimir-fhir maintainer | Sprint 4 day 1 |
| Q2 | Where does the JSON schema live — bundled in mimir-fhir crate or external file? | mimir-fhir maintainer | Sprint 4 day 1 |
| Q3 | StructureDefinition profile XML — hand-author or generate from JSON schema? | Sprint 7 owner | Sprint 7 start |
| Q4 | Demo data realism — synthetic only, or anonymized real HOSxP slice? | Demo lead | Sprint 8 start |
| Q5 | LLM context overflow handling — if Bundle > 25k tokens, do we truncate Observations or summarize-then-summarize? | eir-summary owner | Sprint 10 demo prep |

## Links

- [ADR-015](../decisions/ADR-015-add-composition-and-uc2-patient-summary.md) — decision record
- [ADR-006](../decisions/ADR-006-fhir-canonical-design.md) Amendment 2 — Bundle.entry +1
- [ADR-013](../decisions/ADR-013-fhir-r5-canonical-version.md) — R5 canonical
- [mimir-fhir-phase-1-plan.md](mimir-fhir-phase-1-plan.md) Sprint 4 + Sprint 10
- IPS R5 build (reference): http://build.fhir.org/ig/HL7/fhir-ips/
- LOINC `60591-5` Patient summary Document: http://loinc.org/60591-5