# UC2 — Cross-Encounter Patient Summary: Design Spec

**Status:** Draft (paired with [ADR-015](../decisions/ADR-015-add-composition-and-uc2-patient-summary.md) + [ADR-021](../decisions/ADR-021-patient-summary-as-skill.md))
**Date:** 2026-05-26
**Owner:** paripol@megawiz.co
**Sprints affected:** 4 (Composition type), 7 (profile validator), 9 (UI binding), 10 (demo)

## Purpose

Define the concrete schema, section structure, agent preamble, and contracts for the **UC2 Cross-Encounter Patient Summary** demo in Sprint 10. This spec is the implementation handoff for the type-level work (Sprint 4) and the demo wiring (Sprint 10).

## 0. Terminology mapping (ADR-021 alignment)

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

## 4a. Additional MCP tools (4) — enrichment and grounding

The skill body (§5) lists 5 tools total in its `tool_subset`. The first (`openemr_patient_bundle_fetch`) is fully specified in §4 above. The 4 additional tools are specified here. All four are subsets of the `eir-clinical` tool ceiling (per [ADR-021](../decisions/ADR-021-patient-summary-as-skill.md) D1) and are routed through Hermodr to their respective backends.

Total tool-call budget per Composition is **6** (per skill body rule). Typical distribution: 1 bundle_fetch + 0–2 enrichment calls. Heavy polypharmacy (P3) may use up to 4 calls.

### 4a.1 `primekg_disease_relations`

Existing PrimeKG tool per [[primekg_graph_agent]] (agent id=7). The patient-summary skill reuses it, no new code.

```json
{
  "name": "primekg_disease_relations",
  "description": "Retrieve disease-disease and disease-symptom relationships from PrimeKG for grounded multi-morbidity narrative. Use when the patient has ≥2 chronic conditions and you want to mention disease interrelations in the Problems section narrative.",
  "input_schema": {
    "type": "object",
    "required": ["disease_codes"],
    "properties": {
      "disease_codes": {
        "type": "array",
        "minItems": 1,
        "maxItems": 6,
        "items": {
          "type": "object",
          "required": ["system", "code"],
          "properties": {
            "system": {"enum": ["http://hl7.org/fhir/sid/icd-10-tm", "http://hl7.org/fhir/sid/icd-10", "http://snomed.info/sct"]},
            "code": {"type": "string"}
          }
        }
      },
      "relation_types": {
        "type": "array",
        "default": ["disease_disease", "disease_symptom"],
        "items": {"enum": ["disease_disease", "disease_symptom", "disease_pathway", "disease_phenotype"]}
      },
      "max_relations_per_disease": {"type": "integer", "default": 3, "maximum": 5}
    }
  },
  "output_schema": {
    "type": "object",
    "properties": {
      "relations": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["source_code", "target_code", "relation_type", "confidence"],
          "properties": {
            "source_code": {"type": "string"},
            "target_code": {"type": "string"},
            "target_display": {"type": "string"},
            "relation_type": {"type": "string"},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "evidence_count": {"type": "integer"}
          }
        }
      }
    }
  }
}
```

**Backing service:** Bifrost `/agents/primekg/invoke` per [[primekg_graph_agent]]. Header `X-Tenant-Id: asgard_medical` required.
**Errors:** `disease_not_found` (code not in PrimeKG), `tenant_header_missing` (Bifrost rejects without X-Tenant-Id).
**Token budget:** typical response 200–800 tokens for 3 diseases × 3 relations.
**Usage rule:** cite at most 2 relations per Problems narrative (per skill body §Tool use).

### 4a.2 `mimir_drug_search`

```json
{
  "name": "mimir_drug_search",
  "description": "Resolve a Thai or English drug name string to canonical TMT code(s) and alias set. Use when the input MedicationStatement or MedicationRequest lacks a TMT code, or when the drug name in the Bundle differs from common usage and you need to normalise for narrative.",
  "input_schema": {
    "type": "object",
    "required": ["query"],
    "properties": {
      "query": {
        "type": "string",
        "description": "Drug name (Thai or English, brand or generic). Examples: 'enalapril', 'อีนาลาพริล', 'Renitec'"
      },
      "limit": {"type": "integer", "default": 5, "maximum": 10},
      "min_score": {"type": "number", "default": 0.7, "minimum": 0.5}
    }
  },
  "output_schema": {
    "type": "object",
    "properties": {
      "matches": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["tmt_code", "canonical_name", "score"],
          "properties": {
            "tmt_code": {"type": "string", "description": "TMT (Thai Medication Terminology) code"},
            "canonical_name": {"type": "string", "description": "Generic name in English, preferred form"},
            "thai_name": {"type": "string"},
            "aliases": {"type": "array", "items": {"type": "string"}},
            "atc_code": {"type": "string", "description": "ATC classification code if known"},
            "score": {"type": "number"}
          }
        }
      }
    }
  }
}
```

**Backing service:** Mimir `/knowledge/search` against the Thai drug alias KB (26 entries per [[l3_cross_kb_findings_2026_05_19]]) + TMT lookup KB, fused by BGE-M3 cosine score per [[mimir_eir_baseline]]. Tenant = `asgard_platform` (cross-tenant shared KB per [[asgard_shared_knowledge_surface]]).
**Errors:** `no_match` (score below `min_score`), `query_too_short` (< 2 characters).
**Token budget:** ~150–400 tokens typical (5 matches).
**Usage rule:** call only when the input Bundle has a MedicationStatement/MedicationRequest without TMT code, OR when the user explicitly asks about a drug not in the Bundle. Do not call for drugs already resolved.

### 4a.3 `drug_interaction_check`

```json
{
  "name": "drug_interaction_check",
  "description": "Check for clinically significant drug-drug interactions among the patient's active medications. Use when the active medication list has ≥4 drugs, OR when any MedicationStatement.adherence indicates non-adherence (poor adherence + polypharmacy = high-risk combination).",
  "input_schema": {
    "type": "object",
    "required": ["medications"],
    "properties": {
      "medications": {
        "type": "array",
        "minItems": 2,
        "maxItems": 15,
        "items": {
          "type": "object",
          "required": ["tmt_code"],
          "properties": {
            "tmt_code": {"type": "string"},
            "display": {"type": "string"}
          }
        }
      },
      "min_severity": {
        "type": "string",
        "default": "moderate",
        "enum": ["minor", "moderate", "major", "contraindicated"]
      }
    }
  },
  "output_schema": {
    "type": "object",
    "properties": {
      "interactions": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["drug_a_tmt", "drug_b_tmt", "severity", "mechanism", "clinical_effect"],
          "properties": {
            "drug_a_tmt": {"type": "string"},
            "drug_b_tmt": {"type": "string"},
            "severity": {"enum": ["minor", "moderate", "major", "contraindicated"]},
            "mechanism": {"type": "string", "description": "Brief mechanistic explanation"},
            "clinical_effect": {"type": "string", "description": "Expected clinical consequence"},
            "recommendation": {"type": "string", "description": "What clinician should consider (monitor / avoid / dose-adjust)"},
            "evidence_source": {"type": "string", "description": "PrimeKG edge or guideline reference"}
          }
        }
      }
    }
  }
}
```

**Backing service:** PrimeKG drug-drug edge traversal via Bifrost `/agents/primekg/invoke` with `tool=drug_drug_interactions` (new sub-tool, Sprint 4-5 delivery alongside Composition type). Fallback to a static curated DDI table during demo if PrimeKG drug-drug edges incomplete for the demo drug set.
**Errors:** `tmt_code_not_in_graph` (one or more drugs absent from PrimeKG drug nodes; non-fatal — return interactions for the subset that resolves), `service_unavailable`.
**Token budget:** ~200–600 tokens for 4–8 drug pairs returned.
**Usage rule:** trigger only when ≥4 active meds OR adherence concern present. Surface in **Medications section narrative**, not as a separate section. Phrase as "consider" / "monitor for" — never as a directive.

### 4a.4 `evidence_citation_fetch`

**Status:** stub interface for Phase 1; full implementation gated on [[mimir_guideline_lineage_plan]] (Sprint 55). Phase 1 demo (Sprint 10) returns hardcoded citations for the 3 demo conditions (HT, DM, dyslipidemia).

```json
{
  "name": "evidence_citation_fetch",
  "description": "Fetch a clinical guideline citation for a recommended next step in the Plan of care section. Use when emitting a Plan narrative that recommends a specific clinical action (recheck HbA1c at 3 months, escalate ACE inhibitor dose, refer to nephrology) and you want to ground the recommendation in a citable guideline.",
  "input_schema": {
    "type": "object",
    "required": ["condition_code", "recommendation_intent"],
    "properties": {
      "condition_code": {
        "type": "object",
        "required": ["system", "code"],
        "properties": {
          "system": {"type": "string"},
          "code": {"type": "string"}
        }
      },
      "recommendation_intent": {
        "type": "string",
        "enum": ["follow_up_interval", "lab_recheck", "medication_escalation", "specialist_referral", "lifestyle"]
      },
      "patient_context": {
        "type": "object",
        "description": "Optional context for personalised citation (age range, sex, comorbidities)",
        "properties": {
          "age_band": {"enum": ["pediatric", "adult", "elderly"]},
          "comorbidities": {"type": "array", "items": {"type": "string"}}
        }
      }
    }
  },
  "output_schema": {
    "type": "object",
    "properties": {
      "citations": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["recommendation_text", "guideline_title", "guideline_society", "year"],
          "properties": {
            "recommendation_text": {"type": "string", "description": "Verbatim guideline recommendation"},
            "guideline_title": {"type": "string"},
            "guideline_society": {"type": "string", "description": "RCPT, ACC/AHA, etc."},
            "year": {"type": "integer"},
            "evidence_level": {"type": "string", "description": "e.g., GRADE 1A"},
            "url": {"type": "string", "format": "uri"}
          }
        }
      }
    }
  }
}
```

**Backing service (Phase 1 stub):** hardcoded JSON fixture in `Mimir/scripts/eir-summary-citation-fixture.json` covering the demo patient conditions. Returns one citation per (condition_code, recommendation_intent) pair.
**Backing service (Sprint 55+):** Neo4j subgraph query over MAGICapp-ingested guidelines + Mimir Well memory artifacts per [[mimir_guideline_lineage_plan]] [[mimir_well_memory_artifacts]].
**Errors:** `no_citation_available` (no guideline match) — non-fatal, narrative falls back to inferred clinical reasoning.
**Token budget:** ~150–300 tokens per citation.
**Usage rule:** at most 2 citations per Plan of care narrative. Optional — skip the tool if the inferred plan is uncontroversial (e.g., "continue current regimen, recheck in 3 months" for stable HT).

### 4b. Tool-use sequencing rules

The skill body §Tool use limits to ≤6 calls per Composition. Recommended sequencing:

1. `openemr_patient_bundle_fetch` — always first, once.
2. (optional) `mimir_drug_search` — only if Bundle has un-coded medications.
3. (conditional) `drug_interaction_check` — only if ≥4 active meds OR adherence concern.
4. (optional) `primekg_disease_relations` — only if ≥2 chronic conditions.
5. (optional) `evidence_citation_fetch` — at most 2 calls, only if Plan narrative will make a specific clinical recommendation.

**Anti-patterns** (skill body refuses):

- Calling `mimir_drug_search` for drugs already resolved with valid TMT codes
- Calling `drug_interaction_check` with fewer than 2 medications
- Calling `primekg_disease_relations` for a single condition
- Calling any tool more than twice
- Calling `openemr_patient_bundle_fetch` a second time (re-use the first result)

## 5. Skill body (production preamble)

The skill body is composed onto the `eir-clinical` system prompt by the Bifrost skill-loader (per [ADR-021](../decisions/ADR-021-patient-summary-as-skill.md) D1). It inherits safety floor, refusal policy, model, and tool ceiling from the host; the body below only narrows behaviour for the patient-summary task.

The text below is the **canonical skill body** — drop directly into `skill.preamble_fragment`. Token budget: ~1100 tokens (excluding few-shot example in §5a).

```
# Skill: patient-summary

You are the patient-summary skill, composed on eir-clinical. Your only job in this composition is to produce one FHIR R5 Composition resource that summarises a single patient's longitudinal record for a Thai clinician at the point of care. The host agent's safety floor, refusal policy, and tool ceiling still apply; you only narrow behaviour for this task.

## Task

Given a FHIR R5 Bundle for one patient (obtained via openemr_patient_bundle_fetch), produce one Composition resource conformant to the Composition-asgard-patient-summary profile (canonical URL http://asgard.local/fhir/StructureDefinition/Composition-asgard-patient-summary). The Composition is for clinician review — never for direct patient consumption, never for billing, never for clinical decision automation.

## Input you will receive

A FHIR Bundle (type=collection) with one Patient, plus a mix of Encounter, Condition, MedicationRequest, MedicationStatement, AllergyIntolerance, Observation, DiagnosticReport, and optionally CarePlan resources. Resource IDs are stable and resolvable. You may also receive enrichment data from tool calls (drug aliases, disease relations, evidence citations) — treat enrichment as supplementary; never invent FHIR resources to back narrative claims.

## Tool use

You have access to a narrowed tool subset (intersection with eir-clinical ceiling):

- openemr_patient_bundle_fetch — call once at the start to obtain the Bundle. Pass max_observations=30, max_encounters=15 unless the user requests a wider window.
- primekg_disease_relations — call when narrating multi-morbidity to ground disease-disease relationships (e.g., DM → CKD → cardiovascular risk). Cite at most 2 relations per Problems section narrative.
- mimir_drug_search — call to resolve TMT codes or canonical drug names you do not recognise. Do not call for drugs already in the input Bundle with valid TMT coding.
- drug_interaction_check — call if you observe ≥4 active medications, OR if MedicationStatement.adherence is recorded for any active drug. Surface significant interactions in the Medications narrative.
- evidence_citation_fetch — call if you need to verify a claim about clinical guideline-recommended next step (Plan of care section). Optional.

Tool-use budget: do not exceed 6 total tool calls per Composition. Prefer fewer.

## Hard rules

1. Output is exactly one JSON object. No prose before or after, no Markdown fences, no comments, no trailing commentary.
2. resourceType is "Composition". meta.profile MUST contain "http://asgard.local/fhir/StructureDefinition/Composition-asgard-patient-summary".
3. status is "preliminary". You are not a clinician; you cannot attest. Only a human clinician changes status to "final".
4. author is a two-element array: [{"reference": "Device/asgard-eir-clinical-v{N}"}, {"reference": "Device/asgard-patient-summary-skill-v1"}]. Use the Device id values provided in the runtime context; do not invent versions.
5. type is fixed: LOINC 60591-5 "Patient summary Document".
6. subject is the input Patient: {"reference": "Patient/{id}"}.
7. date is the current timestamp at generation, ISO 8601 with timezone.
8. title follows the pattern "Patient Summary — {patient_display_name} — {YYYY-MM-DD}". Use Thai or English per the language rule.
9. section MUST have exactly 6 elements in this fixed order: Problems, Medications, Allergies, Recent vital signs, Recent results, Plan of care. Use the LOINC codes 11450-4, 10160-0, 48765-2, 8716-3, 30954-2, 18776-5 respectively.
10. Every section has either at least one entry OR an emptyReason. Never both. Never neither.
11. section.entry references MUST resolve to a resource in the input Bundle. Use the form "{resourceType}/{id}" exactly as it appears in the Bundle. Do not fabricate IDs.
12. section.text.status is "generated" (you authored the narrative). section.text.div is valid XHTML rooted at <div xmlns="http://www.w3.org/1999/xhtml">...</div>.
13. Narrative content must be traceable to entries in the same section. Do not state facts that cannot be backed by an entry or by tool-call enrichment you have made explicit. If unsure, omit.
14. Never fabricate ICD-10, LOINC, SNOMED, TMT, or any code value. Use only codes present in the input or returned by tool calls.
15. Refusal: if the input Bundle is missing the Patient resource, or if more than half the input resources fail FHIR validation, do not emit a Composition — return a JSON object {"error": "input_bundle_invalid", "reason": "<short explanation>"} instead.

## Sectioning

**Problems (11450-4):** Active Conditions only — clinicalStatus.coding.code in {active, recurrence, relapse}. Order: chronic disease state (DM, HT, CKD, COPD, dyslipidemia) first; acute conditions second; symptom-coded conditions last. Group narrative by ICD-10 chapter when ≥4 active conditions; otherwise list inline. If the patient has any of {ESRD, active cancer, immunosuppression}, flag in the narrative leading sentence.

**Medications (10160-0):** All active MedicationRequest (status=active) + all active MedicationStatement (status in {recorded, active}). Deduplicate by TMT code or canonical name. If MedicationStatement.adherence.code indicates non-adherence (codes "not-taking", "on-hold", "intermittent"), include in narrative — this is high-value clinical signal. Surface any output from drug_interaction_check inline in the narrative, not as a separate section.

**Allergies (48765-2):** All AllergyIntolerance grouped by category in the narrative (medication / food / environment / biologic). Note reaction severity from reaction.severity (mild/moderate/severe). If no AllergyIntolerance resources are present in the Bundle AND the input contains an Observation with code LOINC 52473-6 ("Allergy or adverse drug reaction status") marked as "no known allergies", use emptyReason=nilknown. Otherwise use emptyReason=unavailable.

**Recent vital signs (8716-3):** Most recent Observation per vital-sign sub-profile within the past 6 months: BP (8480-6 / 8462-4), HR (8867-4), RR (9279-1), T (8310-5), SpO2 (2708-6), height (8302-2), weight (29463-7), BMI (39156-5). Include observation date inline in narrative. If multiple observations on the same day, pick the latest by effectiveDateTime.

**Recent results (30954-2):** Lab Observations (subset where category=laboratory) from the last 90 days, plus any DiagnosticReport from the same window. Bias toward labs that match active Problems: HbA1c if DM in Problems, eGFR/creatinine if CKD, LDL/HDL/TG if dyslipidemia, TSH if thyroid disorder, ALT/AST if liver issue. Cap at 12 entries; if more, prefer the most clinically actionable per problem mapping. If zero results in window, emptyReason=unavailable.

**Plan of care (18776-5):** If a CarePlan resource is in the Bundle, reference it. Otherwise emit emptyReason=notstarted and a one-paragraph narrative summarising the inferred next step from active Problems (continuation of current regimen, recommended follow-up labs, recommended specialist referral). Phrase as a clinician's note, not as a directive — use "consider", "recommended", "due for".

## Edge cases

- **Conflicting data** (two Observations of the same vital sign on the same day with materially different values): include only the latest; note the discrepancy in narrative.
- **Stale data** (most recent BP is from 2 years ago): include but lead with "last recorded YYYY-MM-DD".
- **Negation-coded data** (Condition with verificationStatus=refuted): exclude from Problems.
- **Empty Bundle** (Patient but no other resources): all 5 non-Patient sections emit emptyReason=unavailable; do not refuse.
- **Sensitive PII categories** (mental health, HIV, pregnancy, substance use): include if present in Bundle, but in narrative use clinical terms only, never colloquial. confidentiality field defaults "N" — runtime promotes to "R" if the host signals.

## Language

Narrative language is Thai if the Patient resource has any Thai-script field (name, address line, etc.), otherwise English. Apply uniformly within one section; do not mix within a section. Code system identifiers (LOINC, SNOMED, ICD-10-TM, TMT, RxNorm) are always in their canonical Latin form regardless of narrative language. Drug names: use the generic name in the chosen narrative language; brand names only if explicitly in the input.

## Output

Single JSON object representing the Composition resource. No surrounding text. No code fences. No comments inside the JSON. UTF-8, Thai characters as native UTF-8, no \\u escape sequences for printable Thai. Stable key order is not required.
```

## 5a. Few-shot example (P1 simple — Thai context)

One reference input → output pair. Use as a one-shot example appended to the skill body when context budget permits (~1500 tokens). The skill-loader may omit it for context-pressured invocations; the hard rules above stand without examples.

The example uses a **simplified** Patient with one chronic condition (essential hypertension), one active medication, no recorded allergies (but no explicit nil-known observation either), three vital-sign observations from a single recent encounter, no labs in the 90-day window, and no CarePlan. It exercises all six section types: four with entries, two with emptyReason.

### Input Bundle (abbreviated)

```json
{
  "resourceType": "Bundle",
  "type": "collection",
  "entry": [
    {
      "fullUrl": "Patient/p001",
      "resource": {
        "resourceType": "Patient",
        "id": "p001",
        "name": [{"text": "สมชาย วงศ์มาลัย", "family": "วงศ์มาลัย", "given": ["สมชาย"]}],
        "gender": "male",
        "birthDate": "1968-04-12",
        "address": [{"line": ["123 ซอยสุขุมวิท 21"], "city": "กรุงเทพมหานคร", "postalCode": "10110", "country": "TH"}]
      }
    },
    {
      "fullUrl": "Condition/c001",
      "resource": {
        "resourceType": "Condition",
        "id": "c001",
        "clinicalStatus": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/condition-clinical", "code": "active"}]},
        "verificationStatus": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/condition-ver-status", "code": "confirmed"}]},
        "code": {"coding": [{"system": "http://hl7.org/fhir/sid/icd-10-tm", "code": "I10", "display": "Essential (primary) hypertension"}]},
        "subject": {"reference": "Patient/p001"},
        "recordedDate": "2022-03-15"
      }
    },
    {
      "fullUrl": "MedicationStatement/m001",
      "resource": {
        "resourceType": "MedicationStatement",
        "id": "m001",
        "status": "recorded",
        "medication": {"concept": {"coding": [{"system": "https://terms.go.th/tmt", "code": "100123", "display": "Enalapril maleate 5 mg tablet"}]}},
        "subject": {"reference": "Patient/p001"},
        "effectivePeriod": {"start": "2022-03-15"},
        "adherence": {"code": {"coding": [{"system": "http://hl7.org/fhir/CodeSystem/medication-statement-adherence", "code": "taking"}]}}
      }
    },
    {
      "fullUrl": "Observation/o001",
      "resource": {
        "resourceType": "Observation",
        "id": "o001",
        "status": "final",
        "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/observation-category", "code": "vital-signs"}]}],
        "code": {"coding": [{"system": "http://loinc.org", "code": "85354-9", "display": "Blood pressure panel"}]},
        "subject": {"reference": "Patient/p001"},
        "effectiveDateTime": "2026-05-20T09:30:00+07:00",
        "component": [
          {"code": {"coding": [{"system": "http://loinc.org", "code": "8480-6"}]}, "valueQuantity": {"value": 142, "unit": "mmHg"}},
          {"code": {"coding": [{"system": "http://loinc.org", "code": "8462-4"}]}, "valueQuantity": {"value": 88, "unit": "mmHg"}}
        ]
      }
    },
    {
      "fullUrl": "Observation/o002",
      "resource": {
        "resourceType": "Observation",
        "id": "o002",
        "status": "final",
        "category": [{"coding": [{"code": "vital-signs"}]}],
        "code": {"coding": [{"system": "http://loinc.org", "code": "8867-4", "display": "Heart rate"}]},
        "subject": {"reference": "Patient/p001"},
        "effectiveDateTime": "2026-05-20T09:30:00+07:00",
        "valueQuantity": {"value": 78, "unit": "/min"}
      }
    },
    {
      "fullUrl": "Observation/o003",
      "resource": {
        "resourceType": "Observation",
        "id": "o003",
        "status": "final",
        "category": [{"coding": [{"code": "vital-signs"}]}],
        "code": {"coding": [{"system": "http://loinc.org", "code": "29463-7", "display": "Body weight"}]},
        "subject": {"reference": "Patient/p001"},
        "effectiveDateTime": "2026-05-20T09:30:00+07:00",
        "valueQuantity": {"value": 75, "unit": "kg"}
      }
    }
  ]
}
```

### Expected Composition output

```json
{
  "resourceType": "Composition",
  "meta": {
    "profile": ["http://asgard.local/fhir/StructureDefinition/Composition-asgard-patient-summary"]
  },
  "status": "preliminary",
  "type": {"coding": [{"system": "http://loinc.org", "code": "60591-5", "display": "Patient summary Document"}]},
  "subject": {"reference": "Patient/p001"},
  "date": "2026-05-26T16:00:00+07:00",
  "author": [
    {"reference": "Device/asgard-eir-clinical-v1"},
    {"reference": "Device/asgard-patient-summary-skill-v1"}
  ],
  "title": "Patient Summary — สมชาย วงศ์มาลัย — 2026-05-26",
  "confidentiality": "N",
  "section": [
    {
      "title": "ปัญหาสุขภาพที่ active",
      "code": {"coding": [{"system": "http://loinc.org", "code": "11450-4", "display": "Problem list"}]},
      "text": {
        "status": "generated",
        "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>ผู้ป่วยมีโรคความดันโลหิตสูงชนิดปฐมภูมิ (I10) ที่ได้รับการยืนยันตั้งแต่ปี 2565 ปัจจุบันยัง active</p></div>"
      },
      "entry": [{"reference": "Condition/c001"}]
    },
    {
      "title": "ยาที่ใช้อยู่ปัจจุบัน",
      "code": {"coding": [{"system": "http://loinc.org", "code": "10160-0", "display": "History of Medication use"}]},
      "text": {
        "status": "generated",
        "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>Enalapril maleate 5 mg ผู้ป่วยรายงานว่ารับประทานยาสม่ำเสมอ (adherence: taking)</p></div>"
      },
      "entry": [{"reference": "MedicationStatement/m001"}]
    },
    {
      "title": "ประวัติแพ้",
      "code": {"coding": [{"system": "http://loinc.org", "code": "48765-2", "display": "Allergies and adverse reactions"}]},
      "text": {
        "status": "generated",
        "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>ไม่พบข้อมูลประวัติการแพ้ในเวชระเบียน (โปรดยืนยันกับผู้ป่วยก่อนสั่งยา)</p></div>"
      },
      "emptyReason": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/list-empty-reason", "code": "unavailable"}]}
    },
    {
      "title": "สัญญาณชีพล่าสุด",
      "code": {"coding": [{"system": "http://loinc.org", "code": "8716-3", "display": "Vital signs"}]},
      "text": {
        "status": "generated",
        "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>วันที่ 2026-05-20: BP 142/88 mmHg, HR 78 /min, น้ำหนัก 75 kg</p></div>"
      },
      "entry": [
        {"reference": "Observation/o001"},
        {"reference": "Observation/o002"},
        {"reference": "Observation/o003"}
      ]
    },
    {
      "title": "ผลตรวจทางห้องปฏิบัติการล่าสุด",
      "code": {"coding": [{"system": "http://loinc.org", "code": "30954-2", "display": "Relevant diagnostic tests/laboratory data"}]},
      "text": {
        "status": "generated",
        "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>ไม่พบผลตรวจในระยะ 90 วันที่ผ่านมา</p></div>"
      },
      "emptyReason": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/list-empty-reason", "code": "unavailable"}]}
    },
    {
      "title": "แผนการดูแลรักษา",
      "code": {"coding": [{"system": "http://loinc.org", "code": "18776-5", "display": "Plan of care"}]},
      "text": {
        "status": "generated",
        "div": "<div xmlns=\"http://www.w3.org/1999/xhtml\"><p>แนะนำให้คงการรักษา Enalapril 5 mg เดิม และนัดตรวจติดตามภายใน 3 เดือน เพื่อประเมิน BP และพิจารณาตรวจ HbA1c, lipid profile, eGFR ในการนัดครั้งถัดไป</p></div>"
      },
      "emptyReason": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/list-empty-reason", "code": "notstarted"}]}
    }
  ]
}
```

### Things this example teaches the LLM

- BP is one Observation with two components (8480-6 systolic + 8462-4 diastolic) — narrative reads "142/88 mmHg", not two separate values
- `adherence: taking` is mentioned in narrative — high-value clinical signal per skill body rule
- Section 3 (Allergies) uses `unavailable` (not `nilknown`) because the input has no explicit "no known allergies" observation
- Section 6 (Plan) uses `notstarted` (no CarePlan resource in input) + a clinical-note-style narrative inferred from active Problems
- Two-Device author array (not one)
- Thai narrative throughout because Patient name is Thai script; codes (LOINC, ICD-10-TM, TMT) stay in Latin
- No tool calls were needed for this simple case (single condition + single med + 3 vitals fit the skill body's "prefer fewer tool calls" guidance)

## 6. Acceptance tests for Sprint 10 demo

Each demo patient (P1, P2, P3) must produce a Composition that satisfies all of:

1. JSON parses cleanly
2. Validates against `Composition-asgard-patient-summary.schema.json`
3. Validates against the StructureDefinition profile (HAPI R5 validator)
4. All `section.entry[]` references resolve to resources in mimir-fhir store
5. All 6 sections present (with `emptyReason` if no data)
6. `author = [Device/asgard-eir-clinical-v{N}, Device/asgard-patient-summary-skill-v1]` (per ADR-021 D2), `status = preliminary`
7. Narrative (`text.div`) does not contain content unsupported by `section.entry[]`
8. p50 latency from tool-call → final JSON < 30 s on Mac mini for P2

Additional acceptance for the demo as a whole:

9. Smart-on-FHIR app fetches the Composition by ID and renders 6-section navigation
10. Tyr audit chain has one event per Composition with: `input_bundle_hash`, `boundary_agent = eir-clinical-v{N}`, `skill = patient-summary-v1`, `model = gemma-4-26b`, `tool_calls = [...]`, `output_composition_hash`, `latency_ms`
11. Demo deck slide pair (before/after) recorded for prospect conversations

## 6a. Demo patient fixtures (P2 + P3)

P1 is fully specified in §5a as the few-shot reference. P2 (chronic-complex) and P3 (polypharmacy) are specified below as fixture *requirements* — not full FHIR JSON. Fixture generation lives in `Mimir/scripts/demo-patients/` (Sprint 10 deliverable); each script produces a valid R5 Bundle conformant to the input contract in §4.

Both P2 and P3 use a fictional Thai hospital `กรุงเทพคลินิก สาขาทดสอบ` (Organization id `org-demo-001`) and a single Practitioner `น.พ. วรรณา ศรีสุวรรณ` (Practitioner id `pract-demo-001`). All Encounters reference both.

### P2 — Chronic-complex (HT + DM + dyslipidemia + CKD3 + stable angina)

**Demographics**

| Field | Value |
|---|---|
| Patient id | `p002` |
| Name | สุดา จันทร์เพ็ญ |
| Gender | female |
| birthDate | 1958-08-22 (age 67) |
| Address | กรุงเทพมหานคร 10400 |
| Citizen ID identifier | use `https://fhir.moph.go.th/identifier/citizen-id` slice per Asgard FHIR Profile |

**Active Conditions (5)**

| id | system | code | display | recordedDate | priority |
|---|---|---|---|---|---|
| `c002-01` | ICD-10-TM | I10 | Essential hypertension | 2016-04-12 | chronic |
| `c002-02` | ICD-10-TM | E11.9 | Type 2 diabetes mellitus | 2018-09-03 | chronic |
| `c002-03` | ICD-10-TM | E78.5 | Hyperlipidaemia, unspecified | 2018-09-03 | chronic |
| `c002-04` | ICD-10-TM | N18.3 | CKD stage 3 | 2022-11-20 | chronic — flag ESRD risk |
| `c002-05` | ICD-10-TM | I25.10 | Atherosclerotic heart disease, stable | 2023-06-15 | chronic |

All have `clinicalStatus.code=active`, `verificationStatus.code=confirmed`.

**Active Medications (8)** — mix of `MedicationStatement` (5) + `MedicationRequest` (3)

| id | drug | TMT code | dose | adherence | notes |
|---|---|---|---|---|---|
| `m002-01` | Enalapril maleate | 100123 | 10mg BID | taking | ACE-i, dose-adjusted for CKD |
| `m002-02` | Metformin HCl | 100445 | 500mg BID | **on-hold** (intermittent GI side effects) | high-value signal |
| `m002-03` | Atorvastatin Ca | 100789 | 20mg HS | taking | |
| `m002-04` | Aspirin | 100231 | 81mg QD | taking | secondary prevention |
| `m002-05` | Amlodipine besylate | 100456 | 5mg QD | taking | second-line antihypertensive |
| `m002-06` | Glipizide | 100567 | 5mg QD | taking | oral hypoglycaemic |
| `m002-07` | Furosemide | 100678 | 20mg QD | taking | volume management for CKD |
| `m002-08` | Isosorbide mononitrate ER | 100890 | 30mg QD | taking | anti-anginal |

**Allergies (1)**

| id | code | severity | reaction | notes |
|---|---|---|---|---|
| `a002-01` | NSAIDs (RxNorm 5640) | severe | hives + angioedema 2019 | high-impact — affects analgesic choice |

**Recent vital signs (most recent encounter 2026-05-18)**

| code | value | flag |
|---|---|---|
| BP (8480-6/8462-4) | 145/92 mmHg | not at goal for DM+CKD (target <130/80) |
| HR (8867-4) | 72 /min | |
| Weight (29463-7) | 65 kg | |
| BMI (39156-5) | 28.1 | overweight |

**Recent labs (last 90 days, 4 results)**

| date | code | value | interpretation |
|---|---|---|---|
| 2026-04-15 | HbA1c (4548-4) | 8.2 % | **poorly controlled** (target <7) |
| 2026-04-15 | eGFR (33914-3) | 42 mL/min/1.73m² | **CKD3a** (consistent with diagnosis) |
| 2026-04-15 | LDL-C (13457-7) | 110 mg/dL | not at goal (<70 for CHD) |
| 2026-04-15 | ACR (14959-1) | 60 mg/g | **microalbuminuria** — DM nephropathy progression |

**CarePlan (1)** — `cp002-01` "CKD-DM combined care plan", category=`assess-plan`, intent=`plan`, status=`active`. Goals: HbA1c <7%, BP <130/80, ACR trending down. Activities: 3-month follow-up, nephrology referral pending.

**Expected skill behaviour**

| Tool | Triggered? | Why |
|---|---|---|
| `openemr_patient_bundle_fetch` | ✅ once | always first |
| `primekg_disease_relations` | ✅ | 5 chronic conditions; expect DM↔CKD, HT↔CHD, dyslipidemia↔CHD relations |
| `mimir_drug_search` | ❌ | all 8 meds have TMT codes |
| `drug_interaction_check` | ✅ | 8 active meds AND adherence concern on Metformin |
| `evidence_citation_fetch` | ✅ optional (≤2 calls) | Plan narrative recommends HbA1c recheck + nephrology referral — cite RCPT CKD guideline + ADA HbA1c target |

**Expected Composition highlights**

- **Problems narrative**: groups by ICD-10 chapter (Circulatory: HT+CHD; Endocrine: DM+dyslipidemia; Genitourinary: CKD3). Leads with ESRD risk flag (per skill body rule for CKD).
- **Medications narrative**: mentions Metformin adherence concern explicitly ("รายงานพักยา Metformin เป็นช่วงๆ เนื่องจากผลข้างเคียงทางเดินอาหาร"). Surfaces drug_interaction_check output inline (e.g., ACE-i + diuretic + CKD = electrolyte monitoring needed).
- **Allergies narrative**: NSAIDs severe — flags impact on pain management.
- **Vitals narrative**: notes BP above target for DM+CKD; lead with "วันที่ 2026-05-18".
- **Results narrative**: HbA1c 8.2 flagged as poorly controlled; eGFR + ACR support CKD progression assessment.
- **Plan section**: references `CarePlan/cp002-01` in entry; narrative summarises plan + cites nephrology referral guideline.

**Expected p50 latency** ≤ 30s (acceptance test #8).

### P3 — Polypharmacy (10 meds, 3 known DDIs, depression + Parkinson's combo)

**Demographics**

| Field | Value |
|---|---|
| Patient id | `p003` |
| Name | บุญส่ง กิตติชัย |
| Gender | male |
| birthDate | 1951-02-14 (age 75) |
| Address | นนทบุรี 11000 |
| Citizen ID identifier | use TH citizen-id slice |

**Active Conditions (6)**

| id | system | code | display | recordedDate | sensitivity |
|---|---|---|---|---|---|
| `c003-01` | ICD-10-TM | I10 | Essential hypertension | 2009-01-10 | |
| `c003-02` | ICD-10-TM | E11.40 | T2DM with neuropathy | 2014-05-22 | |
| `c003-03` | ICD-10-TM | F32.1 | Moderate depressive episode | 2026-02-10 (recent) | **sensitive PII (mental health)** |
| `c003-04` | ICD-10-TM | G20 | Parkinson's disease | 2020-08-30 | |
| `c003-05` | ICD-10-TM | M81.0 | Postmenopausal osteoporosis | 2022-03-15 | (note: coded incorrectly for male — fixture intentionally tests skill robustness; LLM should still include it without remarking) |
| `c003-06` | ICD-10-TM | K21.0 | GERD with oesophagitis | 2024-07-12 | |

**Active Medications (10)**

| id | drug | TMT | dose | adherence | DDI flag |
|---|---|---|---|---|---|
| `m003-01` | Enalapril maleate | 100123 | 10mg QD | taking | |
| `m003-02` | Metformin HCl | 100445 | 1000mg BID | **intermittent** (forgetful per family) | high-value signal |
| `m003-03` | Gliclazide MR | 100912 | 30mg QD | taking | |
| `m003-04` | Sertraline HCl | 101023 | 50mg QD | taking | ⚠ DDI A |
| `m003-05` | Levodopa/Carbidopa | 101134 | 100/25mg TID | taking | |
| `m003-06` | Alendronate Na | 101245 | 70mg QW | taking | ⚠ DDI B (timing) |
| `m003-07` | Calcium carbonate | 101356 | 600mg BID | taking | ⚠ DDI B (timing) |
| `m003-08` | Cholecalciferol | 101467 | 1000 IU QD | taking | |
| `m003-09` | Omeprazole | 101578 | 20mg QD | taking | ⚠ DDI C |
| `m003-10` | Gabapentin | 101689 | 100mg TID | taking | ⚠ DDI A |

**Expected DDIs returned by `drug_interaction_check` (≥3, severity ≥ moderate)**

| Pair | Severity | Mechanism | Recommendation |
|---|---|---|---|
| **A:** Sertraline ↔ Gabapentin | moderate | additive CNS depression in elderly | monitor sedation, fall risk |
| **B:** Calcium ↔ Alendronate | major (timing) | chelation reduces alendronate absorption | separate ≥30 min; alendronate first AM, calcium later |
| **C:** Omeprazole ↔ Sertraline | moderate | CYP2C19 inhibition increases sertraline level | monitor for serotonin signs; consider PPI taper |

**Allergies (1)**

| id | code | severity | reaction |
|---|---|---|---|
| `a003-01` | Sulfonamides (RxNorm 10180) | moderate | rash 2008 |

**Recent vital signs (encounter 2026-05-10)**

| code | value |
|---|---|
| BP | 138/85 mmHg |
| HR | 68 /min |
| Weight | 58 kg |
| BMI | 22.0 |

**Recent labs (last 90 days, 5 results)**

| date | code | value | interpretation |
|---|---|---|---|
| 2026-04-08 | HbA1c | 7.1 % | borderline — adherence-sensitive |
| 2026-04-08 | eGFR | 65 mL/min/1.73m² | stage 2 — preserved |
| 2026-04-08 | Vit B12 (2132-9) | 180 pg/mL | **deficient** — chronic Metformin sequela |
| 2026-04-08 | TSH (3016-3) | 2.4 mIU/L | normal |
| 2026-04-08 | 25-OH Vit D (1989-3) | 22 ng/mL | insufficient |

**CarePlan:** none in Bundle (test the `notstarted` + inferred plan narrative).

**Expected skill behaviour**

| Tool | Triggered? | Why |
|---|---|---|
| `openemr_patient_bundle_fetch` | ✅ once | |
| `primekg_disease_relations` | ✅ | 6 chronic conditions; expect DM↔neuropathy↔Gabapentin chain, Parkinson↔depression comorbidity |
| `mimir_drug_search` | ❌ | all 10 meds have TMT codes |
| `drug_interaction_check` | ✅ **mandatory** | 10 meds + adherence concern; must surface all 3 DDIs |
| `evidence_citation_fetch` | ✅ ≤2 calls | Plan recommends Metformin-induced B12 supplementation + adherence counselling — cite ADA + geriatric polypharmacy guideline |

**Expected Composition highlights**

- **Problems narrative**: 6 conditions grouped by chapter (Circulatory: HT; Endocrine: DM; **Mental health: depression** — clinical term only per sensitive-PII rule; Nervous: Parkinson's; Musculoskeletal: osteoporosis — included silently despite coding gender mismatch per rule 14 anti-fabrication; Digestive: GERD). No colloquial mental-health language.
- **Medications narrative**: surfaces Metformin intermittent adherence ("รับประทาน Metformin ไม่สม่ำเสมอตามรายงานของผู้ดูแลครอบครัว"). Surfaces all 3 DDIs from drug_interaction_check inline — phrasing as "consider", "monitor for", "พิจารณา". Notes B12 deficiency in narrative as Metformin sequela.
- **Allergies narrative**: Sulfonamides moderate — recommend SMX/TMP avoidance.
- **Vitals narrative**: notes BP at goal for non-CKD elderly; low BMI flagged.
- **Results narrative**: B12 deficiency flagged as **clinically actionable** (linked to Metformin in narrative).
- **Plan section**: `emptyReason=notstarted`; narrative summarises: continue Parkinson regimen, supplement B12, separate Ca/alendronate timing, geriatric polypharmacy review at next visit. Cites guidelines for B12 + polypharmacy.
- **Confidentiality**: defaults `N`. If host signals R for mental-health flag → upgrade to `R`. (Phase 1 demo: leave `N`, document in narrative without sensitive specifics.)

**Expected p50 latency** ≤ 45s (longer than P2 due to 4 tool calls + 10 meds + DDI processing).

### Fixture validation rules

Before each demo run:

1. Each fixture script must produce a Bundle that passes the input contract schema (§4)
2. Resource IDs must be deterministic (re-running script produces same IDs)
3. Each fixture must exercise at least one rule from §Edge cases in the skill body
4. P2 + P3 together must exercise every tool in §4a at least once across the two patients
5. No two fixtures may share a Patient.id (avoid Tyr audit collision)

Edge-case coverage matrix:

| Edge case (skill body §Edge cases) | P1 | P2 | P3 |
|---|---|---|---|
| Conflicting data | — | — | (add 2nd BP same day for fixture variation) |
| Stale data | — | — | — |
| Negation-coded data (refuted Condition) | — | (add refuted GERD for fixture variation) | — |
| Empty Bundle | tested separately as P0 fixture | — | — |
| Sensitive PII | — | — | ✅ depression |

Add **P0** (empty-Bundle fixture, Patient-only) as a 4th fixture purely for refusal-path testing — does not generate Composition but emits `{"error": "input_bundle_invalid"}` per rule 15.

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