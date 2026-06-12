# ADR-024: Asgard Analytics — Data-Analysis Tenant + Data/Geo Engine

**Status:** Accepted
**Date:** 2026-06-08 (accepted 2026-06-09)
**Deciders:** paripol@megawiz.co
**Scope:** New tenant `asgard_analytics` + two cross-cutting Mimir submodules
**Related:** ADR-009 (single-tenant Mac mini), ADR-010 (agents as boundaries / skills as expertise), ADR-012/014 (data-plane ownership = Mimir family), ADR-023 (open-core IP boundary), [feedback: tenant = domain not org], [feedback: include Tyr/Skuggi in PII designs]

## Context

Megawiz needs a capability to **analyze, visualize, research, and run spatial analysis** over three
kinds of data:

1. **External datasets** uploaded by an analyst (CSV / Parquet / Excel / GeoJSON).
2. **Cross-tenant Asgard operational metrics** (OCR / Eir / eval benchmarks already in
   `asgard_platform`, `asgard_medical`, `asgard_insurance`).
3. **External public / research data** (open data, epidemiology, geo layers).

Spatial scope is **both GIS** (lat/long, choropleth, distance/buffer, clustering) **and statistical
spatial** (Moran's I / LISA, kriging, point-pattern). Consumption is **human-analyst dashboard +
agent-driven (ReAct) + scheduled research reports**.

Two orthogonal questions had to be separated:

- **Capability (service):** where does the compute live? — answered by new submodules.
- **Isolation (tenant):** is "analytics" its own data/governance domain? — answered by a new tenant.

The three data sources include externally-sourced and uploaded data whose PII/governance regime is
**different from medical PHI**. Folding analytics into `asgard_medical` would pollute the PHI
boundary and force cross-tenant federation, which contradicts ADR-009 ("1 Mac mini per customer").

## Decision

Adopt a **two-part design** that keeps capability and isolation on separate axes.

> **Build analytics compute as cross-cutting Mimir submodules; isolate analytics data and agents
> behind their own thin tenant. Rust-first for the engines; Python only inside a sandbox for
> spatial statistics.**

### Part A — Services (capability, cross-cutting, Tier B / AGPL)

Two new submodules under the **Mimir** family (per ADR-012/014 data-plane ownership and the
"no new Norse components — extend as `<parent>-<submodule>`" rule):

- **`mimir-lab`** — dataset registry + ingestion (CSV/Parquet/Excel/GeoJSON) + schema inference +
  **DuckDB**-backed SQL/analytics engine. Pure Rust host (`duckdb-rs`); DuckDB `spatial` extension
  enabled. Reads files directly; persists a Parquet-on-disk catalog + MinIO blobs (both already in
  stack).
- **`mimir-geo`** — geospatial engine on **GeoRust** (`geo` / `geos` / `proj` / `geozero` /
  `geoarrow-rs`) + DuckDB spatial + **h3o** (pure-Rust H3). GIS ops in Rust; **statistical-spatial
  ops run in a sandboxed Python kernel (PySAL / scipy)** — a deliberate, scoped exception to the
  Rust-First Principle because the Rust spatial-stats ecosystem is immature (same precedent as
  mlx-lm for fine-tuning).

Both are **Tier B (AGPL-3.0 public)** per ADR-023 default for new components — they are commodity
analytical engines, not tuned domain IP or defenses. Any tenant may call them.

### Part B — Tenant (isolation, thin boundary)

Create tenant **`asgard_analytics`** (display name "Asgard Analytics"), parallel to
`asgard_medical` / `asgard_insurance` / `asgard_platform`, per "tenant = domain not org":

- **Agents** — an `analyst-*` family seeded as rows in `agent_configs` (clone-Eir pattern, **local
  LLM only** = gemma-4-26b): `analyst-router`, `analyst-sql`, `analyst-geo`, `analyst-stats`,
  `analyst-research`. Each has its own tool allowlist (separate from Eir). Agent configs + any tuned
  rulesets are **Tier C** (private, per-box tuned data) even though the engines are Tier B.
- **Guardrails** — a **Skuggi** dataset-upload PII-scan policy scoped to this tenant (separate from
  medical), and **Tyr** audit on every query / export. (Required by "include Tyr/Skuggi in PII
  designs".)
- **Shared-knowledge surface** — a row in `/api/v1/knowledge/shared` + UI page (required by "shared
  knowledge surface" rule; no silently-invisible KB).
- **Recovery script** — `Mimir/scripts/recover-asgard-analytics.sql` recreates tenant + agents
  (mirrors `recover-asgard-tenant.sql`).

### Cross-tenant federation (bounded)

`asgard_analytics` may read cross-tenant metrics **only via a read-only adapter that is toggleable
and default-off on customer boxes**. On the internal/dev box it behaves like `asgard_platform`
(cross-cutting, PII-free metrics). It must **not** become a permanent federation layer — that would
violate ADR-009.

### Research agent (`analyst-research`, deep-research pattern)

The "do research" requirement is served by `analyst-research`, built on the **`deep-research`
orchestration pattern** (fan-out searches → **adversarially verify each claim** → cited synthesis)
rather than a wholesale third-party engine. DARE (de-anthropocentric-research-engine) was evaluated
and **rejected as a runtime** — it is a Claude-Code markdown-skill arsenal assuming a frontier model
and "autonomous, without permission" operation, which is the wrong runtime (Asgard agents are
Bifrost ReAct loops on local gemma-4-26b) and conflicts with Asgard's humans-in-loop governance. We
**borrow its design patterns only**: the machine-readable Research Spec (with falsifiability audit +
backtrack conditions) and the literature → gap → hypothesis → stress-test structure.

- **Runtime:** Bifrost ReAct loop / workflow, **not** ported skills.
- **Sources:** Mimir RAG (internal corpus) + license-clean external connectors **Semantic Scholar +
  arXiv** via Hermodr (`lit_search`). **No web scraping** (Apify-style) — conflicts with on-prem/PII
  posture.
- **HITL by default:** the agent proposes specs / hypotheses; a human approves. It does not act
  autonomously.
- **Verify-everything:** every external claim is adversarially verified before it enters a report,
  matching Asgard's review ethos.

**Open sub-decision (flagged, default applied):** deep research on local gemma-4-26b is
quality-limited (reasoning-heavy; KB-grounding variance is high per the eir-kb-grounding finding).
Default policy = **local-first; cloud LLM is an opt-in, Skuggi-gated, default-off flag** scoped to
the research path only (mirrors insurance Skuggi-gating; cloud spend stays under the Heimdall oracle
budget cap). Unlike medical/insurance, `asgard_analytics` *may* enable the cloud research path per
box — to be confirmed before P5.

### Orchestration & UX

- **ReAct + scheduled** runs go through Bifrost (`bifrost-agent` live, `bifrost-jobs` cron) — no new
  orchestrator.
- **MCP tools** exposed via **Hermodr**: `dataset_list/upload/profile`, `run_sql`, `plot`,
  `geo_*` (buffer/distance/join/choropleth/h3), `stats_*` (describe/correlate/regress/moran/kriging),
  `lit_search` (Semantic Scholar + arXiv, for `analyst-research`).
- **Visualization** in `asgard-portal` (React): **Apache ECharts** (charts) + **MapLibre GL** +
  **PMTiles/Protomaps** offline tiles (on-prem, no token).
- **Scheduled research reports** via **Evidence.dev** (SQL + markdown over DuckDB), driven by
  `bifrost-jobs`.

## Alternatives Considered

1. **Service only, no tenant (rejected).** Analytics becomes a feature inside each existing tenant.
   Pollutes the PHI boundary, scatters PII policy, and forces cross-tenant federation that breaks
   ADR-009.
2. **Tenant only, stretch existing Mimir (rejected).** Still need the compute capability somewhere;
   bolting dataset/geo storage onto core Mimir without a submodule boundary muddies the data-plane
   ownership set in ADR-012/014.
3. **Extend `asgard_platform` instead of a new tenant (rejected).** `asgard_platform` is hash-only /
   PII-free for internal benchmarks; analytics ingests external + uploaded data that may contain PII,
   so it needs its own governance regime.
4. **PostGIS as the geo backend (rejected as default).** GPL-2.0, heavyweight relational dependency;
   DuckDB spatial + GeoRust cover the needs with a clean (MIT/Apache) license and Rust-first fit.
   Revisit only if relational geo at scale becomes a hard requirement.
5. **Python/pandas as the primary engine (rejected).** Violates Rust-First Principle; Python is
   confined to the sandboxed spatial-stats kernel only.

## Consequences

- **Positive:** clean PHI isolation; reusable analytics engines for every tenant; a productizable
  "analytics box" template; Rust-first/local-LLM/on-prem all preserved; license-clean OSS stack.
- **Negative / cost:** two new submodules to build + maintain; one sanctioned Python sandbox
  (supply-chain + memory-pressure surface — must serialize heavy ops per the Mac-mini memory rule);
  cross-tenant adapter needs careful default-off gating per box.
- **Open-core:** `mimir-lab` + `mimir-geo` engines → Tier B AGPL; `analyst-*` configs + rulesets →
  Tier C private per-box.

## Follow-ups

- Execution detail: [asgard-analytics-execution-plan.md](../strategy/asgard-analytics-execution-plan.md)
- Update `OPEN_CORE_POLICY.md` classification table with the two submodules.
- Update the Asgard pantheon map memory once submodules land.
