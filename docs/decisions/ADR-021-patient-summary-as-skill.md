# ADR-021: Patient Summary is a Skill on `eir-clinical`, Not a Boundary Agent

**Status:** Proposed
**Date:** 2026-05-26
**Deciders:** paripol@megawiz.co
**Scope:** Classifies the UC2 Cross-Encounter Patient Summary (introduced by [ADR-015](ADR-015-add-composition-and-uc2-patient-summary.md)) under the agent-vs-skill framework of [ADR-010](ADR-010-agents-as-boundaries-skills-as-expertise.md). Does not change the resource scope, FHIR profile, or sprint timing established by ADR-015 — only the *registration mechanism* and *audit attribution shape*.
**Depends on:** [ADR-010](ADR-010-agents-as-boundaries-skills-as-expertise.md) **Acceptance** + Bifrost skill-loader runtime existence
**Related:** [ADR-015](ADR-015-add-composition-and-uc2-patient-summary.md), [composition-uc2-patient-summary-spec.md](../technical/composition-uc2-patient-summary-spec.md)

## Context

ADR-015 (2026-05-26) introduced the UC2 patient summary use case and described its execution agent as "`eir-summary` — a DB row in `agent_configs`, model `gemma-4-26b`." That registration pattern follows the **legacy 19-agent roster** documented in [[asgard_agent_registry]] and is consistent with prior Eir specialty work.

[ADR-010](ADR-010-agents-as-boundaries-skills-as-expertise.md) (Proposed, 2026-05-22) replaces the 19-agent roster with **5 boundary agents + N retrievable skills**. Under ADR-010's decision rule:

> Does this specialization change *what the agent may touch / which model / who may access / what it must refuse*?
> **Yes → Agent boundary. No → Skill.**

Patient summary fails the boundary test on every clause:

| Clause | Patient summary | Verdict |
|---|---|---|
| Changes tool ceiling? | No — uses subset of `eir-clinical` tools | Skill |
| Changes model? | No — inherits `gemma-4-26b` | Skill |
| Changes access control? | No — same `asgard_medical` tenant | Skill |
| Changes refusal policy? | No — same safety floor as `eir-clinical` | Skill |

Therefore, **patient summary belongs in the skill registry, not in `agent_configs`** — provided ADR-010 is Accepted.

This ADR resolves the contradiction between ADR-015's `eir-summary` agent terminology and ADR-010's framework, without revisiting the resource-scope or sprint-timing decisions in ADR-015.

## Decision

### D1. Patient summary is the `patient-summary` skill on `eir-clinical`

The execution unit for UC2 is a **skill record** in the skill registry (per ADR-010 §Implementation references → `Bifrost/docs/design/skill-loader-runtime.md`), not a row in `agent_configs`. Skill identity:

| Field | Value |
|---|---|
| `skill_id` | `patient-summary` |
| `host_agent` | `eir-clinical` |
| `version` | `v1` (semver) |
| `description` | "Generate a structured FHIR R5 Composition summarising a patient's active problems, medications, allergies, recent vitals, recent results, and care plan from longitudinal EHR data." — embedded for cosine retrieval |
| `tool_subset` | intersect with `eir-clinical` ceiling: `[openemr_patient_bundle_fetch, primekg_disease_relations, mimir_drug_search, drug_interaction_check, evidence_citation_fetch]` |
| `preamble_fragment` | the skill body specified in [composition-uc2-patient-summary-spec.md](../technical/composition-uc2-patient-summary-spec.md) §5 (the same text formerly described as "`eir-summary` agent preamble") |
| `output_schema_ref` | `Composition-asgard-patient-summary.schema.json` |
| `device_id` | `asgard-patient-summary-skill-v1` |

### D2. `Composition.author` uses two-Device attribution

To preserve ADR-010's separation between agent (boundary) and skill (expertise) in the audit trail, generated Compositions carry **both** identities as authors:

```json
"author": [
  {"reference": "Device/asgard-eir-clinical-v{N}"},
  {"reference": "Device/asgard-patient-summary-skill-v{N}"}
]
```

On clinician attestation (status `preliminary` → `final`), a `Reference(Practitioner)` is appended. The Device entries are not removed — they remain for provenance.

### D3. Skill activation supports both direct invocation and cosine retrieval

UC2 is launched from an explicit "Patient summary" button in the EHR Smart-on-FHIR app — there is no natural-language query to embed. The skill-loader runtime therefore supports two activation paths:

1. **Direct activation** — `?skill=patient-summary` URL parameter or equivalent API field. Bypasses embedding lookup. Used by EHR-button launches.
2. **Cosine retrieval** — for chat-style invocations ("summarise this patient" in free-text agent prompt), the skill-loader embeds the user input and matches against skill `description` embeddings. Used by free-text Bifrost calls.

Both paths converge on the same skill record + composition logic.

### D4. Migration from ADR-015's legacy registration is mechanical

If ADR-015's fallback path was taken (a `agent_configs` row `eir-summary` already exists), migration to skill-mode is:

1. Copy the row's `system_prompt` → skill `preamble_fragment`
2. Copy the row's tool allowlist → skill `tool_subset`
3. Delete the `agent_configs` row
4. Register the skill via the Bifrost skill-loader API
5. Replace any direct-invoke client code (`/agents/eir-summary/invoke`) with skill-activated calls on `eir-clinical` (`/agents/eir-clinical/invoke?skill=patient-summary`)

No data migration is required (Compositions are regenerated on-demand for `status=preliminary`; persisted `final` Compositions retain their `author` array as historical record).

### D5. Sprint 10 demo registration order

Sprint 10 UC2 demo prep order changes:

| Step | Before (ADR-015 only) | After (ADR-015 + ADR-016) |
|---|---|---|
| 1 | Insert `eir-summary` row in `agent_configs` | Verify Bifrost skill-loader runtime is operational |
| 2 | Seed `Device(asgard-eir-summary-v1)` resource | Seed `Device(asgard-eir-clinical-v{N})` + `Device(asgard-patient-summary-skill-v1)` |
| 3 | Wire Bifrost route `/agents/eir-summary/invoke` | Register `patient-summary` skill with `host_agent=eir-clinical` |
| 4 | Demo seed patients + run | Same |

If the skill-loader runtime is not operational by Sprint 10 start, use ADR-015's fallback path (legacy `agent_configs` row) for the demo and execute D4 migration post-Phase-1.

## Why a separate ADR (not an amendment to ADR-015)

- ADR-015 is a resource-scope decision (add Composition + UC2 demo); ADR-016 is a registration-mechanism decision. Different reversibility profiles — ADR-016 can move with ADR-010 changes without re-opening the resource scope question.
- ADR-010 is still Proposed. If it changes shape or is rejected, ADR-016 amends or supersedes independently of ADR-015.
- Cleaner audit trail — the skill-vs-agent shift for patient summary is one quotable decision, not buried in an amendment.

## Consequences

**Positive**

- Patient summary aligns with ADR-010 framework
- Audit trail separates skill identity from boundary agent identity (two Devices in `Composition.author`)
- One less row in `agent_configs` (5 boundary agents instead of 5 + 1 = 6)
- Skill is retrievable for free-text invocations, not only direct button launches
- Long-tail extensibility — specialty-flavoured summaries (cardio, sleep, ent) become composable skills on `eir-clinical`, not new agents

**Negative**

- Adds a hard dependency on the Bifrost skill-loader runtime being operational before Sprint 10
- Doubles `Composition.author` cardinality (two Device entries instead of one) — slight schema noise
- Skill registry must be operational + tested before UC2 demo

**Neutral**

- No change to FHIR profile, JSON schema, output acceptance criteria, sprint timing, or Composition resource design from ADR-015

## Open questions

1. **Skill-loader runtime owner + sprint slot.** Per ADR-010 §Consequences, the skill-loader is "the one net-new component." Need explicit owner + sprint slot before Sprint 10 work begins. If unassigned, fallback path is activated.
2. **Device versioning policy.** Should `Device(asgard-eir-clinical-v{N})` rev when only the skill rev'd? Recommended: independent versioning — agent Device tracks boundary agent changes; skill Device tracks skill changes. Both authors in `Composition.author` capture the composition.
3. ~~**Skill testing harness.** ADR-010 requires a parity test ≥ current quality on specialty-tagged HBp subset before retiring per-specialty agents. Does UC2 patient summary require a similar parity benchmark? Recommended: yes — define a "summary quality" benchmark (section completeness, narrative accuracy, citation correctness) before declaring UC2 demo green.~~ **CLOSED 2026-05-27** — specified in [composition-uc2-patient-summary-spec.md §6b](../technical/composition-uc2-patient-summary-spec.md#6b-eval-harness-closes-adr-021-open-q3). Three-layer harness: machine validation (L1, must pass 100%), LLM-as-judge with 7-dim rubric scored 0–5 (L2, average ≥4.0 + no dim <3.0), human spot-check on 10% monthly (L3). Corpus = P0/P1/P2/P3 fixtures from §5a + §6a. Persisted to Mimir eval per [[primekg_resolver_regression]] pattern. PR gate + nightly drift gate + Sprint 10 demo gate defined.

## Links

- [ADR-010 agents-vs-skills](ADR-010-agents-as-boundaries-skills-as-expertise.md) — framework
- [ADR-015 Composition + UC2](ADR-015-add-composition-and-uc2-patient-summary.md) — resource scope (this ADR refines D4 only)
- [composition-uc2-patient-summary-spec.md](../technical/composition-uc2-patient-summary-spec.md) — design detail
- [[asgard_agent_registry]] — legacy agent-row pattern (used only in fallback path)
- [[feedback_eir_agents_local_only]] — `eir-clinical` (host) must use gemma-4-26b / medgemma / typhoon; skill inherits