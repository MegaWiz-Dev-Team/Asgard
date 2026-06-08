# Asgard Analytics — Execution Plan

**Owner:** paripol@megawiz.co
**Date:** 2026-06-08
**Decision of record:** [ADR-024](../decisions/ADR-024-asgard-analytics-tenant-and-data-engine.md)
**Principles in force:** Rust-First • local-LLM-only for agents • TDD • SemVer • backup-before-state-change • Tyr/Skuggi in every PII path • single-tenant-per-box

---

## 0. Architecture at a glance

```
                          ┌────────────────────────── asgard-portal (React) ──────────────────────────┐
                          │  ECharts (charts)   MapLibre GL + PMTiles (maps)   notebook/exploratory view │
                          └───────────────▲───────────────────────────────────────────▲────────────────┘
                                          │ REST / SSE                                  │
              ┌───────────────────────────┴───────────────┐                ┌───────────┴───────────┐
              │ Bifrost                                    │                │ Evidence.dev          │
              │  bifrost-agent (ReAct, live)               │                │ (SQL+md research      │
              │  bifrost-jobs  (scheduled reports)         │                │  reports over DuckDB) │
              └───────────────┬────────────────────────────┘                └───────────┬───────────┘
                              │ tool calls (MCP)                                          │
                       ┌──────┴───────┐                                                   │
                       │ Hermodr      │  dataset_* · run_sql · plot · geo_* · stats_*     │
                       └──────┬───────┘                                                   │
          Heimdall ◀─ LLM ─── │ (gemma-4-26b, local only)                                 │
                              ▼                                                            ▼
         ┌────────────────────────────────────┐        ┌────────────────────────────────────────┐
         │ mimir-lab (Rust, Tier B)            │        │ mimir-geo (Rust, Tier B)                 │
         │  • dataset registry + ingest        │◀──────▶│  • GeoRust (geo/geos/proj/geozero)       │
         │  • schema inference                 │ shares │  • DuckDB spatial · h3o                   │
         │  • DuckDB engine (+spatial ext)     │ DuckDB │  • spatial-stats → Python sandbox        │
         │  • Parquet-on-disk + MinIO blobs    │        │    (PySAL / scipy), serialized           │
         └───────────────┬────────────────────┘        └────────────────────────────────────────┘
                         │ every upload / query / export
                ┌────────┴────────┐         ┌──────────────┐
                │ Skuggi PII scan │         │ Tyr audit log │
                └─────────────────┘         └──────────────┘

   Tenant boundary: asgard_analytics  (agent_configs rows: analyst-router/-sql/-geo/-stats/-report)
```

---

## 1. Data model (`mimir-lab`, new tables; tenant-scoped)

All tables carry `tenant_id` (= `asgard_analytics`). Migration via the existing Mimir migration tooling.

| Table | Purpose | Key columns |
|---|---|---|
| `datasets` | registry of every dataset | `id`, `tenant_id`, `name`, `source_type` (upload/cross_tenant/external), `schema_json`, `storage_uri`, `row_count`, `pii_status` (pending/clean/flagged), `created_by`, `created_at` |
| `dataset_versions` | immutable snapshots | `id`, `dataset_id`, `version`, `storage_uri`, `checksum`, `created_at` |
| `analyses` | saved query/notebook artifacts | `id`, `tenant_id`, `title`, `kind` (sql/notebook/geo), `spec_json`, `created_by`, `updated_at` |
| `report_jobs` | scheduled report config | `id`, `tenant_id`, `name`, `cron`, `analysis_id`, `evidence_template`, `last_run`, `status` |
| `geo_layers` | registered spatial layers | `id`, `dataset_id`, `geom_type`, `crs`, `bbox`, `feature_count` |

- **Storage:** raw + versioned data as **Parquet on disk**; large blobs/originals in **MinIO**;
  DuckDB is the query layer (attaches Parquet, no second copy). Agent configs stay in `agent_configs`.
- **PII gate:** a row may not move from `pii_status=pending` to queryable until Skuggi scan completes.

---

## 2. MCP tool catalog (Hermodr) — the agent's hands

| Tool | Backed by | Notes |
|---|---|---|
| `dataset_list` / `dataset_profile` | mimir-lab | schema, stats, null %, sample (PII-masked) |
| `dataset_upload` | mimir-lab + Skuggi | triggers PII scan; returns `pii_status` |
| `run_sql` | mimir-lab (DuckDB) | read-only role; row-cap + timeout; Tyr-audited |
| `plot` | portal/ECharts spec | returns a Vega/ECharts spec, not an image |
| `geo_buffer` / `geo_distance` / `geo_join` / `geo_choropleth` / `geo_h3` | mimir-geo | GeoRust + DuckDB spatial |
| `stats_describe` / `stats_correlate` / `stats_regress` | mimir-lab | cheap stats in-engine |
| `stats_moran` / `stats_lisa` / `stats_kriging` / `stats_pointpattern` | mimir-geo → Python sandbox | heavy; serialized, one at a time |
| `lit_search` | Hermodr → Semantic Scholar + arXiv | external literature; license-clean sources; **no scraping**; results adversarially verified before use |

Guardrails on every tool: read-only DB role, query timeout, row cap, Tyr audit, Skuggi-gated inputs.

---

## 3. Agent family (`analyst-*`, clone-Eir, local LLM only)

Seeded by `Mimir/scripts/seed-asgard-analytics-agents.sql`. UI tool labels **must match** the
runtime `kb_tool_label` names in Bifrost (Agent Studio has no validation — known footgun).

| Agent | Role / preamble focus | Tool allowlist |
|---|---|---|
| `analyst-router` | classify request → route to sql/geo/stats/report | (routing only) |
| `analyst-sql` | tabular Q&A, aggregation, charting | `dataset_*`, `run_sql`, `plot`, `stats_describe/correlate` |
| `analyst-geo` | GIS reasoning, maps, choropleth | `dataset_*`, `geo_*`, `plot` |
| `analyst-stats` | regression + spatial statistics | `dataset_*`, `run_sql`, `stats_*` |
| `analyst-research` | deep-research: fan-out → adversarially verify → cited synthesis; compose report | all read tools + `plot` + `lit_search` |

All on `gemma-4-26b` (Heimdall local). Heimdall already injects `enable_thinking:false` for local MLX.

**`analyst-research` design** — built on the **`deep-research` orchestration pattern** (fan-out
searches → verify each claim → cited synthesis), borrowing DARE's machine-readable **Research Spec**
(falsifiability audit + backtrack conditions) and literature→gap→hypothesis→stress-test structure —
**not** DARE's markdown-skill runtime. Runs as a Bifrost ReAct loop / workflow. Sources = Mimir RAG +
`lit_search` (Semantic Scholar/arXiv). **HITL by default** (proposes specs/hypotheses; human
approves). See §6 for the local-vs-cloud quality decision.

---

## 4. Phased delivery

> Effort is rough dev-days on the single Mac mini, serial where memory pressure forces it.

### P0 — Foundations & decision (≈1 day)
- [x] Land ADR-024 (Accepted 2026-06-09).
- [x] Update `OPEN_CORE_POLICY.md` Tier B table (mimir-lab/mimir-geo).
- [x] Author tenant seed `Mimir/scripts/seed-asgard-analytics-tenant.sql` (idempotent, rollback noted).
- [x] Author agent seed `Mimir/scripts/seed-asgard-analytics-agents.sql` (5 analyst-* agents; tool
      names flagged as placeholders pending P2 Hermodr registration).
- [x] **Backup step 0 (2026-06-09):** `scripts/backup-full-k8s.sh` → `/Volumes/T7 Shield/asgard-backup-2026-06-09`; gzip-tested OK incl. mariadb-asgard. (Known gaps: minio.tar.gz FAIL — distroless no-tar, needs helper-pod; Vault keys MANUAL.)
- [x] **Applied to live DB (2026-06-09).** ⚠️ **Tenancy is split across TWO MariaDB instances:**
  - `tenants` / `tenant_configs` → **asgard-infra** MariaDB → tenant seed applied (1 row).
  - `agent_configs` → **asgard** MariaDB → agent seed applied (5 analyst-* rows, published).
  - There is **no `tenants` table in the `asgard` MariaDB**; agent registry is `tenant_id`-column only.
- [x] Restarted `deploy/bifrost -n asgard` (rollout OK).
- [ ] Add shared-knowledge catalog row + UI page stub (P1 — when mimir-lab lands a KB surface).

### P1 — `mimir-lab` MVP (≈4–5 days)
- [ ] Scaffold Rust crate under Mimir family; wire `duckdb-rs` + spatial extension.
- [ ] Migrations for the 5 tables (§1). **TDD:** schema + ingest tests first.
- [ ] Ingest CSV/Parquet/Excel/GeoJSON → schema inference → Parquet catalog + MinIO.
- [ ] `run_sql` read-only path (role, timeout, row-cap) + `dataset_list/profile`.
- [ ] **Skuggi** dataset-upload PII scan policy + `pii_status` gate; **Tyr** audit on query/export.
- [ ] Tag `mimir-lab v0.1.0`.

### P2 — Agents + MCP (≈3–4 days)
- [ ] Hermodr tool definitions for `dataset_*`, `run_sql`, `plot`, `stats_describe/correlate`.
- [ ] Seed `analyst-*` agents; verify UI tool labels == runtime names (Agent Studio footgun).
- [ ] ReAct loop end-to-end: ask → route → run_sql → plot spec (gemma-4-26b local).
- [ ] E2E JSON-RPC verification of MCP tools (mirror Hermodr PrimeKG verification).

### P3 — Portal visualization (≈4 days)
- [ ] ECharts render of `plot` specs in `asgard-portal`.
- [ ] Exploratory/notebook view (query → table → chart, interactive).
- [ ] SSE streaming for ReAct reasoning trace (keep-alive >60s for Cloudflare).
- [ ] Dataset upload UI + PII-status surfacing.

### P4 — `mimir-geo` + spatial (≈5–6 days)
- [ ] Scaffold crate; GeoRust + DuckDB spatial + h3o; share DuckDB handle with mimir-lab.
- [ ] GIS ops (`geo_buffer/distance/join/choropleth/h3`) — **TDD** with fixture geometries.
- [ ] **Python sandbox** for spatial-stats (PySAL/scipy): isolated venv, resource-capped,
      **serialized** (memory-pressure rule), invoked only via `stats_moran/lisa/kriging/pointpattern`.
- [ ] MapLibre GL + PMTiles offline tiles in portal; choropleth + point layers (deck.gl if needed).
- [ ] Tag `mimir-geo v0.1.0`.

### P5 — Research agent + scheduled reports (≈5 days)
- [ ] Confirm local-vs-cloud research policy (§6); if cloud opt-in, wire Skuggi gate + oracle-budget cap.
- [ ] `lit_search` connector via Hermodr → Semantic Scholar + arXiv (license-clean, no scraping).
- [ ] `analyst-research` as Bifrost ReAct loop / workflow on the **deep-research pattern**
      (fan-out → adversarial verify each claim → cited synthesis); Research Spec artifact with
      falsifiability + backtrack conditions (DARE pattern, not its runtime). **HITL approval gate.**
- [ ] Evidence.dev project wired to DuckDB; report templates.
- [ ] `bifrost-jobs` cron → run analysis/research → render report → store + notify.
- [ ] `report_jobs` UI (GitHub-Actions-style, reuse Bifrost cron monitor pattern) + manual trigger.

### P6 — Cross-tenant adapter + hardening (≈2–3 days)
- [ ] Read-only cross-tenant metrics adapter, **default-off**, per-box toggle (ADR-009 safety).
- [ ] Load/latency check on Mac mini; ensure no parallel heavy ops; `sudo purge` headroom checks.
- [ ] Security review (`/security-review`) on upload + query + export surfaces.
- [ ] Docs + runbook + recovery drill.

**Total:** ~24–28 dev-days. P1→P3 is the usable vertical slice (tabular analytics + viz); P4 adds
spatial; P5 adds research agent + automation.

---

## 5. Open-source stack (license-checked)

| Layer | Component | License | Role |
|---|---|---|---|
| SQL/OLAP engine | **DuckDB** + spatial ext | MIT | core of mimir-lab; reads CSV/Parquet/Excel; ST_* |
| Rust dataframe (opt) | Polars / DataFusion | MIT / Apache-2.0 | if pure-Rust pipelines needed |
| Geo | **GeoRust** (geo/geos/proj/geozero/geoarrow-rs) | MIT/Apache | mimir-geo |
| Geo index | **h3o** | MIT | pure-Rust H3 hex indexing |
| Spatial stats | **PySAL**, scipy, statsmodels | BSD | sandbox only |
| Charts | **Apache ECharts** | Apache-2.0 | portal |
| Maps | **MapLibre GL JS** + **PMTiles/Protomaps** | BSD | offline on-prem tiles |
| Big geo layers (opt) | deck.gl | MIT | large point/hex layers |
| Reports | **Evidence.dev** | MIT | scheduled SQL+md reports |
| Research orchestration | **`deep-research` pattern** (in-harness) | — | template for `analyst-research`; fan-out + adversarial verify + cited synthesis |
| Research patterns (ref only) | **DARE**, STORM, GPT-Researcher | Apache/MIT | design reference (Research Spec, gap/hypothesis loop) — **not adopted as runtime** |
| Literature sources | Semantic Scholar MCP, arXiv | — | `lit_search`; license-clean; no scraping |

Avoid: PostGIS (GPL, heavy — default-off), Metabase (source-available — don't embed), DARE/Apify
scraping as a runtime (wrong runtime + cloud/autonomous, conflicts with on-prem HITL governance). All deps keep
their own terms; Asgard's own `mimir-lab`/`mimir-geo` code is AGPL-3.0 (Tier B).

---

## 6. Risks & open questions

1. **Mac-mini memory pressure** — DuckDB + gemma-4-26b + Python sandbox concurrently risks the
   2026-05-21 kernel-panic class. Mitigation: serialize heavy ops, purge before load, cap sandbox RAM.
2. **Cross-tenant adapter vs ADR-009** — must stay default-off per box; never a standing federation.
3. **PII in uploads** — Skuggi must gate *before* data is queryable; flagged datasets quarantined.
4. **Python supply chain** — pin + vendor the sandbox venv; no network at run time.
5. **Tile data size** — PMTiles for Thailand/region only, not global, to fit on-box storage.
6. **Research quality on local LLM** — deep research is reasoning-heavy; gemma-4-26b is
   quality-limited and KB-grounding variance is high (eir-kb-grounding finding). **Decision (default
   applied):** local-first; cloud LLM = opt-in, **Skuggi-gated, default-off**, research-path-only,
   under the Heimdall oracle-budget cap. Unlike medical/insurance, `asgard_analytics` *may* enable it
   per box — confirm before P5. Keep `analyst-research` HITL regardless of model.

## 7. Definition of done (MVP = P0–P3)
Analyst uploads a CSV → Skuggi-cleared → asks a question in the portal → `analyst-router` routes →
`run_sql` + `plot` → interactive ECharts chart, reasoning trace streamed, every step Tyr-audited,
all LLM calls local. Spatial (P4) and scheduled reports (P5) follow.
