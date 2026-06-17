# ADR-016: Asgard FHIR Profile Family — Own Profile, Informed by PC1, Not Strictly Conformant

**Status:** Accepted
**Date:** 2026-05-26
**Deciders:** paripol@megawiz.co (with endorsement from Aj. Rath Panyowat, MOPH-PC1 architect)
**Scope:** Locks the strategic posture for Asgard's FHIR profile work — name, ownership, relationship to MOPH-PC1, update / amendment process, publishing strategy. Applies to all FHIR profile-related decisions going forward (Sprint 2 onwards).
**Supersedes:** the implicit "strict MOPH-PC1 conformance" posture in [ADR-006 Amendment 1](ADR-006-fhir-canonical-design.md) (now reframed) and the "bounded by MOPH-PC1" scope rule in [ADR-006 Decision 1](ADR-006-fhir-canonical-design.md#decision-1--bundleentry-typing) (relaxed).
**Related:** [ADR-006](ADR-006-fhir-canonical-design.md), [ADR-012](ADR-012-fhir-native-data-plane-no-ehr-replacement.md), [ADR-013](ADR-013-fhir-r5-canonical-version.md), [ADR-014](ADR-014-fhir-data-plane-ownership.md), [ADR-015](ADR-015-add-composition-and-uc2-patient-summary.md), [MOPH-PC1 mapping](../architecture/moph_pc1_fhir_mapping.md), [Aj. Rath consultation memory](../../../.claude/projects/-Users-mimir-Developer/memory/rath_panyowat_pc1_consultation.md)

## Context

ADR-006 Amendment 1 (2026-05-23) locked Asgard's FHIR resource scope at 20 resources, framed as "bounded by MOPH-PC1's 78-element mapping". This framing implicitly committed Asgard to **strict PC1 conformance** — every resource addition required justifying against PC1 scope, every "errata" in the PC1 spreadsheet became a workaround.

Two things have happened since:

1. **ADR-015 (2026-05-26)** added `Composition` as the 21st resource for UC2 Cross-Encounter Patient Summary — already a deviation from PC1's element-level scope.
2. **Aj. Rath Panyowat consultation (2026-05-26)** — the PC1 architect himself:
   - Endorsed FHIR R5 for Asgard (validates ADR-013)
   - Acknowledged methodology issues in PC1 ("ในหลายเรื่ิงที่ผมไม่เห็นด้วยด้านวิธีการจัดทำ")
   - Explicitly told Asgard: **"หา FHIR Profile ที่เหมาะกับ Asgard เองได้เลย ไม่ต้องยึดติด PC1"** (translate: design your own FHIR profile suited to Asgard, no obligation to stay strictly conformant with PC1)

The consultation reframes the strategic posture. ADR-006 Amendment 1 framing is now inconsistent with how Asgard will actually operate going forward. This ADR locks the new posture.

## Decision

**Asgard publishes and maintains its own FHIR Profile family — "Asgard FHIR Profile" — informed by MOPH-PC1 and the Thai healthcare context but NOT strictly conformant to PC1.** PC1 mapping continues to be the canonical starting reference; divergence from PC1 is a deliberate, documented design choice rather than an exception to fix.

### D1. Profile family identity

- **Family name:** "Asgard FHIR Profile"
- **Canonical URL root** (proposed, pending DNS/cert provisioning):
  `https://fhir.asgard.megawiz.co.th/StructureDefinition/{ResourceName}`
- **Versioning:** SemVer per [[semver_release_process]] — v0.x.x during Phase 1, v1.0.0 at Phase 1 GA, breaking changes major bump
- **Distribution:**
  - `mimir-fhir` Rust crate ships profile validators as code
  - `mimir-fhir/profiles/asgard/{version}/{ResourceName}.profile.json` vendored as JSON Schema-compatible artifacts (post-Sprint 7)
  - Public publication of `StructureDefinition` resources deferred to Sprint 7 detail design (see [D5](#d5-profile-publishing-strategy-deferred))

### D2. Relationship to MOPH-PC1

| Aspect | Posture |
|---|---|
| PC1 as starting point | ✓ Asgard imports PC1's element-to-resource mapping as the initial scope |
| Strict PC1 conformance | ✗ Not required — Asgard diverges where use cases warrant |
| PC1 element semantics | ✓ Adopted where they make sense (vital signs, identifiers, address structure) |
| PC1 scope boundary | ✗ Not binding — Asgard adds resources (e.g., Composition per ADR-015) for non-PC1 use cases |
| Divergence documentation | ✓ Tracked in [`moph_pc1_fhir_mapping.md` § Asgard divergence from PC1](../architecture/moph_pc1_fhir_mapping.md#asgard-divergence-from-pc1) |
| ADR amendment for divergence | ✗ Not required for content; required only for scope changes (resource list / FHIR version / ownership) |

### D3. Profile content scope (initial)

Asgard FHIR Profile covers, at Phase 1 stabilisation:

- **21 R5 resources** — 20 from ADR-006 A1 + Composition from ADR-015. Further additions require their own ADR.
- **TH Core extension URLs** honoured where MOPH publishes them; Asgard-stable URLs used as fallback until then. Migration plan: when MOPH publishes official URL, Asgard adapter honours both URLs for a transition window, then deprecates the Asgard-stable URL.
- **Code system bindings:**
  - TMT (Thai Medication Terminology) — drugs, drug allergies
  - ICD-10-TM — diagnoses
  - SNOMED CT — clinical findings, procedures, manifestations
  - LOINC — vital signs, lab results
  - HL7 v2-0203 — identifier types (NI, MR, etc.)
- **Profile slices** for Thai-specific shapes:
  - Patient.identifier: Thai citizen ID 13-digit slice
  - HumanName: Thai-script + Latin transliteration pair (per ADR-006 D5)
  - Address: 4-level Thai mapping (line / district / state / postalCode + sub-district extension)

### D4. Update / amendment process

| Change type | Process |
|---|---|
| Content (slice, validator, extension URL update, code system mapping clarification) | PR + brief rationale; no ADR amendment |
| Adding a new field / making an optional field required | PR + brief rationale; no ADR amendment |
| Removing a field, breaking change to existing field | PR + minor version bump on Asgard FHIR Profile + ADR amendment |
| Adding a new resource | New ADR (e.g., ADR-015 for Composition) |
| Removing a resource | ADR + breaking-change Profile major version bump |
| FHIR version change (R5 → R6) | ADR amendment (ADR-013 successor) |
| Ownership change (Mimir → Eir / standalone) | ADR amendment (ADR-014 successor) |

This is **less amendment friction than ADR-006 A1's implicit "PC1-bound" framing**, which would have required justifying every deviation. The looser process trades off some governance for speed.

### D5. Profile publishing strategy (deferred)

Whether Asgard publishes `StructureDefinition` resources at the canonical URL (allowing external FHIR validators to retrieve them) is **deferred to Sprint 7** (profile validators sprint).

Two options on the table:

**Option A — Public publication.** Host StructureDefinition JSON at `https://fhir.asgard.megawiz.co.th/StructureDefinition/...`. Pros: external FHIR validators (`$validate`, IG Publisher) can resolve canonical URLs; downstream Thai vendors could adopt; supports MOPH community contribution narrative. Cons: requires DNS/cert provisioning, ongoing hosting, public commitment to URL stability.

**Option B — Internal only.** Asgard ships profile validators as compiled Rust code in `mimir-fhir`. Pros: no hosting burden, no public commitment. Cons: external systems can't validate Asgard resources without copying our crate; harder to contribute back to community.

**Decision criterion:** if Phase 1 demo includes any non-Asgard FHIR client validation, Option A wins. If demo is fully self-contained, Option B is acceptable.

### D6. Relationship to MOPH FHIR Thailand IG (future)

- **No formal endorsement** sought from MOPH in Phase 1. Pursuing official endorsement adds political effort and uncertain timeline; Asgard ships and gathers references first.
- **Reciprocal contribution channels:**
  - Blog posts (per [[feedback_blog_confidentiality]] — generic terms only)
  - Conference talks (HL7 Thailand, RCPT, Thai Heart Society)
  - Code samples (Asgard FHIR Profile JSON, MOPH-PC1 conformance test corpus — synthetic data only per [[syn_data_internal_only]])
  - Direct technical conversations with Aj. Rath and MOPH IT team (Sprint 7+)
- **TH Core profile JSON adoption:** when MOPH publishes official TH Core profile JSON, Asgard FHIR Profile adapters honour both Asgard-stable URLs and MOPH-official URLs for a transition window (12-18 months), then deprecate Asgard URLs.
- **PC2 / future MOPH datasets:** when MOPH publishes new datasets (NCD-focused, specialty-specific), Asgard audits and decides per-case whether to align Asgard FHIR Profile or maintain divergence.

## Why this posture

1. **Endorsed by PC1 architect** — Aj. Rath consultation 2026-05-26 explicitly gave permission to deviate
2. **PC1 architect himself acknowledges methodology issues** — his FB comment + in-person reinforcement
3. **Asgard scope is broader than primary care** — clinical decision support across specialties, insurance underwriting (asgard_insurance tenant), document-level summaries (UC2), pharmacovigilance, etc. PC1's primary-care-only frame is too narrow
4. **First adopter advantage** — Asgard has no installed base to break by deviating, and PC1 has no other production users (per Aj. Rath's own admission "ผมนึกว่าเขาทำไว้บนหิ้งเฉย ๆ")
5. **Reduces ADR friction** — under strict-PC1 framing, every Composition / Practitioner / future addition would need ADR amendment justifying against PC1 scope. Under this ADR, scope-bounded amendments only
6. **Cleaner sales narrative** — "Asgard FHIR Profile aligned with MOPH-PC1 conventions, designed for Thai medical AI" is easier than "Asgard implements MOPH-PC1 verbatim with these exceptions..."

## What we explicitly do NOT do

| Tempting choice | Reason rejected |
|---|---|
| Strict PC1 conformance | Per architect — PC1 is data dictionary not vendor spec; methodology has known issues; Asgard scope broader |
| Wait for MOPH to publish updated PC1 before shipping | MOPH timeline unknown; Asgard cannot block Phase 1 on it |
| Seek formal MOPH endorsement in Phase 1 | Political effort + timeline risk; ship first, gather references, pursue endorsement in Phase 2+ |
| Publish Asgard FHIR Profile publicly in Phase 1 | Hosting burden; commitment to URL stability before profile design stabilises. Defer to Sprint 7 |
| Diverge from PC1 silently | Divergence MUST be documented in mapping doc § Asgard divergence section; transparency preserved |
| Treat Asgard FHIR Profile as a replacement for TH Core | Asgard adopts TH Core extensions where MOPH publishes them; we are an implementer, not a competitor |
| Hard-fork from MOPH-PC1 | Mapping doc continues to track every PC1 element; divergence is curated, not abandonment |

## Consequences

**Positive:**

- Architect-endorsed posture — strongest possible Thai-context validation
- Faster Phase 2-5 iteration — Sprint 2 Patient + Encounter, Sprint 3 Observation, etc. can include Asgard-required fields without per-resource PC1 cross-reference debate
- ADR amendment friction reduced significantly
- Sales narrative cleaner ("Asgard FHIR Profile, aligned with MOPH-PC1 conventions")
- Reciprocal contribution channel opens to MOPH community on Asgard's terms
- Future-proofs against PC2 / R6 / TH Core IG evolutions — Asgard adapts, doesn't break

**Negative:**

- Asgard maintains its own profile documentation indefinitely (vs riding on MOPH publishing)
- External FHIR validators can't auto-resolve Asgard profiles unless we publish (Sprint 7 decision)
- Vendors who want strict PC1 conformance from Asgard must request it as a feature (R4-style content negotiation at adapter boundary; existing ADR-013 D2 R4 emit path is the precedent)
- Risk of profile drift between Asgard and MOPH official if both evolve independently — mitigated by mapping doc tracking + annual re-audit

**Neutral / TBD:**

- Asgard FHIR Profile canonical URL hosting — deferred to Sprint 7
- Whether to seek HL7 Thailand affiliate membership / official observer status — deferred to Phase 2 GTM decisions
- Asgard FHIR Profile version cadence (annual? per-Phase? per-major-release?) — confirmed at Phase 1 retro

## Open questions

1. **Domain provisioning** — `fhir.asgard.megawiz.co.th` DNS + TLS cert. Coordinate with Yggdrasil ([[asgard_jwt_auth_pattern]]) for hosting strategy. Timeline: pre-Sprint 7.
2. **Profile naming detail** — is the family name `Asgard FHIR Profile` (singular) or `Asgard FHIR Profiles` (plural)? Singular sounds cleaner in API context; plural is more accurate. Default: singular.
3. **TH Core vs Asgard relationship** — does Asgard profile depend on TH Core (extension URLs imported) or implement standalone? Architect view not captured in consultation — defer to Sprint 7 detail design.
4. **Profile versioning lock** — SemVer enough or need date-based (e.g., `2026-05-26`-suffixed JSON files like we already do for vendored MOPH JSON)? Likely both — Cargo crate uses SemVer, on-disk JSON uses date prefix.
5. **Sub-district extension migration** — when MOPH publishes official sub-district extension URL, exact migration plan. Defer until MOPH publishes.

## Implications for prior ADRs

| ADR | What changes | When to update |
|---|---|---|
| ADR-006 A1 | "bounded by MOPH-PC1" framing soften to "informed by MOPH-PC1"; scope rule relaxed (resource additions allowed via per-ADR) | Amendment 3 alongside next scope change |
| ADR-012 D2 | "FHIR Thailand profile compliance" wording updated to "Asgard FHIR Profile (informed by TH Core + MoPH-PC)" | Amendment 2 alongside next D2 update |
| ADR-013 § Validation criteria | Add "Endorsed by PC1 architect Aj. Rath Panyowat (2026-05-26)" as external validation point | Amendment 1 (recommended this PR) |
| ADR-014 | No change — data plane ownership unchanged | n/a |
| ADR-015 | Reframe Composition addition as Asgard-Profile design choice (not PC1 scope exception) | Status update from Proposed → Accepted; minor framing edit |

These prior-ADR updates are **non-blocking** — Asgard FHIR Profile work in Sprint 2-5 can proceed before they land. They are housekeeping for consistency.

## Validation criteria

This ADR is validated when:

- [ ] `mimir-fhir/profiles/asgard/` directory established (post-Sprint 7)
- [ ] First Asgard FHIR Profile JSON exported (Patient profile, post-Sprint 2)
- [ ] PC1 mapping doc v2 reflects new posture (✓ done 2026-05-26 alongside this ADR)
- [ ] No PR adds a FHIR resource type outside `mimir-fhir/` (CI lint per cross-service consistency design)
- [ ] Sprint 2 Patient + Encounter implementation uses Asgard FHIR Profile naming + extension URLs
- [ ] At least one Phase 2 use case (eir-ddx, eir-care-pathway, etc.) consumes Asgard FHIR Profile without PC1 cross-reference

## References

- [ADR-006: FHIR canonical design](ADR-006-fhir-canonical-design.md) — type system + amendment history
- [ADR-012: FHIR-native data plane](ADR-012-fhir-native-data-plane-no-ehr-replacement.md) — 3-layer architecture
- [ADR-013: FHIR R5 canonical version](ADR-013-fhir-r5-canonical-version.md) — R5 lock (architect-endorsed)
- [ADR-014: FHIR data plane ownership](ADR-014-fhir-data-plane-ownership.md) — Mimir owns
- [ADR-015: Composition + UC2 patient summary](ADR-015-add-composition-and-uc2-patient-summary.md) — 21st resource
- [MOPH-PC1 FHIR mapping v2](../architecture/moph_pc1_fhir_mapping.md) — informative reference + divergence tracking
- [Aj. Rath consultation memory](../../../.claude/projects/-Users-mimir-Developer/memory/rath_panyowat_pc1_consultation.md) — 2026-05-26 consultation outcomes
- HL7 FHIR R5 — http://hl7.org/fhir/R5/
- MOPH FHIR Thailand IG — https://fhir.moph.go.th
- HL7 IG Publisher — https://github.com/HL7/fhir-ig-publisher (post-Sprint 7 if Option A in D5)
