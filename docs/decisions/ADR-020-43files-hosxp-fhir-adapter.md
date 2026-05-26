# ADR-020: 43Files / HOSxP → FHIR Adapter Architecture and Sync Strategy

**Status:** Proposed
**Date:** 2026-05-26
**Deciders:** paripol@megawiz.co
**Scope:** Locks the architecture, scope, sync strategy, identity model, data quality discipline, and sprint phasing for the Phase 1 43Files / HOSxP → FHIR adapter (`mimir-43files-adapter`). Unblocks Sprint 8.
**Related:** [ADR-006](ADR-006-fhir-canonical-design.md), [ADR-013](ADR-013-fhir-r5-canonical-version.md), [ADR-014](ADR-014-fhir-data-plane-ownership.md), [ADR-016](ADR-016-asgard-fhir-profile-family.md), [ADR-017](ADR-017-fhir-r4r5-translation-framework.md), [ADR-019](ADR-019-fhir-profile-validation-tightest-binding-wins.md)

## Context

The 43Files dataset (43 แฟ้ม) is the Thai Ministry of Public Health's mandated reporting standard — 43 relational tables that every Thai hospital submits monthly. HOSxP, the dominant Thai HIS (≈60-70% market share), stores its operational data directly in the 43Files schema. "Reading HOSxP" therefore means reading 43Files-shaped MariaDB tables.

For Asgard to function inside a Thai hospital, it must ingest from HOSxP without disrupting hospital operations. This means: read-only access, eventual consistency, idempotent retries, and resilience to schema variance across HOSxP versions (3.x / 4.x / Standard / Premier).

Sprint 8 is the largest sprint in Phase 1 because the adapter spans 12 priority tables × ~200 fields × code-system translation × identity reconciliation × sync infrastructure × encoding/date normalisation. Without a locked architecture, the sprint risks scope creep into Sprint 9 (Smart-on-FHIR), or arrival at hospital sites with silent data-quality gaps.

This ADR locks the design before Sprint 8 begins.

## Decision

Build `mimir-43files-adapter` as a separate Rust crate that ingests 12 priority HOSxP tables, translates them into 11 Asgard FHIR Profile resource types, and writes through the `mimir-fhir` REST API with full profile validation. Sync defaults to polling; CDC via Debezium is an opt-in upgrade.

### D1. Crate placement and naming

- Crate: `mimir-43files-adapter`
- Depends on: `mimir-fhir` (FHIR types + REST client + profile validators)
- Family: `mimir-*` per the established submodule pattern (no new Norse names)
- Repository layout: `crates/mimir-43files-adapter/` alongside `crates/mimir-fhir/`

The adapter is a **separate crate**, not a module of `mimir-fhir`. Rationale: clear boundary (FHIR types vs HOSxP ingest), independent test corpus, optional dependency (deployments without HOSxP can omit it), and reusability for future MOPH-format consumers (PC2, NHSO E-claim).

### D2. Phase 1 table scope — 12 priority tables → 11 FHIR resources

| Tier | HOSxP Table(s) | FHIR Resource(s) |
|---|---|---|
| 1 | PERSON + HOME + ADDRESS | Patient |
| 1 | SERVICE | Encounter (ambulatory) |
| 1 | ADMISSION + DISCHARGE_IPD | Encounter (inpatient) |
| 1 | DIAGNOSIS_OPD + DIAGNOSIS_IPD | Condition |
| 2 | DRUG_OPD + DRUG_IPD | MedicationRequest + MedicationStatement |
| 2 | DRUG_ALLERGY | AllergyIntolerance |
| 2 | PROCEDURE_OPD + PROCEDURE_IPD | Procedure |
| 2 | LABFU | Observation (lab) + DiagnosticReport |
| 2 | NCDSCREEN | Observation (vital signs, 8 sub-profiles) |
| 3 | EPI | Immunization |
| 3 | INSURANCE | Coverage |

Explicitly deferred to Sprint 8.5 or later:

- CHARGE_OPD / CHARGE_IPD → Claim (waits for Sprint 5 Claim resource stabilisation)
- DEATH → Patient.deceased + Observation
- SURGERY → Procedure (subset of PROCEDURE_*; not additive)
- ANC, APPOINTMENT, MENTAL_HEALTH, FAMILY_PLANNING, ~25 other tables (specialty / population-health datasets)

Field-level mapping detail lives in `docs/architecture/43files-fhir-mapping-matrix.md` (companion to [moph_pc1_fhir_mapping.md](../architecture/moph_pc1_fhir_mapping.md)).

### D3. Identity model — stable UUID, multi-identifier preservation

Asgard's `Patient.id` is a **stable UUID** derived as:

```
patient_uuid = uuid_v5(
    namespace = ASGARD_NS,
    name = "{hospital_id}|{cid_or_hn_fallback}"
)
```

- If `PERSON.CID` is a valid 13-digit Thai citizen ID → use CID
- Else fallback to `PERSON.HN` with identifier type `MR`
- `hospital_id` is the Asgard-assigned hospital identifier (set at deployment, immutable)

All native HOSxP identifiers are preserved in `Patient.identifier[]`:

| HOSxP source | FHIR slice | system URL |
|---|---|---|
| `CID` | `identifier[slice=citizenId]` | `https://fhir.moph.go.th/identifier/citizen-id` |
| `HN` | `identifier[slice=hn]` | `https://fhir.asgard.megawiz.co.th/identifier/{hospital_id}/hn` |
| `PID` | `identifier[slice=pid]` | `https://fhir.asgard.megawiz.co.th/identifier/{hospital_id}/pid` |
| Asgard UUID | `identifier[slice=asgard]` | `https://fhir.asgard.megawiz.co.th/identifier/uuid` |

Cross-hospital patient matching is **not attempted** in Phase 1. Each hospital deployment maintains its own UUID namespace. Two `Patient` resources at two hospitals with the same CID will have different `Patient.id` and are treated as separate logical patients. Future cross-hospital MPI work is out of scope.

For non-Patient resources, `id` is `uuid_v5(namespace=ASGARD_NS, name="{hospital_id}|{table}|{source_pk}")`. Re-ingesting the same row regenerates the same UUID → upsert no-op (idempotency).

### D4. Sync strategy — polling default, CDC opt-in

Two sync modes are supported:

| Mode | Trigger | Latency | DBA access requirement |
|---|---|---|---|
| Polling (default) | Cron every 5 min: `SELECT ... WHERE update_datetime > last_sync` | 5 min p95 | Read-only user with SELECT on the 12 tables |
| CDC (opt-in upgrade) | Debezium reads MariaDB binlog → Kafka/NATS → consumer | 1-5 sec p95 | Binlog access + replication user |

**Polling is default** because most Thai hospital DBAs are unwilling to grant binlog access without significant deliberation. Polling works on a vanilla read-only user. CDC is offered as an upgrade path for hospitals where ≤5 sec latency materially improves a use case (real-time CDS during prescribing).

Initial deployment runs a **snapshot** pass over all 12 tables to backfill historical data (1-5 years typical), then enters polling or CDC steady-state.

Sync state (last polling timestamp per table, CDC offset, snapshot completion markers) lives in `mimir_43files_sync` table in Asgard MariaDB, not in HOSxP DB. The adapter is a strict consumer of HOSxP; it never writes back.

### D5. Code system bridging

| HOSxP field | Source code system | FHIR binding |
|---|---|---|
| `DRUG_OPD.DIDSTD` | TMT (Thai Medication Terminology) | pass-through, system=`https://terminology.moph.go.th/CodeSystem/tmt` |
| `DIAGNOSIS_*.ICD10` | ICD-10-TM | pass-through, system=`https://terminology.moph.go.th/CodeSystem/icd10-tm` |
| `PROCEDURE_*.ICDCM` | ICD-9-CM or ICD-10-PCS (varies by HOSxP version) | pass-through with version flag in extension |
| `LABFU.LABCODE` | local hospital lab code | **bridge required** — lookup in Mimir KB `lab_code_bridge` table → LOINC |
| `NCDSCREEN.BPS/BPD/HEIGHT/WEIGHT/...` | numeric measurements | bind to LOINC vital-signs codes by field |
| `INSURANCE.INSCL` | MOPH insurance class code | bind to ValueSet `moph-insurance-class` |
| `EPI.VACCINETYPE` | local vaccine code | **bridge required** — Mimir KB `vaccine_code_bridge` → CVX or MOPH official |

Unmapped codes emit `fhir.ingest.unmapped_code` Tyr event with HOSxP code, hospital_id, and FHIR field path. The Mimir Curator queue surfaces these for human review per the existing curator workflow. The adapter does not block on unmapped codes — it emits the resource with `coding.code` set and `coding.system=urn:asgard:unmapped` until the bridge is filled.

### D6. Encoding and date normalisation

**Encoding:** HOSxP databases use TIS-620 or UTF-8 depending on age. The adapter auto-detects encoding per column (TIS-620 byte patterns are statistically distinguishable from UTF-8). Internal canonical is UTF-8.

**Buddhist year detection:** HOSxP date columns sometimes contain Buddhist Era years (year + 543). Auto-detection rule:

- If `year > 2500` → assume Buddhist → subtract 543
- If `year < 2400` → assume Gregorian → pass through
- If `2400 ≤ year ≤ 2500` → ambiguous → emit `fhir.ingest.date_ambiguous` Tyr event, default to Gregorian, flag for Curator review

A second sanity check: `PERSON.BIRTH` is cross-validated against `PERSON.AGE` if present. Mismatch > 1 year emits `fhir.ingest.date_inconsistent`.

### D7. Idempotency and retry

Every resource emitted by the adapter carries a deterministic UUID per [D3](#d3-identity-model--stable-uuid-multi-identifier-preservation). Re-ingesting the same HOSxP row produces the same UUID and the same resource body byte-for-byte (modulo timestamps). `mimir-fhir` REST treats this as an upsert.

The adapter implements exactly-once-effectively semantics via:

- Stable UUID → at-most-once write logically
- Retry on transport failure (exponential backoff up to 5 retries) → at-least-once attempt
- Dead-letter queue after retry exhaustion → manual reconciliation via Curator

### D8. Profile validation is mandatory pre-store

Every translated resource passes through the ADR-019 validators before `mimir-fhir` stores it. A resource that fails validation at severity ≥ `Error`:

- Is NOT stored
- Emits `fhir.ingest.validation_failed` Tyr event with full `ValidationReport`
- Routes to the Curator dead-letter queue for human review or mapping fix

A resource with only `Warning`-severity issues is stored but the warning is logged. Hospital data quality is reflected in Tyr dashboards over time.

This is the architectural guarantee that the Asgard canonical store never contains a profile-violating resource — even if the HOSxP source has data quality issues.

### D9. Data quality reporting

The adapter emits `fhir.ingest.quality.*` Tyr events at batch boundaries:

- Per-batch summary: total rows read / resources emitted / validation failures / unmapped codes / encoding fixes / date ambiguities
- Per-table 24h rollup: ingestion rate, error rate, latency p50/p95/p99
- Per-hospital weekly report: data quality trend, top unmapped codes, recommended Curator priorities

The customer-facing dashboard (built later) consumes these. Customers see data quality without raw PHI exposure (citizen IDs are SHA-256 hashed in events per existing Skuggi policy).

### D10. Performance target

Sprint 8 commits to **≥100 resources/sec** sustained ingest on the Mac mini M2 baseline, end-to-end (HOSxP read → translate → validate → mimir-fhir store). This is conservative — a 100k-resource backfill completes in ≤17 minutes.

Higher throughput (≥1000 resources/sec) is a Sprint 8.5+ optimization candidate. Initial bottleneck is likely profile validation (≥1000 r/s per ADR-019) plus REST round-trip; both can be batched in a Phase 2 optimization pass.

## Why this architecture over alternatives

| Alternative | Reason rejected |
|---|---|
| Embed adapter inside `mimir-fhir` | Couples FHIR types to HOSxP ingest; deployments without HOSxP get unwanted code; testing becomes intertwined |
| CDC-only sync (no polling) | Requires binlog access; most Thai hospital DBAs decline; would block initial deployments |
| Polling-only sync (no CDC) | Real-time CDS use case needs <5s latency; CDC opt-in path preserves option |
| Write directly to MariaDB / Neo4j (bypass mimir-fhir REST) | Skips profile validation, audit, future API authentication; introduces a second write path |
| Attempt cross-hospital MPI in Phase 1 | Identity matching is a hard problem with regulatory implications; defer until customer demand + governance framework |
| Map all 43 tables in Sprint 8 | Sprint 8 would balloon to 8+ weeks; 12 tables cover the documented use cases (UC1 OPD HT/DM, UC3 paeds vaccine) |
| Hot-reload mapping configuration | Mapping changes are profile-bearing — they need the same compile-time discipline as profiles (ADR-019) |

## What we explicitly do NOT do

| Tempting choice | Reason rejected |
|---|---|
| Write back to HOSxP DB | Asgard is read-only on HOSxP; any future writeback requires a separate ADR + hospital legal review |
| Maintain HOSxP schema variant matrix in Phase 1 | Phase 1 targets HOSxP 4.x Standard; other variants (3.x, Premier) deferred to Sprint 8.5 |
| Build a UI for mapping configuration | Mapping is code; visual configuration introduces drift between display and execution |
| Sync charges/billing in Phase 1 | Billing has regulatory complications (NHSO E-claim format, hospital revenue cycle); defer to dedicated sprint |
| Allow non-validated resources into canonical store under "permissive mode" | Defeats the audit guarantee; data quality should be visible, not papered over |

## Consequences

**Positive:**

- Bounded sprint scope (12 tables → 11 resources) — predictable 4-week duration
- Adapter is a separate optional crate — deployments without HOSxP omit it cleanly
- Idempotent design — backfill is safely re-runnable; retry is built in
- Profile validation gate — canonical store never contains invalid resources
- Tyr quality events — customer dashboard, regulator-traceable, no PHI exposure
- Polling default keeps initial onboarding low-friction; CDC available for hospitals that want it
- Buddhist year + TIS-620 handled at adapter boundary, not bleeding into FHIR canonical

**Negative:**

- Sprint 8 is still the largest sprint (4 weeks vs 1-2 for others); risk of scope pressure to defer
- Unmapped lab/vaccine codes go to Curator queue — operational dependency on Curator throughput
- Polling adds 5-minute lag to data freshness; CDS use cases at hospitals on polling-only see this latency
- HOSxP schema variance (3.x vs 4.x vs Premier) is a Sprint 8.5 problem; Phase 1 targets 4.x Standard only
- Cross-hospital MPI explicitly deferred — any pitch involving "merge patient records across hospitals" must be reframed for Phase 1

**Neutral / TBD:**

- Whether to ship a CLI tool for one-shot snapshot ingest (`asgard-43files-snapshot --since 2020-01-01`) — defer to Sprint 8 detail design
- Whether the adapter exposes a `/status` HTTP endpoint for ops monitoring or relies on Tyr events only — defer to Sprint 8 detail design
- Future PC2 / NHSO E-claim adapters: reuse same crate pattern? — likely yes, but no ADR commitment until customer ask materialises

## Sprint 8 deliverables

| Week | Days | Focus | Output |
|---|---|---|---|
| 1 | 1-2 | This ADR accepted; `crates/mimir-43files-adapter` scaffold; HOSxP schema sqlx types | Crate compiles, types match HOSxP 4.x Standard DDL |
| 1 | 3-5 | `map/person.rs` → Patient (bilingual name, 4-level address, CID slice, stable UUID) | Patient mapper + 50 synthetic golden cases passing validators |
| 2 | 6-8 | `map/service.rs` + `map/admission.rs` → Encounter (R5 actualPeriod, admission BackboneElement) | Encounter mappers + 30 cases |
| 2 | 9-10 | `map/diagnosis_*.rs` → Condition | Condition mappers + 20 cases |
| 3 | 11-13 | `map/drug_*.rs` → MedicationRequest + MedicationStatement (R5 adherence derive); `map/drug_allergy.rs` → AllergyIntolerance | 3 mappers + 40 cases |
| 3 | 14-15 | `map/labfu.rs` + `map/ncdscreen.rs` + `map/procedure_*.rs` (LOINC bridge lookup, vital-signs sub-profiles) | 4 mappers + 30 cases |
| 4 | 16-17 | `sync/poll.rs` + `sync/cdc.rs` + `idempot/upsert.rs` | Sync drivers integration test |
| 4 | 18 | `map/epi.rs` → Immunization; `map/insurance.rs` → Coverage | 2 mappers + 15 cases |
| 4 | 19 | `quality/` Tyr emitter + retry + dead-letter | Quality events live, ops runbook |
| 4 | 20 | E2E against synthetic HOSxP DB (100 patients × 5y); benchmark ≥100 resources/sec; PR ready | Green CI, perf baseline, ADR validation done |

## Validation criteria

This ADR is validated when:

- [ ] `mimir-43files-adapter` crate exists, depends on `mimir-fhir`, compiles cleanly
- [ ] 12 priority tables are read via sqlx; types match HOSxP 4.x Standard DDL byte-for-byte
- [ ] 11 mappers emit resources that pass ADR-019 profile validators (no profile violations in golden corpus)
- [ ] Stable UUID generation is deterministic — re-running snapshot yields identical UUIDs
- [ ] Polling sync demonstrates 5-minute end-to-end latency on synthetic load
- [ ] CDC sync (opt-in path) demonstrates ≤5-second latency on synthetic load
- [ ] Encoding auto-detect correctly normalizes TIS-620 in test corpus
- [ ] Buddhist year auto-detect correctly converts dates with year > 2500
- [ ] At least one synthetic `fhir.ingest.unmapped_code` event reaches Tyr + Curator queue
- [ ] At least one synthetic `fhir.ingest.validation_failed` event reaches Tyr + dead-letter queue
- [ ] Benchmark sustains ≥100 resources/sec end-to-end on Mac mini M2

## Open questions

1. **HOSxP version target** — confirmed as 4.x Standard for Phase 1. Sprint 8.5 to address 3.x compatibility if a customer needs it.
2. **Snapshot CLI tool** — likely yes; defer detail to Sprint 8 Day 16.
3. **Cross-hospital MPI** — out of scope Phase 1; needs separate ADR when customer asks.
4. **Backwards-compat with PC2 / NHSO E-claim** — same crate pattern likely; no commitment until customer demand.
5. **Hospital DBA access negotiation playbook** — operational doc, not ADR scope; track in `docs/runbooks/hospital-onboarding.md`.

## References

- [ADR-006](ADR-006-fhir-canonical-design.md) — FHIR canonical design
- [ADR-013](ADR-013-fhir-r5-canonical-version.md) — R5 canonical version
- [ADR-014](ADR-014-fhir-data-plane-ownership.md) — FHIR data plane ownership (Mimir family)
- [ADR-016](ADR-016-asgard-fhir-profile-family.md) — Asgard FHIR Profile family
- [ADR-017](ADR-017-fhir-r4r5-translation-framework.md) — R4↔R5 translation framework (sibling discipline)
- [ADR-019](ADR-019-fhir-profile-validation-tightest-binding-wins.md) — Profile validation algorithm
- HOSxP table reference — internal (no public DDL spec; sourced from customer HOSxP installations)
- MOPH 43Files data dictionary — https://mophdc.moph.go.th/index.php (43 แฟ้ม specification)
- TMT (Thai Medication Terminology) — https://terminology.moph.go.th
- ICD-10-TM — https://hcup.moph.go.th
- LOINC — https://loinc.org
- Mapping matrix — `docs/architecture/43files-fhir-mapping-matrix.md` (companion doc)
- Adapter crate — `crates/mimir-43files-adapter/` (Sprint 8)
