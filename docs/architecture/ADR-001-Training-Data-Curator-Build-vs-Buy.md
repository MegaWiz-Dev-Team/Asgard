# ADR-001: Training Data Curator — Build vs Buy

**Status:** Accepted
**Date:** 2026-05-06
**Context:** Sprint 39 (LoRA fine-tuning) requires a labeling tool to curate
5,000-10,000 medical Q-A pairs into a training corpus. Multiple medical-lead
reviewers, custom rubric (accuracy/completeness/safety + edit + specialty tag),
JSONL export.

## Decision

**Build a minimal-scope "Mimir Curator" page inside Mimir Dashboard rather than
deploying Label Studio.**

Scope is intentionally narrow: a "Training Data Review" page (~10-15% of Label
Studio's feature surface), not a Label Studio replacement. ~1.5-2 weeks
implementation effort vs 5-7 weeks for full LS-clone parity vs 1-day LS deploy.

## Options considered

### A. Deploy Label Studio CE (Python/Django)

Label Studio CE is the dominant FOSS labeling platform (~22k stars, Apache 2.0,
HumanSignal-backed, mature 5+ years). Helm chart available; Postgres backend;
OIDC integration.

**Pros:**
- Production-ready, no implementation effort (~1 day to deploy)
- Mature feature set: custom XML labeling interfaces, IAA (Cohen's κ /
  Krippendorff α), versioning, snapshots, multi-reviewer queues, ML-assisted
  labeling, plugin ecosystem, REST API + SDK
- Reproducibility-friendly for academic publication ("we used Label Studio CE")
- Active maintenance, community-found bug fixes

**Cons:**
- Adds Python/Django service to Asgard's Rust-first backend
- Separate Postgres pod (~1-2 GB RAM)
- OIDC bridge needed to integrate with Yggdrasil (Asgard's auth)
- LS multi-tenant model differs from Asgard's tenant-isolation pattern
- Long-term: dependency on upstream (LS schema, breaking changes, security
  patches all on their cadence)

### B. Build full Label Studio replacement in Rust

A from-scratch Rust labeling platform with feature parity to Label Studio.

**Pros:**
- Pure Asgard Rust-first stack
- Full ownership of roadmap

**Cons:**
- 5-7 weeks of dedicated engineering (per estimate vs LS feature checklist)
- Researched 2026-05-06: **no production-grade Rust-native labeling platform
  exists in the ecosystem.** Highest-star Rust labeler is `quickner` at 22 stars
  (single-user CLI, stale Feb 2024). Closest equivalents: `rvimage` (8 stars,
  CV bbox only), `nktkt/labeler` (0 stars, ratatui terminal toy). No
  Argilla equivalent in Rust. No Leptos/Yew/Dioxus production labeling app.
- High risk of shipping half-baked tool while we'd still be missing IAA,
  ML-assisted labeling, versioning, plugin ecosystem
- 5-7 weeks blocks Sprint 39 LoRA, which is the highest-EV next move per
  Sprint 43 closure (model-swap ceiling empirically confirmed at ~50%)

### C. Build minimal "Mimir Curator" inside Mimir Dashboard *(chosen)*

A "Training Data Review" page added to existing Mimir Dashboard, with
supporting endpoints in Mimir Axum backend. Not a Label Studio replacement —
a focused review form for the workflow Asgard actually needs.

**Pros:**
- Aligns with Asgard policy: Rust backend (Axum, extends existing routes),
  TypeScript frontend (Next.js Dashboard, allowed exception per
  `MultiAgent_Architecture_Plan.md` §3 stack policy)
- Tight integration: reuses `eval_scores` schema for cross-references,
  Yggdrasil JWT for SSO, X-Tenant-Id middleware for tenant isolation, single
  DB for unified audit trail
- Familiar UI for medical leads (already use Mimir Dashboard for evals)
- Custom rubric exact-fit to Asgard medical Q-A workflow
- ~1.5-2 weeks implementation (vs 5-7 for full clone)
- Long-term: own roadmap, no upstream dependency

**Cons:**
- 1.5-2 weeks slower than LS (1 day deploy)
- Will not have IAA real-time computation (defer to manual export-script if
  needed for 200-pair initial set)
- No multi-modal labeling (Sprint 45+ MedGemma multimodal radiology will need
  scope extension; bounded refactor when that comes)
- No active learning / ML-assisted labeling (overkill at our scale)
- No plugin ecosystem (acceptable — medical Q-A workflow is domain-specific)
- We own every bug

## Why C was chosen over A

The framing "deploy Label Studio vs build Label Studio" is a false dichotomy.
We don't need 85% of Label Studio's feature surface. The features we *do* need
are essentially a specialized review form — and that's a 1.5-2 week build, not
a 5-7 week clone. Once that reframing landed, the trade-off vs A's 1-day deploy
became:

- 2 weeks delay vs LS deploy (manageable; Sprint 39 LoRA has multi-week
  predecessor work anyway)
- Zero ongoing Python/Django ops burden
- Zero OIDC bridge complexity
- Long-term roadmap fully owned

The 2-week delay is bounded; the avoided complexity is ongoing.

## Why C was chosen over B

Option B's premise — that we'd need to build a Label Studio equivalent — was
wrong. Even with the constraint of Rust-first, the answer is to build *less*,
not to clone the same scope in Rust. C is "Rust where it matters (backend,
business logic), TypeScript where the policy already allows (Mimir Dashboard
frontend)." Pure Rust-purity (Leptos + WASM frontend) would add weeks for no
clear benefit, given the dashboard is already TS.

## Implementation scope

See Sprint 39 Phase 0 backlog (B-30a..e) in
[`Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md`](../../../Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md).

| Layer | Estimate | Output |
|---|---|---|
| DB migration (`training_corpus_items` table) | 1 day | `migrations/2026xxx_training_corpus_items.sql` |
| Mimir backend Axum routes (`/api/v1/training/datasets`) | 4-5 days | ~600-800 LOC Rust |
| Mimir Dashboard page (`/training/curator/projects/:id`) | 4-5 days | ~400-600 LOC TS/React |
| JSONL export streaming endpoint | 1 day | ~100 LOC Rust |
| Dogfood pass (50 seed pairs reviewed) | 1 day | ≥1 medical lead validates UX |
| **Total** | **~1.5-2 weeks** | ~1,500 LOC |

## Out-of-scope (deferred to Sprint 50+ Curator v2 if labeling becomes ongoing operational concern)

- Real-time inter-annotator agreement (Cohen's κ live UI display) — manual
  export script for 200-pair set is sufficient for Sprint 39
- Multi-modal labeling (image, audio, video) — Sprint 45+ if MedGemma
  multimodal radiology lands
- Active learning / ML-assisted seed (model predictions as suggested ratings)
- Plugin / extension framework — domain-specific workflow, plugins don't help
- Standalone deploy / SaaS-ification — internal tool only
- Project/workspace management UI — single project ("Eir LoRA") per tenant

## Revisit triggers

Re-evaluate this decision if any of these become true:

1. **Curator dev exceeds 3 weeks** — scope-creep guard. If we're at 3 weeks
   and not shipping, pause and reconsider Label Studio deploy.
2. **Labeling becomes top-3 ongoing operational concern** — Sprint 50+, if
   we're labeling tens of thousands per quarter across multiple modalities.
   At that point evaluate Curator v2 (full Asgard-native platform) vs adopting
   Label Studio after all.
3. **Multi-modal labeling needed sooner than Sprint 45** — extending Curator
   to image/audio is bounded but adds weeks; LS is multi-modal out of the box.
4. **Multi-tenant labeling pattern diverges** — if customer hospitals want to
   label their own data with their own rubrics, the tenant-isolation pattern
   gets complex. LS's multi-tenant model is more mature.

## References

- Research finding (no Rust-native LS alternative exists): see chat log
  2026-05-06, agent search across GitHub for "rust label studio alternative",
  "rust annotation tool", "rust dataset labeling" — top result `quickner` at
  22 stars, no others above weak-match threshold.
- Asgard stack policy: [`MultiAgent_Architecture_Plan.md` §3](../../../Asgard/docs/roadmap/MultiAgent_Architecture_Plan.md)
- Sprint 39 plan: [`Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md`](../../../Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md)
- Sprint 43 closure (driver for Sprint 39 priority): same doc, Sprint 43 section
