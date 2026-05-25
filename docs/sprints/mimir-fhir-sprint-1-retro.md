# Mimir-FHIR Sprint 1 — Retrospective

**Sprint:** 1 — Datatypes Foundation
**Window:** 2026-05-24 → 2026-05-25 (1 calendar day, ~10 productive hours)
**Branch:** `feat/mimir-fhir-phase-1` (pushed to origin)
**Status:** **Complete** — all 10 day-plan items shipped + committed + ~50% pushed
**Companion docs:** [Phase 1 plan](../technical/mimir-fhir-phase-1-plan.md), [implementation steps](../technical/mimir-fhir-implementation-steps.md), [Sprint 0 checkpoint](./mimir-fhir-sprint-0-checkpoint.md)

---

## TL;DR

Sprint 1 was originally planned as **10 sprints × 2 weeks = 20 weeks calendar / 14 productive weeks**. The datatype-foundation portion (Days 1-10) was executed in **~10 hours on a single calendar day** because:

- Datatypes are mostly mechanical (one TDD cycle per primitive / complex type)
- No external blockers (no waiting on hospital data, partner sign-off, infra provisioning)
- ADRs locked the design up front — no architecture indecision mid-implementation
- TDD discipline kept work additive (every commit is a green build)

**Outcomes:**
- 202 tests across 16 suites, all green
- 4 commits on `feat/mimir-fhir-phase-1`, all on top of `main`
- Clippy clean with `-D warnings` (pedantic + clippy::all), `unsafe_code` forbidden
- 30+ datatypes implemented (every primitive + complex needed by 20 R5 resources)
- JSON Schema export pipeline ready for Hermodr MCP tool consumption
- Thai bilingual i18n end-to-end test green

**What's NOT done:**
- The 20 FHIR R5 **Resources** (Patient, Encounter, Observation, etc.) — that's Sprint 2 scope per [Phase 1 plan](../technical/mimir-fhir-phase-1-plan.md)
- REST endpoint, persistence, 43Files adapter, profile validators — Sprint 6-8
- Smart-on-FHIR launch surface — Sprint 9
- UC1 + UC3 demo apps — Sprint 10

## Commit Trail

| Commit | Sprint Day(s) | Scope | Tests | Status |
|---|---|---|---|---|
| `2511127` | 0 + 1-5 | Scaffold + Id/Code/Uri/Url/Markdown/DateTime/Period/ContactPoint/Extension(min)/Address/Coding/CodeableConcept/Identifier/Reference/HumanName | 133 | ✓ pushed |
| `dac2dd3` | 6 | Decimal (wrapper)/Quantity/Money/Range/Ratio | 154 (+21) | ✓ pushed |
| `b3e6066` | 7 | Instant/Annotation/Meta/Narrative/Extension(full polymorphism) | 184 (+30) | ✓ pushed |
| `4ac9a3a` | 8 | schemars derive + JSON Schema export pipeline | 194 (+10) | local — not yet pushed |
| `<TBD>` | 9-10 | i18n bilingual integration test + this retro doc | 202 (+8) | local — not yet pushed |

## What Worked

1. **TDD per type.** Writing the failing test first forced clear thinking about each datatype's grammar / construction rules. Caught at least 5 design oversights that would have surfaced in Sprint 2 integration otherwise (e.g., the Identifier↔Reference cycle, Markdown empty-whitespace-only, Decimal trailing-zero preservation).
2. **Standalone Cargo workspace** (empty `[workspace]` table in mimir-fhir/Cargo.toml). Allowed working in parallel with Session A's syn-regions-stage1 branch without touching `ro-ai-bridge/Cargo.toml workspace.members` while it had uncommitted state. Will promote to workspace member once Phase 1 stabilises.
3. **Per-day commit cadence.** Each commit is a green build with all prior tests passing. Easy to bisect if a future change breaks something.
4. **Strict lints day one.** `clippy::pedantic = warn`, `clippy::all = deny`, `unsafe_code = forbid` in Cargo.toml. Caught doc_markdown / `field_reassign_with_default` / `missing_panics_doc` issues immediately rather than accumulating debt.
5. **Coordination log** (`log-session-status.md`) prevented collisions with Session A working on Iris + Mimir ADR-002 OCR provenance in parallel.
6. **Explicit ADR-006 D5 i18n decision** (plain `String` + `language` field, not LangString newtype) — confirmed correct by Day 9 i18n test working cleanly. No noisy `String` wrappers needed across all 30+ types.

## What Slipped (or had to be adapted)

1. **`Decimal` was originally `pub use rust_decimal::Decimal`.** Day 8 schemars derive failed because `rust_decimal::Decimal` has no `JsonSchema` impl. Refactored to wrapper newtype with manual `JsonSchema` impl + Deref delegation. ~30 LOC added; zero call-site change because FromStr / Display / serde behaviours preserved. **Lesson:** "use external type directly" works until you need a trait the external type doesn't impl — design for wrapper from day one when the type sits at a boundary.
2. **Extension default derive** removed because `Uri` has no `Default` (intentional — Uri must be non-empty). Used a private `Extension::empty(url)` helper + per-variant factories. Slight verbosity but clean.
3. **Annotation default derive** removed for the same reason on `Markdown.text` (required field).
4. **Period reserved for Day 5** but Identifier/HumanName had period TODOs since Day 3/4. The "defer until proper type exists" pattern worked — TODOs were closed in Day 5 alongside Period implementation rather than stubbed earlier.
5. **Pre-existing uncommitted state in Mimir workspace** (Cargo.toml, mimir-core-ai/*, neo4j.rs, dashboard files) — stashed under named tag `pre-mimir-fhir-phase-1 syn-regions WIP` before branching off main. Stash recovery instructions filed in `log-session-status.md` for whoever owns that WIP.

## Design Decisions Made During Sprint

| # | Decision | Captured in |
|---|---|---|
| 1 | FHIR `id` validation at construction + on deserialise (not best-effort) | code + test |
| 2 | Custom `Deserialize` propagates inner validation errors to JSON parse | code + test (`uri_deserialize_validates_inner_uri`) |
| 3 | `Identifier.assigner: Option<Box<Reference>>` — break Reference↔Identifier cycle on the rarer field | code |
| 4 | `HumanName::thai()` / `english()` factories — `language` field used for filter, not via FHIR `_language` extension on primitives (Phase 1 simplification, can refactor later) | code + ADR-006 D5 |
| 5 | Thai address sub-district via Asgard-stable extension URL `https://fhir.moph.go.th/StructureDefinition/sub-district` | `address.rs` + `TH_SUB_DISTRICT_EXTENSION_URL` constant |
| 6 | `Extension` minimal Day 5 → 9-variant Day 7. Remaining ~40 variants on demand | code |
| 7 | `Meta.versionId` / `Meta.lastUpdated` derived from Tyr audit on emit; struct fields are `Option<...>` ignored on write | ADR-006 D2 |
| 8 | `Decimal` wrapper newtype (not `pub use`) — for JsonSchema + type identity | Day 8 refactor |
| 9 | JSON Schema export via runtime helper, not `build.rs` — keeps cargo builds fast | `schema_export.rs` |
| 10 | Schemas alphabetically sorted in output for diff-friendly CI | test (`schemas_are_sorted_alphabetically_for_stable_diff`) |

None of these required a new ADR — all sit within ADR-006 D1-D5 design space.

## Metrics

| Metric | Value |
|---|---|
| Source files (`mimir-fhir/src/`) | 9 (lib + datatypes/mod + 6 datatype modules + schema_export) |
| Test files (`mimir-fhir/tests/`) | 14 |
| Total LOC source | ~3,400 |
| Total LOC tests | ~2,200 |
| Tests | **202 across 16 suites** |
| `cargo build` (clean) | ~12s |
| `cargo build` (incremental) | <1s |
| `cargo test` runtime | <1s |
| Clippy with `-D warnings` | clean |
| Cargo fmt | clean |
| `unsafe_code` | forbidden (lint) |
| Deps | serde, serde_json, schemars (chrono+preserve_order), chrono, thiserror, rust_decimal (serde-with-str) |

## Sprint 2 Backlog (Resources Layer)

Direct continuation. The 20 FHIR R5 resources to implement, in TDD order (least dependent first):

| # | Resource | Dependencies (datatypes used) | Phase 1 plan day |
|---|---|---|---|
| 1 | `Patient` | Id, Identifier, HumanName, Address, ContactPoint, Code, CodeableConcept, Reference, Period, Meta, Narrative | Sprint 2 (Phase 1 Sprint 2-3) |
| 2 | `Encounter` | Identifier, Reference, Period, CodeableConcept | Sprint 2 |
| 3 | `Observation` + 8 sub-profile builders | Identifier, Quantity, CodeableConcept, Reference, Period, Range, Ratio, Annotation | Sprint 3 |
| 4-20 | Condition, MedicationRequest, MedicationStatement, Procedure, AllergyIntolerance, DocumentReference, DiagnosticReport, Coverage, Claim, ClaimResponse, Practitioner, Organization, Location, Immunization, Specimen, ImagingStudy, Device | various | Sprint 4-5 |

Additional pre-Sprint-2 work:
- Verify all datatype JSON Schemas roundtrip through HAPI sandbox or HL7 validator (external sanity check)
- Add `Patient`/`Encounter`/`Observation` Sprint 2 acceptance criteria to checkpoint doc

## Open Questions for Sprint 2+

1. **Resource ID strategy** — server-generated ULID per [`mimir_well` pattern](../decisions/ADR-011-mimir-well-memory-artifacts.md) vs client-supplied? Defer to Sprint 6 (REST endpoint design).
2. **Bundle.entry closed enum** — per ADR-006 D1. Day 7 finished all 20 resource-supporting datatypes; the enum becomes possible to construct in Sprint 5 after the 20th resource lands.
3. **`External*` newtype pattern** for lenient inbound parsing (ADR-006 D4) — Phase 1 Sprint 5 starts; design the type-state transition pattern then.
4. **`r4_to_r5` translator** scaffolding — Sprint 2-3 alongside Patient + Encounter (the highest-translation-cost resources per [mapping doc R4↔R5 diff](../architecture/moph_pc1_fhir_mapping.md#r4-→-r5-element-name-diff-full-list)).

## What I'd Do Differently Next Sprint

1. **Wrap external types from the start.** `Decimal` would have been wrapped in Day 6 if I had anticipated Day 8 schemars; the Day 8 refactor was painless but unnecessary churn.
2. **Don't derive `Default` on types with non-Optional required fields.** Extension + Annotation needed factory constructors instead; learning landed in Day 7. Pattern: only derive `Default` when ALL fields are `Option<T>` / `Vec<T>` / primitives with sensible zero.
3. **Add `# Panics` doc section even on infallible `.expect()` paths** — clippy enforces it under pedantic; just write the section up front rather than fixing in Day 8.

## Sprint 2 Kickoff Readiness

- [x] Datatype layer complete (every Resource field type implementable)
- [x] JSON Schema export pipeline ready
- [x] Thai bilingual i18n proven end-to-end at datatype layer
- [x] Test infrastructure pattern established (one suite per type)
- [x] Branch + commit cadence pattern established
- [x] Coordination log working (no collisions with Session A in 10+ hours)
- [ ] HOSxP anonymized dump acquired (Step 0.1 of implementation steps — needed for Sprint 8 adapter, not Sprint 2 resources)
- [ ] TH Core profile JSON snapshot downloaded (Step 0.2 — needed for Sprint 7 validators, not Sprint 2 resources)
- [ ] OpenEMR Smart-on-FHIR support verified (Step 0.3 — needed for Sprint 9 launch, not Sprint 2)

Sprint 2 can start without the 3 unchecked items — they unblock Sprint 7-9.

---

## Acknowledgments

Sprint 1 ran in parallel with Session A's Iris / ADR-002 OCR provenance work (5 commits including v2.9.0 → v2.9.4 + v2.10.0 on asgard-underwriter, b224845 on Mimir). Zero scope collision thanks to:

- Clear file-boundary documentation in `log-session-status.md`
- Mutual ACK of each commit batch
- Distinct scopes (Session A: `routes/ocr.rs` + Iris; Session B: `mimir-fhir/`)

The coordination log pattern is documented in [`log-session-status.md`](../../../log-session-status.md) and is recommended for any future multi-session work on this repo.
