# ADR-018: CDS and CQM as Eir Agent Families

**Status:** Proposed
**Date:** 2026-05-26
**Deciders:** paripol@megawiz.co
**Scope:** Establishes that real-time Clinical Decision Support (CDS Hooks) and retrospective Clinical Quality Measures (FHIR `Measure`) are implemented as two distinct Eir agent families — `eir-cds-*` and `eir-cqm` — running on the existing Eir agent registry, consuming `mimir-fhir` via Hermodr MCP tools. Closes the agent-design gap left open by Sprint 59 CDS plan and previous CQM discussion.
**Related:** [ADR-010](ADR-010-agents-as-boundaries-skills-as-expertise.md), [ADR-013](ADR-013-fhir-r5-canonical-version.md), [ADR-014](ADR-014-fhir-data-plane-ownership.md), [ADR-017](ADR-017-fhir-r4r5-translation-framework.md)

## Context

Two clinical AI surfaces have been designed separately:

1. **CDS** (real-time, point-of-care) — Sprint 59 plan proposes `eir-cardio-cds` as a single agent variant for HTN + dyslipidemia. The scope is too narrow: CDS Hooks fires for many specialties (cardio, endocrine, infectious, paeds, etc.) and needs a routing layer plus specialty variants.

2. **CQM** (retrospective, scheduled) — earlier discussion placed CQM under Bifrost cron + Mimir Well without naming an agent owner. CQM produces FHIR `MeasureReport` plus a Thai-language clinical narrative; both require LLM reasoning over guideline + population data, which is Eir's expertise per [ADR-010](ADR-010-agents-as-boundaries-skills-as-expertise.md).

Without an architectural lock, three risks compound:

- Sprint 59 ships `eir-cardio-cds` as a one-off, then later sprints have to retroactively split a router out and rename. Naming churn.
- CQM gets implemented as ad-hoc Python in Bifrost without an agent envelope, breaking the principle in [ADR-014](ADR-014-fhir-data-plane-ownership.md) that Layer 2 reasoning lives in Eir, not Bifrost.
- CDS and CQM diverge in tool catalog, audit shape, and provenance linkage — even though they need the same FHIR + guideline grounding.

This ADR locks the family structure before Sprint 59 (CDS) and the not-yet-numbered CQM sprint begin.

## Decision

CDS and CQM are two Eir agent families with distinct shape but shared substrate:

```
eir-cds-router   ──→ eir-cds-cardio   ───┐
                  ├─→ eir-cds-endo     ──┤
                  ├─→ eir-cds-pulmo    ──┤  Hermodr fhir_* tools
                  ├─→ eir-cds-paeds    ──┼─→  mimir-fhir REST
                  ├─→ eir-cds-id       ──┤  S55 guideline lineage
                  └─→ eir-cds-general  ──┘

eir-cqm          ──────────────────────────┘
  (measure-agnostic, parameterized by FHIR Measure resource ID)
```

### D1. CDS = specialty fan-out, CQM = measure-agnostic singleton

**CDS family** (`eir-cds-*`):

- One agent per specialty, cloned from existing specialty agents (`eir-cardio` → `eir-cds-cardio`, etc.) with CDS Card-shaped output preamble and CDS-specific tool allowlist.
- A router agent `eir-cds-router` reads the FHIR context bundle from the CDS Hook payload and dispatches to one specialty agent.
- Mirrors the existing `eir-router` → specialty pattern from the Eir agent registry (`agent_configs` table).

**CQM family** (`eir-cqm`):

- Single agent, parameterized by FHIR `Measure` resource ID + reporting period.
- The agent loads the `Measure` definition and `Library` (CQL) at runtime via Hermodr, computes population counts via FHIR Bulk Data, and generates the narrative.
- No specialty fan-out: a single agent that switches behavior based on the measure definition is simpler than dozens of per-measure agents that all do roughly the same thing.

Why the asymmetry: CDS needs specialty depth because the decision logic is specialty-bespoke (cardio guidelines differ structurally from paeds vaccine schedules). CQM logic is structurally identical across measures — denominator / numerator / exclusion — so it's a parameter, not a specialty.

### D2. Output contracts

| Family | Trigger | Output |
|---|---|---|
| `eir-cds-*` | CDS Hooks 2.0 service endpoint (Bifrost) | CDS Card JSON (summary + indicator + suggestions + `link.url` to S55 `PlanDefinition`) |
| `eir-cqm` | Bifrost cron via `bifrost-jobs` runtime | FHIR `MeasureReport` resource + Thai narrative `Composition` resource |

Both outputs are FHIR-shaped — no proprietary envelopes. CDS Cards conform to the CDS Hooks 2.0 spec; MeasureReports conform to the FHIR R5 Clinical Reasoning module.

### D3. Local LLM mandatory

Both families MUST use local LLM only — `gemma-4-26b-it-4bit` (current local Mimir-Eir baseline champion) or `medgemma-27b` when proven competitive. Cloud LLM is banned for all Eir-family agents on `asgard_medical` tenant.

CQM running batch does not weaken this rule: the on-prem Mac mini constraint applies to all `asgard_medical` workloads regardless of latency tolerance.

### D4. Skuggi gate mandatory pre-LLM

Both families route FHIR context bundles through Skuggi (Heimdall in-process Rust middleware, W1 Text Tier 1 shipped per ADR-007) before LLM invocation. Citizen IDs are hashed; names are preserved because clinical reasoning needs the patient identity within the session. Phone, non-clinical addresses, and email are masked.

CQM gets an additional aggregation guard: the agent processes patient batches with per-patient Skuggi pre-pass, but the output `MeasureReport` is population-level (numerator counts, not patient lists). Patient-level linkage in the narrative is forbidden — only aggregate findings.

### D5. Tool allowlists

| Tool | `eir-cds-*` | `eir-cqm` |
|---|---|---|
| `fhir_patient_summary` | ✓ | — |
| `fhir_active_medications` | ✓ | — |
| `fhir_active_conditions` | ✓ | — |
| `fhir_recent_observations` | ✓ | — |
| `fhir_allergy_intolerance` | ✓ | — |
| `fhir_immunization_status` | ✓ (paeds variant) | — |
| `fhir_encounter_history` | ✓ | — |
| `fhir_check_codes` | ✓ | ✓ |
| `fhir_measure_definition` (NEW) | — | ✓ |
| `fhir_population_query` (NEW) | — | ✓ |
| `mimir_guideline_lookup` | ✓ | ✓ |
| `primekg_drug_interaction` | ✓ | — |

CQM adds two new Hermodr tools that must be specified before the CQM sprint begins (separate spec doc, not in this ADR):

- `fhir_measure_definition(measure_id) → { population_criteria, numerator_expr, denominator_expr, library_cql }`
- `fhir_population_query(measure_id, period, group_by) → { denominator_count, numerator_count, exclusion_count, by_group }`

### D6. Provenance and audit

Both families emit Living Evidence provenance:

- CDS Card: `link.url` to S55 `PlanDefinition` (the guideline excerpt that supported the recommendation)
- CQM MeasureReport: `extension` containing S55 `Measure` resource version + S56 Mimir Well episodic memory record ID for the run

Tyr receives events:
- `cds.decision.emitted` (per Card) with patient hash + agent name + tool calls + LLM model + latency
- `cqm.run.completed` (per MeasureReport) with measure ID + period + counts + duration

### D7. Bifrost runtime placement

- CDS uses `bifrost-agent` (live sessions, SSE-streamable, low latency target <3s p95)
- CQM uses `bifrost-jobs` (cron-scheduled batch runtime)

The same Eir agent body can be invoked by either runtime because Eir agents are pure functions of `(prompt, tools, context) → response` per [ADR-010](ADR-010-agents-as-boundaries-skills-as-expertise.md). The runtime difference is in trigger + envelope only.

### D8. Naming compliance

Both families honor the established naming convention: no new Norse-named components; submodules use plain-English `<parent>-<submodule>` form. `eir-cds-*` and `eir-cqm` follow that pattern directly. The `eir-cds-router` mirrors the existing `eir-router` convention exactly.

## Why this structure over alternatives

| Alternative | Reason rejected |
|---|---|
| Single `eir-clinical` agent with mode flag (cds | cqm) | Mode flag explodes the system prompt; output shapes are FHIR-incompatible; tool allowlists diverge sharply |
| CDS and CQM as Bifrost-internal Python (no Eir agent) | Violates ADR-014 (Layer 2 reasoning lives in Eir); loses local LLM substitution; loses Tyr audit consistency with other Eir agents |
| Per-measure CQM agents (`eir-cqm-htn`, `eir-cqm-dm`, ...) | FHIR Measure is the parameter, not the agent — would duplicate 90% of the prompt per measure |
| Per-specialty CQM agents | CQM logic is structurally measure-driven, not specialty-driven; specialty fan-out doesn't add information |
| Single-specialty CDS (no router) for Sprint 59 only | Sprint 59 retro would force router extraction; cheaper to add router now even if specialty count = 2 (cardio, dyslipidemia) |

## What we explicitly do NOT do

| Tempting choice | Reason rejected |
|---|---|
| Use cloud LLM for CQM batch (no latency pressure) | Violates the Eir local-LLM-only rule. The rule is about data residency for `asgard_medical`, not latency. |
| Embed CQL execution in Eir agent prompt | CQL is deterministic logic — execute in `mimir-fhir` (FHIR Clinical Reasoning module) and pass results to Eir for narrative generation only |
| Allow CDS Card to reference patient identifiers in `link.url` | Provenance links go to guideline resources only, never to patient resources — Skuggi guard |
| Let `eir-cqm` emit patient-level findings in the narrative | Population-level only; per-patient drill-down is a separate authenticated request, not part of the MeasureReport |

## Consequences

**Positive:**

- Clean alignment with existing Eir agent registry pattern — no new infrastructure
- Specialty fan-out for CDS sets up subsequent CDS sprints (S60+ for ID, endo, pulmo) without architectural churn
- CQM measure-agnostic design means adding a new HEDIS / MIPS / Thai NHSO measure is a database insert + Measure resource publish, not an agent build
- Both families share the Hermodr `fhir_*` MCP tool catalog — no duplicate development
- Provenance + audit symmetry means one Tyr dashboard can show both surfaces

**Negative:**

- Sprint 59 scope expands slightly: from one agent (`eir-cardio-cds`) to router + 2 specialty agents (`eir-cds-router`, `eir-cds-cardio`, `eir-cds-dyslipidemia`). Adds ~3 days.
- CQM sprint cannot start until Hermodr ships `fhir_measure_definition` + `fhir_population_query` (currently unspec). Spec must precede sprint.
- Local LLM constraint on CQM batch means slower aggregation runs; mitigated by overnight scheduling

**Neutral / TBD:**

- Whether `eir-cds-router` is itself an LLM agent or a rules-based dispatcher — defer to Sprint 59 Phase 1 detail design. A small classifier model is cheaper if the routing decision is well-bounded by specialty codes.
- Whether to expose CQM results directly to clinicians or restrict to QI / administrator role — defer to UI sprint after CQM ships.

## Sprint impact

| Sprint | Change |
|---|---|
| **Sprint 59 (CDS pilot)** | Expand from `eir-cardio-cds` single agent to `eir-cds-router` + `eir-cds-cardio` + `eir-cds-dyslipidemia`. +3 days. Output: working CDS Hooks service with HTN + dyslipidemia coverage. |
| **Sprint 60 (proposed: CDS expansion)** | Add `eir-cds-endo`, `eir-cds-paeds`, `eir-cds-id` after Sprint 59 production validation. |
| **Sprint TBD (CQM pilot)** | Pre-req: Hermodr ships `fhir_measure_definition` + `fhir_population_query` tools. First measure: HbA1c <7% rate (NHSO P4P-relevant). |

## Validation criteria

This ADR is validated when:

- [ ] `agent_configs` rows exist for `eir-cds-router`, `eir-cds-cardio`, `eir-cds-dyslipidemia`, `eir-cqm`
- [ ] Sprint 59 ships CDS Hooks service end-to-end with router → specialty dispatch working
- [ ] At least one CDS Card includes a verifiable `link.url` to a S55 PlanDefinition
- [ ] CQM sprint demonstrates one MeasureReport produced from FHIR Measure resource + Thai narrative
- [ ] Tyr dashboard shows both `cds.decision.emitted` and `cqm.run.completed` events
- [ ] Both families confirmed local-LLM-only in `ai_models` allowlist (no gemini/anthropic models permitted)
- [ ] Skuggi gate logs visible for both families in Tyr

## References

- [ADR-010](ADR-010-agents-as-boundaries-skills-as-expertise.md) — Agents as boundaries, skills as expertise
- [ADR-013](ADR-013-fhir-r5-canonical-version.md) — R5 canonical lock
- [ADR-014](ADR-014-fhir-data-plane-ownership.md) — FHIR data plane ownership
- [ADR-017](ADR-017-fhir-r4r5-translation-framework.md) — R4↔R5 translation framework
- CDS Hooks 2.0 spec — https://cds-hooks.org
- FHIR R5 Clinical Reasoning module — http://hl7.org/fhir/R5/clinicalreasoning-module.html
- Agent registry — `Mimir/scripts/recover-asgard-tenant.sql` (clone pattern)
- CDS Hooks 2.0 spec — https://cds-hooks.org/
- Hermodr FHIR MCP catalog spec — to be added at `docs/architecture/hermodr-fhir-mcp-catalog.md`
- Sprint 59 CDS plan — to be migrated to `docs/sprint-planning/sprint-59-cds-pilot.md`
- Living Evidence positioning — `docs/strategy/living-evidence-positioning.md`