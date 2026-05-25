# Mimir-FHIR — Step-by-Step Implementation Guide

**Status:** Draft v1
**Date:** 2026-05-24
**Companion to:** [mimir-fhir-phase-1-plan.md](./mimir-fhir-phase-1-plan.md)
**Scope:** Tactical day-by-day execution guide. The Phase 1 plan is sprint-level (10 sprints × 2 weeks); this doc translates each sprint into daily tasks + concrete commands. Read this when you sit down to actually code, not when planning.

---

## How to use this guide

- **Phase 1 is gated** after S1 Go/No-Go (2026-06-12) + Insurance Launch (S52-54) + Living Evidence (S55-58). You **cannot start Sprint 1** until those wrap. But **Step 0 (pre-Phase-1)** is fair game now — none of it blocks the gating sprints.
- **TDD discipline** — every task that produces code MUST have a failing test first.
- **Commit cadence** — at minimum one commit per day, ideally per completed task. Each commit on `feat/mimir-fhir-phase-1` branch.
- **Backup before destructive ops** — see [Phase 1 plan §Backup Strategy](./mimir-fhir-phase-1-plan.md#backup-strategy-per-feedback_backup_before_changes).
- **When stuck** — see [§ Escalation tree](#when-stuck--escalation-tree) at end of this doc.

---

## Step 0 — Pre-Phase-1 prep (do NOW, parallel with S55-58)

These 7 tasks unblock Phase 1. None depend on S58 finishing. Do them this month while S55-58 work is ongoing.

### 0.1 Acquire anonymized HOSxP test dump

**Why:** Sprint 8 (43Files adapter) needs real-world test data. Without this, you ship adapter code that works against synthetic data but breaks on first real hospital.

**Action:**
```bash
# Reach out to friendly hospital partner (sleep clinic origin? specialty clinic?)
# Request: anonymized MariaDB dump of 43Files tables
#   PERSON, SERVICE, ADMISSION, NCDSCREEN, DIAGNOSIS_OPD, DIAGNOSIS_IPD,
#   DRUG_OPD, DRUG_IPD, PROCEDURE_OPD, PROCEDURE_IPD, LABFU, EPI,
#   DRUGALLERGY, CARD
# PII scrub spec: replace names with hash, replace national IDs with synthetic,
#   replace phone/email/address but keep province/district codes intact
# Target volume: ~1000 patients × ~10000 encounters minimum
```

**Storage:** `/Volumes/T7 Shield/asgard-test-data/hosxp-anonymized/` (per [[mimir_data_on_t7]] pattern)

**Done when:** dump exists on T7, can be restored to local MariaDB, spot-check confirms PII is scrubbed.

### 0.2 Download TH Core profile JSON snapshot

**Why:** Sprint 7 (profile validators) reads these as input. Snapshot avoids version drift.

**Action:**
```bash
# Download from fhir.moph.go.th
mkdir -p /Users/mimir/Developer/Mimir/mimir-fhir/profiles/th-core/
cd /Users/mimir/Developer/Mimir/mimir-fhir/profiles/th-core/

# Capture published date in filename
SNAPSHOT_DATE=$(date +%Y-%m-%d)
mkdir -p $SNAPSHOT_DATE
cd $SNAPSHOT_DATE

# Download each profile JSON (URLs to be confirmed from fhir.moph.go.th)
# Patient, Encounter, Observation (8 sub-profiles), AllergyIntolerance,
# Condition, MedicationRequest, MedicationStatement, Procedure,
# DiagnosticReport, DocumentReference, Coverage, Practitioner, Organization,
# Location, Immunization, Specimen, ImagingStudy, Device

# Commit raw JSON to git (these are public profiles, OK to vendor)
```

**Done when:** all 20 resources' profile JSON committed under dated directory.

### 0.3 Verify OpenEMR Smart-on-FHIR support level

**Why:** Sprint 9 (Smart-on-FHIR launch) assumes OpenEMR can launch external apps. Need to verify NOW so fallback plan (HAPI sandbox) is ready if not.

**Action:**
```bash
# Spin up OpenEMR locally
cd /Users/mimir/Developer/Asgard
docker compose -f docker-compose.openemr.yml up -d
# Verify FHIR endpoint
curl -s http://localhost:8080/apis/default/fhir/metadata | jq '.fhirVersion'
# Test Smart-on-FHIR app registration flow (manual UI walk-through)
# Document findings in: docs/technical/openemr-smart-on-fhir-status.md
```

**Done when:** documented yes/no on Smart-on-FHIR support + fallback plan if no.

### 0.4 Generate MOPH-PC1 synthetic corpus (5 patients × 78 elements)

**Why:** Sprint 0 needs this corpus for conformance testing. Build it once, use for 10 sprints.

**Action:**
```bash
mkdir -p /Users/mimir/Developer/Mimir/mimir-fhir/tests/moph_pc1/fixtures/
cd /Users/mimir/Developer/Mimir/mimir-fhir/tests/moph_pc1/fixtures/

# Create 5 patient bundles, each covering all 78 elements
# Pattern: patient_01_complete.json — every element populated
#          patient_02_outpatient.json — OPD scenario
#          patient_03_inpatient.json — IPD with discharge
#          patient_04_paediatric.json — well-child + immunization
#          patient_05_lab_specimen.json — full lab workflow + specimen
```

Reference per-element FHIR shape from [`docs/architecture/moph_pc1_fhir_mapping.md`](../architecture/moph_pc1_fhir_mapping.md).

**Done when:** 5 R5 Bundles committed, manually validated against MOPH-PC1 mapping doc element-by-element.

### 0.5 Evaluate fhir-rs crate ecosystem

**Why:** Decide build-from-scratch vs adopt-existing for Sprint 1 datatypes. Spike before sprint kickoff.

**Action:**
```bash
# Clone candidate crates, evaluate
mkdir -p /tmp/fhir-rs-spike && cd /tmp/fhir-rs-spike

git clone https://github.com/<actual-repo>/fhir-rs.git
git clone https://github.com/<actual-repo>/fhir-sdk-rs.git

# For each: check
# 1. R5 support level (vs R4 only)
# 2. License compatibility with AGPL-3.0 + Commercial (per [[feedback_asgard_license]])
# 3. Active maintenance (last commit < 6mo)
# 4. schemars derive support
# 5. serde support
# 6. Test fixtures / examples for our 20 resources

# Document findings in: docs/technical/fhir-rs-evaluation.md
# Verdict: adopt | fork | build from scratch
```

**Done when:** decision recorded; if "adopt" or "fork", Sprint 1 will integrate; if "build", Sprint 1 starts from zero.

### 0.6 Confirm Phase 1 timing against S58 wrap

**Why:** Don't over-commit Phase 1 schedule before knowing if S58 is on time.

**Action:**
- Check S55-58 sprint tracker. Are Mimir Guideline Lineage + mimir-well + mimir-curator on track to ship?
- If S58 slips by N weeks, Phase 1 slips by N weeks. Update [Phase 1 plan](./mimir-fhir-phase-1-plan.md) timing estimates.

**Done when:** confirmed start date for Sprint 0 (Phase 1 pre-flight) is realistic.

### 0.7 Restore drill script

**Why:** [Phase 1 plan Sprint 6](./mimir-fhir-phase-1-plan.md#sprint-6--rest-api--persistence-layer-10-days) backup gate requires `scripts/restore-from-backup.sh`. If Sprint 56 (mimir-well) already built it, verify it works. If not, build now.

**Action:**
```bash
ls /Users/mimir/Developer/Asgard/scripts/restore-from-backup.sh
# If exists: run restore drill in scratch namespace
# If not: write it (target ~200 LOC; mirrors backup-full-k8s.sh in reverse)
```

**Done when:** restore drill succeeds in scratch namespace; documented in `docs/runbooks/restore-drill.md`.

---

## Step 1 — Sprint 0 (Pre-flight, ~5 days, after S58 wraps)

### Day 1 — Backup + pre-condition verification

**Morning (2-3 hr):**

```bash
# 1. Full T7 Shield backup
cd /Users/mimir/Developer/Asgard
./scripts/backup-full-k8s.sh
# Tag: pre-mimir-fhir-phase-1
# Verify MANIFEST + gzip integrity (per [[asgard_full_backup_procedure]])
ls -lh "/Volumes/T7 Shield/asgard-backup-$(date +%Y-%m-%d)/"
gunzip -t "/Volumes/T7 Shield/asgard-backup-$(date +%Y-%m-%d)/MANIFEST"

# 2. Verify pre-conditions (per Phase 1 plan §Pre-Conditions)
# Run a checklist script (write it):
./scripts/mimir-fhir-preflight.sh
# Should output: P1 ✓ P2 ✓ ... P10 ✓
```

**Afternoon (3-4 hr):**

```bash
# 3. Mac mini headroom check
sudo purge
vm_stat | grep "Pages free"
# Want ≥30GB free RAM (per [[mac_mini_specs]])

# 4. Confirm Step 0 artifacts in place
ls /Volumes/T7\ Shield/asgard-test-data/hosxp-anonymized/
ls /Users/mimir/Developer/Mimir/mimir-fhir/profiles/th-core/
ls /Users/mimir/Developer/Mimir/mimir-fhir/tests/moph_pc1/fixtures/
```

**End of day:** all pre-conditions green or documented waiver in `docs/sprints/mimir-fhir-sprint-0-checkpoint.md`.

### Day 2 — Cargo workspace scaffold

**Morning:**

```bash
cd /Users/mimir/Developer/Mimir

# Create branch
git checkout -b feat/mimir-fhir-phase-1

# Add workspace member
# Edit Cargo.toml: add "mimir-fhir" to workspace.members

# Scaffold crate
cargo new --lib mimir-fhir
cd mimir-fhir

# Initial Cargo.toml dependencies (R5-oriented)
# serde, serde_json, schemars, chrono, uuid, ulid, rust_decimal
# axum (REST server), tokio (async runtime)
# sqlx or sea-orm (MariaDB persistence) — defer to Sprint 6
# tracing (logging)

# License + copyright header (AGPL-3.0 + Commercial per [[feedback_asgard_license]])
# Add LICENSE.md mirror in mimir-fhir/

cargo build  # should succeed on empty lib

git add . && git commit -m "scaffold mimir-fhir crate with R5 type system targets"
```

**Afternoon:**

```bash
# Directory structure (create empty mod files now, fill in sprints 1-5)
mkdir -p src/{datatypes,resources,profiles,translate/r4_to_r5,adapters/forty_three_files,validators,rest}
mkdir -p src/resources/observation/sub_profiles

# Empty mod.rs files with TODO comments per sprint plan
# src/lib.rs imports all top-level mods

cargo check  # ensure structure compiles
git add . && git commit -m "src/ directory skeleton per Phase 1 plan"
```

### Day 3 — CI setup + test corpus commit

**Morning:**

```bash
# GitHub Actions workflow for mimir-fhir
mkdir -p .github/workflows
# .github/workflows/mimir-fhir-ci.yml: cargo check, clippy, test, fmt --check
# Run on PR + push to main + feat/mimir-fhir-* branches

# Verify CI green on first push
git push -u origin feat/mimir-fhir-phase-1
# Wait for green check on GitHub
```

**Afternoon:**

```bash
# Copy MOPH-PC1 corpus from Step 0.4
cp -r /path/to/step-0.4-fixtures/ tests/moph_pc1/fixtures/
git add . && git commit -m "moph-pc1 78-element synthetic corpus (5 patients)"

# Add corpus loader test stub (just verifies fixtures are valid JSON)
# tests/moph_pc1/corpus_loader.rs
cargo test  # should pass (just JSON validity)
```

### Day 4 — First PR + reviewer setup

```bash
# Push branch (already done)
# Open PR on GitHub: "Sprint 0: mimir-fhir scaffolding"
# Description: link to Phase 1 plan + ADR-006/012/013

# Sprint 0 doesn't merge to main yet — keep branch open through all of Phase 1
# CI must stay green

# Self-review checklist (since solo dev):
# - [ ] Compiles
# - [ ] No clippy warnings
# - [ ] LICENSE + copyright in place
# - [ ] README placeholder explains "Mimir-FHIR Phase 1 in progress"
# - [ ] Linked to Phase 1 plan + ADRs
```

### Day 5 — Sprint 0 retro

```bash
# Document Sprint 0 outcomes
cat > docs/sprints/mimir-fhir-sprint-0-retro.md <<EOF
# Sprint 0 Retro

## Done
- [list completed Day 1-4 tasks]

## Slipped / deferred
- [list anything missed]

## Pre-condition status (P1-P10)
- [check each]

## Sprint 1 confidence
- [high/medium/low + reasoning]
EOF

git add . && git commit -m "sprint 0 retro"
```

**End of Sprint 0:** pre-conditions verified, scaffolding committed, CI green, ready for Sprint 1 datatypes work.

---

## Step 2 — Sprint 1 (Datatypes, ~10 days)

TDD discipline: every datatype = write failing test first, then implement, then green.

### Day 1 — Primitive datatypes (1/2)

**Test first:**
```rust
// tests/datatypes/primitives.rs
#[test]
fn id_serializes_as_string() {
    let id = Id::from("patient-001");
    assert_eq!(serde_json::to_string(&id).unwrap(), "\"patient-001\"");
}

#[test]
fn id_rejects_invalid_chars() {
    assert!(Id::try_from("patient/001").is_err()); // FHIR Id grammar
}
```

**Implement:**
```rust
// src/datatypes/primitive.rs
pub struct Id(String);
impl Id { ... }
// Code, Canonical, Uri, Url, Markdown — similar shape
```

```bash
cargo test datatypes::primitives  # green
git commit -m "datatypes: Id, Code, Canonical, Uri, Url, Markdown"
```

### Day 2 — Primitive datatypes (2/2): temporal + numeric

```rust
// DateTime, Date, Time, Instant — wrap chrono
// Base64Binary — wrap Vec<u8> with base64 ser/de
// Decimal — wrap rust_decimal::Decimal (FHIR allows arbitrary precision)
// PositiveInt, UnsignedInt — newtype on u32 with validation
```

```bash
cargo test datatypes::primitives
git commit -m "datatypes: DateTime, Date, Time, Instant, Base64Binary, Decimal, PositiveInt, UnsignedInt"
```

### Day 3 — Identifier + Coding + CodeableConcept

```rust
// src/datatypes/identifier.rs
pub struct Identifier {
    pub use_: Option<IdentifierUse>,
    pub type_: Option<CodeableConcept>,
    pub system: Option<Uri>,
    pub value: Option<String>,
    pub period: Option<Period>,
    pub assigner: Option<Reference>,
}

// src/datatypes/coding.rs
pub struct Coding {
    pub system: Option<Uri>,
    pub version: Option<String>,
    pub code: Option<Code>,
    pub display: Option<String>,
    pub user_selected: Option<bool>,
}

// src/datatypes/codeable_concept.rs
pub struct CodeableConcept {
    pub coding: Vec<Coding>,
    pub text: Option<String>,
}
```

**Test:** Thai citizen ID identifier round-trip (13-digit national ID slice).

```bash
git commit -m "datatypes: Identifier, Coding, CodeableConcept"
```

### Day 4 — Reference + HumanName (Thai bilingual)

```rust
// src/datatypes/reference.rs — literal + logical reference
pub struct Reference {
    pub reference: Option<String>,           // literal "Patient/123"
    pub type_: Option<Uri>,
    pub identifier: Option<Identifier>,     // logical
    pub display: Option<String>,
}

// src/datatypes/human_name.rs — must support Thai + Latin via _language extension
pub struct HumanName {
    pub use_: Option<NameUse>,
    pub text: Option<String>,
    pub family: Option<String>,
    pub given: Vec<String>,
    pub prefix: Vec<String>,
    pub suffix: Vec<String>,
    pub period: Option<Period>,
    pub language: Option<Code>,             // _language extension for "th"/"en"
}

impl HumanName {
    pub fn thai(family: &str, given: &str) -> Self { ... }
    pub fn english(family: &str, given: &str) -> Self { ... }
}
```

**Test:** bilingual patient name round-trip per ADR-006 D5.

```bash
git commit -m "datatypes: Reference, HumanName (Thai bilingual)"
```

### Day 5 — Address (Thai extension) + ContactPoint + Period

```rust
// src/datatypes/address.rs
pub struct Address {
    pub use_: Option<AddressUse>,
    pub type_: Option<AddressType>,
    pub text: Option<String>,
    pub line: Vec<String>,
    pub city: Option<String>,
    pub district: Option<String>,            // อำเภอ
    pub state: Option<String>,               // จังหวัด
    pub postal_code: Option<String>,
    pub country: Option<String>,             // "TH"
    pub period: Option<Period>,
    pub extension: Vec<Extension>,           // Thai sub_district extension (ตำบล)
}

// src/datatypes/contact_point.rs — system (phone/email/...) + value + use
// src/datatypes/period.rs — start + end
```

```bash
git commit -m "datatypes: Address (Thai extension), ContactPoint, Period"
```

### Day 6 — Quantity + Money + Range + Ratio

```rust
// src/datatypes/quantity.rs
pub struct Quantity {
    pub value: Option<Decimal>,
    pub comparator: Option<QuantityComparator>,  // <, <=, >=, >
    pub unit: Option<String>,                     // human-readable
    pub system: Option<Uri>,                      // UCUM canonical URL
    pub code: Option<Code>,                       // UCUM code
}

// Money, Range, Ratio similar
```

```bash
git commit -m "datatypes: Quantity, Money, Range, Ratio"
```

### Day 7 — Annotation + Meta + Extension + Narrative

```rust
// src/datatypes/annotation.rs — text + author + time (used in Condition.note etc.)
// src/datatypes/meta.rs — version_id + last_updated derived from Tyr (per ADR-006 D2)
//                       — source, profile (canonical URLs), security, tag
// src/datatypes/extension.rs — recursive (extensions can have extensions)
// src/datatypes/narrative.rs — status (generated/extensions/additional/empty) + div (xhtml)
```

```bash
git commit -m "datatypes: Annotation, Meta, Extension, Narrative"
```

### Day 8 — schemars derive + cardinality annotations

```rust
// Add #[derive(JsonSchema)] to every datatype
// Add #[schemars(length(min = N))] for 1..* fields where needed
// Add custom #[schemars(...)] for FHIR-specific semantics (oneOf for value[x] polymorphism)

// Generate schemas at build time
// build.rs writes target/schemas/datatypes/*.json

cargo build  # verify schemas generate
ls target/schemas/datatypes/
```

```bash
git commit -m "datatypes: schemars derive + JSON Schema export"
```

### Day 9 — `_language` extension helper + i18n smoke tests

```rust
// src/datatypes/language_ext.rs — helper for FHIR _language extension on primitives
// Test: HumanName with Thai + English entries round-trips
// Test: Condition.note with Thai annotation round-trips
```

```bash
git commit -m "datatypes: _language extension helper + i18n round-trip tests"
```

### Day 10 — Sprint 1 retro + Sprint 2 kickoff prep

```bash
# Sprint 1 acceptance criteria check (from Phase 1 plan):
# - All datatypes compile + pass round-trip tests ✓
# - cargo test -p mimir-fhir green ✓
# - target/schemas/datatypes/*.json generated ✓

cat > docs/sprints/mimir-fhir-sprint-1-retro.md <<EOF
# Sprint 1 Retro
## Done — datatypes complete
## Slipped — [if any]
## Sprint 2 prep — Patient + Encounter, R4↔R5 translator scaffold
EOF

git commit -m "sprint 1 retro + sprint 2 kickoff prep"
```

**End of Sprint 1:** all FHIR R5 datatypes implemented, tests green, ready for Sprint 2 (Patient + Encounter).

---

## Step 3 — Pattern for Sprint 2 through Sprint 10

Each sprint follows the same daily template. Adjust task content per [Phase 1 plan](./mimir-fhir-phase-1-plan.md).

### Standard daily template

| Time | Activity |
|---|---|
| 9:00 – 9:30 | Review yesterday's commit; check CI green; plan today's tasks (1-2) |
| 9:30 – 10:00 | Write failing test (TDD red) for first task |
| 10:00 – 12:00 | Implement until test green |
| 12:00 – 13:00 | Lunch + memory check (`sudo purge` if heavy LLM work coming) |
| 13:00 – 15:00 | Second task (test red → green) |
| 15:00 – 16:00 | Refactor + clippy + fmt |
| 16:00 – 17:00 | Commit + push + verify CI green; update sprint checkpoint doc |

### Sprint kickoff template (Day 1 of any sprint)

1. Re-read sprint section in Phase 1 plan
2. List sprint acceptance criteria as todo checklist
3. Identify daily task breakdown (rough — adjust as you go)
4. Check dependencies (prior sprints' artifacts ready?)
5. Check backup gate (any state mutation this sprint? if yes, run backup before Day 2)
6. Document any open question for clinical advisor

### Sprint retro template (Last day of any sprint)

```markdown
# Sprint N Retro

## Acceptance criteria
- [x] criterion 1
- [ ] criterion 2 — SLIPPED, reason: ...

## What worked
- ...

## What slipped
- ...

## Lessons for next sprint
- ...

## Backlog for Phase 2
- ... (items that came up but were out of Phase 1 scope)
```

### Sprint-specific gotchas (per [Phase 1 plan Risk Register](./mimir-fhir-phase-1-plan.md#risk-register-sprint-level))

| Sprint | Watch out for |
|---|---|
| 2 | TH Core Patient profile slices may differ from spec — verify against snapshot |
| 3 | Type-state pattern for Observation sub-profiles — start with runtime validation, gate compile-time only on demand |
| 4 | TMT code table location — coordinate with Mimir KB on T7 ([[mimir_data_on_t7]]) |
| 6 | MariaDB schema migration — backup-first; restore drill in scratch namespace BEFORE prod-like DB |
| 7 | TH Core profile JSON may need code-gen tool; defer to Phase 2 if hand-written validators are faster |
| 8 | **Biggest sprint, highest risk.** HOSxP schema quirks. Plan 20-30% schedule buffer. |
| 9 | If OpenEMR Smart-on-FHIR insufficient (Step 0.3), fall back to HAPI sandbox + custom launcher |
| 10 | Demo data realism — flag synthetic-only issues for Phase 2 pilot data work |

---

## Daily Discipline Checklist

Print this and stick on monitor:

- [ ] **Did I write a failing test FIRST?** (TDD red)
- [ ] **Does the test cover the happy path?**
- [ ] **Does the test cover ≥1 edge case?**
- [ ] **Did I commit before lunch + before end-of-day?**
- [ ] **Did I run `cargo clippy` + `cargo fmt --check`?**
- [ ] **Did I update the sprint checkpoint doc?**
- [ ] **Did I check Mac mini RAM headroom?** (sudo purge if planning multi-LLM work)
- [ ] **Did I push to GitHub?** (CI green check before going home)
- [ ] **If state mutation today: was backup run?**

## Weekly Discipline Checklist

End of each week (Friday afternoon):

- [ ] All daily commits pushed; branch up-to-date with origin
- [ ] CI green on latest commit
- [ ] Sprint checkpoint doc reflects actual progress vs plan
- [ ] Backup verification: T7 Shield mount + most-recent backup gzip OK
- [ ] If sprint behind: identify what to descope (NOT extend timeline)
- [ ] Plan next week's task breakdown

---

## When Stuck — Escalation Tree

```
Task feels hard / unclear?
  |
  v
Step A: Search Asgard memory + docs for prior context
  ├── grep /Users/mimir/.claude/projects/-Users-mimir-Developer/memory/
  ├── search Asgard/docs/decisions/
  └── search Asgard/docs/architecture/
  |
  | (5-15 min)
  |
  v
Found? -> apply prior pattern -> back to coding
Not found?
  |
  v
Step B: Spike (timebox 1-2 hours)
  ├── Write smallest possible test that exhibits the problem
  ├── Try 1-2 approaches
  └── Document findings (even if approach failed)
  |
  v
Resolved? -> commit + back to coding
Not resolved?
  |
  v
Step C: Ask Claude Code with full context
  ├── Quote: error message, current code, what was expected
  ├── Reference: which ADR / which sprint section
  └── Ask for: 2-3 alternative approaches, NOT one final answer
  |
  v
Resolved? -> commit + back to coding; save lesson to memory
Not resolved?
  |
  v
Step D: Ask clinical advisor or external expert
  ├── If FHIR spec question -> HL7 chat.fhir.org
  ├── If Thai medical workflow -> clinical advisor
  ├── If Rust idiom -> Rust users forum / Discord
  |
  v
Resolved -> commit + back to coding; save lesson + escalation pattern
Not resolved after Step D?
  |
  v
Step E: Defer to Phase 2; document the open question
  ├── This is allowed if the question is not blocking demo
  └── Move on; do not stall sprint
```

---

## Commands Cheatsheet

### Cargo workflow
```bash
cargo new --lib mimir-fhir                         # scaffold crate
cargo check -p mimir-fhir                          # fast compile check
cargo build -p mimir-fhir                          # full build
cargo test -p mimir-fhir                           # run all tests
cargo test -p mimir-fhir datatypes::               # run only datatypes tests
cargo test -p mimir-fhir -- --nocapture            # show println! output
cargo clippy -p mimir-fhir -- -D warnings          # lint, fail on warning
cargo fmt --check                                  # format check (CI)
cargo doc -p mimir-fhir --open                     # generate + open docs
```

### Git workflow
```bash
git checkout -b feat/mimir-fhir-phase-1
# Daily commits...
git push origin feat/mimir-fhir-phase-1
gh pr create --draft --title "Sprint N: <topic>" --body "<link to plan>"
gh pr view --web   # open PR in browser
```

### Backup commands
```bash
cd /Users/mimir/Developer/Asgard
./scripts/backup-full-k8s.sh                       # full K8s + DB backup to T7
./scripts/backup-neo4j-only.sh TAG=pre-X           # cheaper Neo4j-only backup
./scripts/restore-from-backup.sh <backup-tag>      # restore (run in scratch first!)
```

### MariaDB inspection (Sprint 6+)
```bash
# Connect to Asgard MariaDB pod
kubectl exec -it -n asgard mariadb-0 -- mariadb -u root -p
# List tables in mimir DB
SHOW TABLES FROM mimir;
DESCRIBE mimir.fhir_resource;
```

### Memory check (per [[feedback_mac_mini_memory_pressure]])
```bash
sudo purge                                          # free inactive memory
vm_stat | grep "Pages free"                        # check available RAM
# Want >= 30GB before heavy LLM + multi-build work
```

### FHIR R5 spec lookup
- Resource browser: http://hl7.org/fhir/R5/resourcelist.html
- R4 vs R5 diff per resource: http://hl7.org/fhir/R5/<resource>.html → "Compare to R4"
- Thai IG: https://fhir.moph.go.th

---

## What to do RIGHT NOW (this week)

If you read this doc on 2026-05-24, here are the 3 tactical actions for **this week** (before Phase 1 gates clear):

1. **Step 0.1 — Reach out to friendly hospital partner** for anonymized HOSxP test dump request. Even if delivery takes 4-6 weeks, start the conversation now.
2. **Step 0.2 — Download TH Core profile JSON** snapshot from fhir.moph.go.th. Commit to a placeholder `mimir-fhir/profiles/th-core/` even before the crate exists. Get a feel for what's published.
3. **Step 0.3 — Spin up OpenEMR locally** and walk through Smart-on-FHIR app registration manually. 1-2 hours. Decide yes/no on viability + fallback plan.

These 3 unblock the highest-risk parts of Phase 1 (data, profile binding, launch flow). Do them while S55-58 still has 4-6 weeks of runway.

---

## References

- [Phase 1 implementation plan (sprint-level)](./mimir-fhir-phase-1-plan.md) — sprint goals + acceptance criteria
- [ADR-006 FHIR canonical design](../decisions/ADR-006-fhir-canonical-design.md)
- [ADR-012 FHIR-native data plane](../decisions/ADR-012-fhir-native-data-plane-no-ehr-replacement.md)
- [ADR-013 FHIR R5 canonical version](../decisions/ADR-013-fhir-r5-canonical-version.md)
- [MOPH-PC1 FHIR mapping](../architecture/moph_pc1_fhir_mapping.md)
- [As-is problem analysis](../use-cases/as-is-problem-analysis.md)
- [Strategic summary (CONFIDENTIAL)](../../../Asgard-Confidential/Mimir-FHIR/README.md)

---

**This is a tactical execution guide.** Update on each sprint kickoff with sprint-specific task breakdowns. Daily/weekly checklists are stable.
