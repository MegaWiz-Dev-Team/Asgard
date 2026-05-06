# ADR-002: MLOps Tracking — Mimir-Extend vs MLflow / Aim / Laminar

**Status:** Accepted
**Date:** 2026-05-06
**Context:** Sprint 39 Phase 2 (LoRA training) needs experiment tracking —
hyperparameters, training loss curves, eval metrics (HBp% on locked items),
adapter artifact paths, model lineage (parent corpus version → base model →
adapter → eval runs), promotion status (candidate → staging → production).
Volume is small: ~5-20 training runs per Sprint, ~50-100/year. Single ML
engineer team. Local MLX training on Apple Silicon (not distributed).

## Decision

**Extend Mimir with `lora_training_runs` table + `ai_models` lineage extension.
Track via Python wrapper around `mlx_lm.lora` that POSTs to a new Mimir REST
endpoint** (`/api/v1/training/runs/:id/log`).

## Options considered

### A. MLflow self-hosted (Python)

The de-facto MLOps standard. 22k stars, Apache 2.0, Databricks-backed.

**Pros:**
- Production-ready, mature feature set
- Model registry stage transitions (staging → production)
- Native integrations: PyTorch, HF Transformers, TensorBoard
- Reproducibility-friendly for academic/audit use
- ~3 days to deploy with Helm + bridge code

**Cons:**
- Python/Flask service violates Asgard Rust-first policy (1 more exception)
- Postgres + S3 backend adds 2 services to ops burden
- ML eng must learn 2 dashboards (MLflow UI + Mimir Dashboard)
- Most features overkill for 5-20 runs/sprint volume
- MLflow registry duplicates `ai_models` lifecycle that Mimir already manages

### B. opsml (Rust, demml.dev)

Closest Rust-native MLOps candidate found in 2026-05-06 ecosystem search.
Rust core + Python SDK; artifact registry with experiment cards.

**Pros:**
- Rust-native — aligns with Asgard policy
- Active development as of 2026-05

**Cons:**
- 35 stars, very early-stage adoption
- **Proprietary EULA** (not open source)
- Solo maintainer / small team risk
- Building on top of someone's side-project bet

### C. Mimir extension *(chosen)*

New `lora_training_runs` table in Mimir's existing MariaDB. Schema parallels
existing `eval_runs`/`eval_summary` pattern. Mimir Dashboard adds a
`/training/runs/:id` page reusing existing chart components.

**Pros:**
- Aligns with Asgard policy: Rust backend (Axum, extends existing routes),
  TS frontend (Mimir Dashboard, allowed exception)
- Same logic as ADR-001 (Curator) — single Mimir DB, single auth, single UI
- Tight integration: `lora_training_runs.dataset_version_id` FK to Curator's
  `training_corpus_items` snapshot; `ai_models.parent_model_id` for adapter
  genealogy
- ~5-6 days dev (vs ~3 days MLflow + 1-2 days bridge code = ~5 days +
  ongoing 1 service maintenance)
- Long-term: own roadmap, no upstream dependency

**Cons:**
- Will not have native PyTorch/HF Transformers `mlflow.log_*` integration
  (we use a wrapper script around `mlx_lm.lora`, so this is moot)
- Adapter registry stage transitions reimplemented locally (~50 LOC)
- No plugin ecosystem (acceptable — domain-specific)

### D. Aim (Python, lighter than MLflow)

Apache 2.0, ~5.6k stars, faster than MLflow on read.

**Pros:** lighter; pure tracking (no registry overhead)
**Cons:** same Python service burden as MLflow with smaller community

### E. Laminar (Rust LLM observability, lmnr.ai)

Rust-native; matches Asgard policy.

**Cons (scope mismatch):**
- Designed for production LLM call tracing + online evaluation, NOT training
  experiment tracking
- No native loss-curve / hyperparam-grid / adapter-lineage support
- Significant overlap with existing Mimir `eval_runs`/`eval_summary` would
  require migration choice
- Service availability concern — lmnr.ai inaccessible 2026-05-06 (single
  data point)
- Single-vendor risk (YC-stage company)

→ Re-evaluate at Sprint 50+ for production observability use case
(see Sprint 50+ section in
[`Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md`](../../../Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md)).

## Why C was chosen

Same logic as ADR-001 (Curator):
- Sprint 39 scope (~50-100 runs/year) doesn't justify a 3rd-party MLOps
  service's complexity
- Extending Mimir = 5-6 days work (vs 3 days deploy + ongoing service)
- Tight integration with Curator's corpus snapshots + Heimdall's `ai_models`
  registry produces a cleaner lineage story than bridging across 3 services
- Asgard's "single operational pane" pattern (Mimir Dashboard) is preserved

## Implementation scope

See Sprint 39 Phase 2 in
[`Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md`](../../../Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md).

Tasks B-32a (DB), B-32b (Python wrapper), B-32 (orchestrator script), B-34
(dashboard page).

| Layer | Estimate |
|---|---|
| DB migration | 1 day |
| Python wrapper for `mlx_lm.lora` | 2 days |
| Orchestrator shell script + reproducibility | 3 days |
| Dashboard page (loss curves, hyperparams, lineage tree) | 3-4 days |
| **Total** | **~9-10 days** within Sprint 39 Phase 2 budget |

## Out of scope (deferred)

- Stage-transition workflow with approvals (just `is_active` flag for now)
- Cross-tenant adapter fleet management UI
- Hyperparameter sweep orchestration (Sprint 39 = manual sweeps; OK for 5-20 runs)
- Native MLflow protocol compatibility for external tool integration

## Revisit triggers

Re-evaluate this decision if any of these become true:

1. **>50 training runs/quarter sustained** — manual tracking gets painful;
   MLflow's UI may pay back.
2. **Multiple ML engineers comparing experiments** — collaboration on Mimir's
   single dashboard could become friction; standard tool expectations.
3. **Cross-tenant LoRA fleet** — when N tenants each have their own adapter
   pipelines, lifecycle UI for fleet operations becomes a real ask.
4. **FDA/PDPA audit requires standard lineage format** — auditors prefer MLflow-
   format records over custom schemas.
5. **Hyperparameter sweep automation needed** — if Sprint 39+ requires Optuna /
   Ray Tune integration, MLflow has the protocol baked in.

## References

- ADR-001 (Curator): `Asgard/docs/architecture/ADR-001-Training-Data-Curator-Build-vs-Buy.md`
- Sprint 39 plan: `Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md`
- Rust MLOps research finding (no production-grade alternative exists, 2026-05-06):
  see chat log; agent searched GitHub for "rust mlops", "rust experiment tracking",
  "rust model registry", "rust ml pipeline" — best matches xvc (72 stars solo),
  opsml (35 stars proprietary), Lance (6.4k stars format only), ModelFox (1.5k stars
  abandoned 2024-08).
