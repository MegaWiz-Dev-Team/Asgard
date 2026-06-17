# Mimir-FHIR Sprint 0 — Checkpoint Log

**Sprint:** 0 (Pre-flight & scaffold)
**Started:** 2026-05-24
**Status:** Sprint 0 Day 2 in progress (scaffold + first datatype landed early)
**Branch:** `feat/syn-regions-stage1` (existing — to be split to `feat/mimir-fhir-phase-1` before next commit per Phase 1 plan)
**Plan reference:** [mimir-fhir-phase-1-plan.md §Sprint 0](../technical/mimir-fhir-phase-1-plan.md#sprint-0--pre-flight--test-corpus-week-0-5-days) + [implementation-steps.md §Step 1](../technical/mimir-fhir-implementation-steps.md#step-1--sprint-0-pre-flight-5-days-after-s58-wraps)

## Notes on early start

The Phase 1 plan gates Sprint 1 implementation after S1 Go/No-Go + Insurance Launch S52-54 + Living Evidence S55-58. **Sprint 0 scaffolding was started early (paper-only / non-destructive code organisation)** at the user's direction. This is acceptable because:

- New crate `mimir-fhir/` does not touch existing code
- Standalone Cargo workspace (empty `[workspace]` table) does not require `ro-ai-bridge/Cargo.toml` edits
- No state mutation in DB / Tyr / Mac mini infra
- Discovery work can inform S55-58 closing decisions

If Phase 1 gating slips, Sprint 0 commits stay parked on branch until ready.

## Day-by-Day Log

### Day 1 (2026-05-24, partial — sprint 0 + sprint 1 day 1 both started)

- [x] Locate existing Rust workspace structure (`/Users/mimir/Developer/Mimir/ro-ai-bridge/`)
- [x] Confirm `mimir-well` is sibling pattern to follow
- [x] Scaffold `mimir-fhir/` standalone crate (no workspace.members edit — preserves uncommitted `feat/syn-regions-stage1` work)
- [x] Cargo.toml with AGPL-3.0 + Commercial dual license (mirrors `mimir-well` pattern; see [[feedback_asgard_license]])
- [x] Strict lints: `clippy::all = deny`, `clippy::pedantic = warn`, `unsafe_code = forbid`
- [x] Directory skeleton: `src/datatypes/` (only filled module), placeholder for `resources/`, `profiles/`, `translate/`, `adapters/`, `validators/`, `rest/` (commented out in `lib.rs` until sprint kickoff)
- [x] Placeholder dirs: `profiles/th-core/.gitkeep`, `tests/moph_pc1/fixtures/.gitkeep`
- [x] README explaining sprint structure, build commands, license
- [x] **First datatype: `Id` (FHIR R5 primitive)** — full TDD
  - Validation: FHIR R5 grammar `[A-Za-z0-9\-\.]{1,64}`
  - 14 test cases (happy path × 3, length errors × 2, character errors × 4, Display/AsRef × 1, serde × 4)
  - Custom `Deserialize` impl ensures non-conformant Id cannot enter via JSON
  - Compile-time prevention of FHIR-non-conformant Id values via private `new()` validation
- [x] `cargo test` — **14/14 green**
- [x] `cargo clippy --all-targets -- -D warnings` — clean (after fixing doc-markdown backtick warnings)
- [x] `cargo fmt --check` — clean

### Day 2-5 (pending)

- [ ] Day 2: Cargo workspace decision (stay standalone vs add to ro-ai-bridge members) — defer until syn-regions-stage1 work commits
- [ ] Day 3: CI workflow `.github/workflows/mimir-fhir-ci.yml` (cargo check, clippy, test, fmt)
- [ ] Day 4: Open draft PR
- [ ] Day 5: Sprint 0 retro + Sprint 1 task breakdown

## Pre-Condition Status (per Phase 1 plan §Pre-Conditions)

| # | Pre-condition | Status |
|---|---|---|
| P1 | S1 Go/No-Go passed (2026-06-12) | **Pending** — 19 days away |
| P2 | Insurance Launch S52-54 production stable | **Pending** |
| P3 | Living Evidence S55-58 shipped | **Pending** |
| P4 | Full T7 backup verified | Not yet run for Phase 1 (next: before Sprint 6 schema work) |
| P5 | Anonymized HOSxP test dump available | **Not yet** — Step 0.1 action item |
| P6 | OpenEMR test instance running | **Not yet** — Step 0.3 action item |
| P7 | Mac mini headroom check | Not yet (current sprint paper-only) |
| P8 | Cargo workspace structure confirmed | ✓ standalone crate; workspace integration deferred |
| P9 | TH Core profile JSON available | **Not yet** — Step 0.2 action item |
| P10 | MOPH-PC1 78-element corpus drafted | **Not yet** — Step 0.4 action item; placeholder dir + README in place |

## Test Results

| Suite | Count | Status |
|---|---|---|
| `tests/datatypes_id.rs` | 14 | 14/14 ✓ |
| Sprint 0 total | 14 | 14/14 ✓ |

## Files added

```
Mimir/ro-ai-bridge/mimir-fhir/
├── Cargo.toml
├── README.md
├── src/
│   ├── lib.rs
│   └── datatypes/
│       ├── mod.rs
│       └── primitive.rs
├── profiles/th-core/.gitkeep
└── tests/
    ├── datatypes_id.rs
    └── moph_pc1/
        ├── README.md
        └── fixtures/.gitkeep
```

## Open issues

1. **Branch policy** — currently on `feat/syn-regions-stage1` (user's in-progress branch). Before next commit, decide:
   - (a) Switch to new branch `feat/mimir-fhir-phase-1` (requires resolving syn-regions changes)
   - (b) Stay on current branch and commit mimir-fhir alongside syn-regions (mixed scope)
   - (c) Stash syn-regions, switch, commit mimir-fhir, then pop (clean separation)
2. **Workspace membership** — `mimir-fhir` is standalone (own `[workspace]`). When ready, add to `ro-ai-bridge/Cargo.toml workspace.members` and drop the local `[workspace]` table.
3. **schemars on `Id`** — not yet derived. Sprint 1 Day 8 task; defer until more datatypes exist so JSON Schema export has critical mass.
4. **CI workflow** — not yet written. Add when branch policy resolved.

## Next session pickup

1. Resolve branch policy (open issue 1)
2. Continue Sprint 1 Day 2: implement `Code`, `Canonical`, `Uri`, `Url`, `Markdown` primitives (same TDD pattern as `Id`)
3. Run Step 0.2 (download TH Core profile JSON) in parallel
