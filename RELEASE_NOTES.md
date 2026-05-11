# Release Notes — Asgard AI Platform

## v1.3-alpha — Sprint 50 OCR Foundation (2026-05-11)

> Document OCR becomes a first-class capability across the platform. Clinicians can upload an image or PDF; Mimir extracts text via Syn's 4-tier smart-router (Path A), audits the call, enforces a per-tenant monthly cost cap, and surfaces everything in a new dashboard tab. Bifrost picks up an image-bearing chat path so any agent can ground on the document without explicit tool-calling. Cloud tiers remain hard-gated on PHI strict + Sprint 50b Skuggi PII guardrail.

### 🧩 Umbrella
- Helm umbrella `charts/asgard` — `version 0.2.0 → 0.3.0`, `appVersion 0.38.0 → 0.50.0`
- Sub-chart versions unchanged at this umbrella cut (per-service Helm bumps land on each service's own merge — same pattern as v1.2-alpha aligned all at once; this is a partial-roll release until Lane A merges)

### 📦 Service bumps (Sprint 50)

| Component | From | To | Manifest | Highlight |
|:--|:--|:--|:--|:--|
| 👁️ Syn (OCR) | 0.1.0 | **0.2.0** | `services/api/Cargo.toml` | B-50h.0 benchmark harness (Syn #5) — PII regex baseline F1 ≥ 0.91 |
| 🧠 Mimir bridge | 1.2.0 | **1.3.0** | `ro-ai-bridge/Cargo.toml` | B-50e audit, B-50b Path A, B-50m cost guard, admin endpoints |
| 🖥️ Mimir Dashboard | 1.2.0 | **1.3.0** | `ro-ai-dashboard/package.json` | B-50i `/playground` upload, OCR Cost Guard tab, Recent OCR Calls table |
| ⚡ Bifrost | 0.2.0 | **0.3.0** | `Cargo.toml` | B-50d transparent OCR path (Bifrost #13) |
| 🏰 Asgard docs | — | — | `docs/technical/e2e-ocr-lab-icd10.md` (NEW) + `scripts/e2e/lab_icd10.sh` (NEW) | B-50j E2E runbook + smoke script |

### 🏗️ Sprint 50 Lane A — what landed

- **B-50a/a.2/a.3** — 4-tier → 3-tier OCR stack (chandra retired; PaddleOCR + Typhoon-OCR + Gemini Flash/Pro)
- **B-50e** Mimir `ocr_documents` audit writer + per-tenant policy reader (Mimir #264)
- **B-50b** Path A — Mimir `/ocr/extract` delegates to Syn's 6-rule smart router (Mimir #265)
- **B-50c** REST endpoint with full request/response shape
- **B-50m** Cost guard middleware — pre-call USD estimate, monthly cap enforcement, PHI strict hard-block (Mimir #266)
- **B-50l** Tenant settings backend + admin policy GET/PATCH endpoints (Mimir #266/#267/#268)
- **B-50g** `ocr_extract` tool added to 5 clinical Eir variants (Mimir #269); insurance Sprint 52 tool seed pre-staged (B-50g+)
- **B-50d** Bifrost transparent OCR — `RunAgentRequest.image_base64` → Syn → marker-block prepend before swarm (Bifrost #13)
- **B-50i** Dashboard `/playground` drag-drop upload with editable OCR preview + engine/cost badges (Mimir #270)
- **B-50j** E2E runbook + bash smoke script chaining Syn OCR → Mimir agent chat → ICD-10 verification (Asgard #35)
- **B-50h.0** Initial OCR + PII benchmark harness — 30 Thai medical certificate cases, regex PII baseline F1 ≥ 0.91 (Syn #5)

### 🔒 Cloud tier remains gated

Tier 2 Gemini Flash and Tier 3 Gemini Pro implementations exist (B-50k partial) but every tenant ships with `ocr_phi_strict = true` and the cost guard hard-blocks cloud regardless of opt-in. Cloud OCR unlocks only when:
1. Sprint 50b Skuggi PII guardrail is in production
2. Tenant explicitly opts-in via the new admin policy endpoint
3. Monthly cloud budget > 0

This matches the insurance Sprint 54 gate (see `Mimir/docs/03_implementation_plans/03_16_Asgard_Insurance_Sprint_Plan.md`).

### 🩺 Privacy posture

- `Syn/data/` fixture set (30 Thai medical certificate cases incl. 10 image-backed) stays gitignored
- Derived gold-label JSON artifacts also gitignored
- B-50e audit table stores image_sha256 fingerprint, not raw bytes
- 3 gold-labeling bugs surfaced in the source CSV (T015/T019/T020); flagged for data owner correction before B-50h.1 (clinician partner data) lands

### 🚧 Sprint 50 not-yet-shipped (Lane B / follow-ups)

- **B-50f** Mimir Curator OCR review extension (clinician marks errors → corrections corpus)
- **B-50h.1** Clinician-partner test set (50-100 real medical documents under Vault mount)
- **B-50k** Gemini cloud adapter wire-up — implementable; gated on Skuggi ship
- **Sprint 50b** Skuggi PII guardrail (parallel sprint; gates B-50k + insurance v2)

### 📊 Open review train (Sprint 50 Lane A)

10 PRs across 4 repos: Mimir #264, #265, #266, #267, #268, #269, #270 · Bifrost #13 · Asgard #35 · Syn #5. Stacked review intentionally — Mimir #264 (audit row writer) is the root; subsequent PRs depend on its base schema.

### 🎯 Next (Sprint 51 / 50b / 52)

- **Sprint 50b** — Skuggi PII guardrail (Heimdall middleware; Thai PII regex + OpenCV face/text blur)
- **Sprint 52** — `asgard_insurance` foundation (parallel tenant + cross-tenant Hermodr gateway skeleton). See `Mimir/docs/03_implementation_plans/03_16_Asgard_Insurance_Sprint_Plan.md`.

---

## v1.2-alpha — Sprint 38 Release (2026-04-22)

> Unified platform bump aligning all 14 services, 11 Helm sub-charts, and the umbrella chart to a single consistent release on top of the OrbStack K8s migration delivered in Sprints 37–38.

### 🧩 Umbrella
- Helm umbrella `charts/asgard` — `version 0.1.0 → 0.2.0`, `appVersion 0.37.0 → 0.38.0`
- All 11 sub-charts bumped `0.1.0 → 0.2.0`

### 📦 Service bumps (+0.1.0 minor)

| Component | From | To | Manifest |
|:--|:--|:--|:--|
| 🛡️ Heimdall | 0.4.0 | **0.5.0** | `gateway/Cargo.toml` |
| 🧠 Mimir bridge | 1.1.0 | **1.2.0** | `ro-ai-bridge/Cargo.toml` |
| 🖥️ Mimir Dashboard | 1.1.0 | **1.2.0** | `ro-ai-dashboard/package.json` |
| ⚡ Bifrost | 0.1.0 | **0.2.0** | `Cargo.toml` |
| 🏥 Eir | 0.2.0 | **0.3.0** | `package.json` |
| 🐺 Fenrir | 0.1.0 | **0.2.0** | `pyproject.toml` |
| 🌳 Yggdrasil | 0.1.0 | **0.2.0** | `pyproject.toml` |
| 🛡️ Várðr | 0.4.0 | **0.5.0** | `Cargo.toml` |
| ⚖️ Forseti | 0.1.0 | **0.2.0** | `pyproject.toml` |
| 🔨 Mjölnir | 0.1.0 | **0.2.0** | `Cargo.toml` |
| 🐿️ Ratatoskr | 0.1.0 | **0.2.0** | `Cargo.toml` |
| 📨 Hermóðr | 0.1.0 | **0.2.0** | `Cargo.toml` |
| 🐦‍⬛ Huginn | 0.2.1 | **0.3.0** | `Cargo.toml` |
| 🐦 Muninn | 0.2.0 | **0.3.0** | `Cargo.toml` |

### 🏗️ Delivered in this release cycle (Sprints 37–38)
- **K3s + Helm + CI/CD** production deployment on Mac Mini (Sprint 37)
- **OrbStack migration** — Colima retired; launchd host now runs Heimdall Gateway + MLX backend + Várðr agent only (Sprint 38)
- **ISO 27001 log pipeline** — launchd `log-shipper` + `log-archiver` → Wazuh Indexer (Týr) with 365-day retention on T7 Shield

### 📊 Live K8s footprint (asgard namespace)
27 pods Running across 14 services; all `/healthz` probes green. Heimdall runs native on host (MLX).

### 🎯 Next (Phase 1 "Shield Wall", Apr 2026)
- ⚡ **Bifrost S8** — AI Guardrails (Thai PII filter, kill switch, hallucination check, handover queue)
- 📦 **Package Extract** — `@asgard/line-connector`, Gmail, TTS, BigQuery NLQ
- 👁️ **Syn** — new OCR/eKYC service (`:8600`)

---

## v1.1-alpha — Várðr & Docker Verified (2026-03-13)

### 🛡️ New Component: Várðr
Monitoring dashboard built in Rust (Axum) — real-time service health, Docker logs, and container metrics.

### 🐳 Docker Compose Verified
All 11 services build and start successfully with `docker compose up`:

| Service | Port | Status |
|:--|:--|:--|
| 🧠 Mimir API | :3000 | ✅ Healthy |
| 🖥️ Mimir Dashboard | :3001 | ✅ Running |
| ⚡ Bifrost | :8100 | ✅ Healthy |
| 🐺 Fenrir | :8200 | ✅ Healthy |
| 🌳 Yggdrasil | :8085 | ✅ Running |
| 🛡️ Várðr | :9090 | ✅ Healthy |
| 🗄️ MariaDB | :3306 | ✅ Healthy |
| 🐘 PostgreSQL | :5432 | ✅ Healthy |
| 🔍 Qdrant | :6333 | ✅ Running |
| 📦 Redis | :6379 | ✅ Running |
| 🕸️ Neo4j | :7474 | ✅ Running |

### 🔧 Fixes
- Yggdrasil masterkey: exactly 32 bytes + `--masterkeyFromEnv` + `--tlsMode disabled`
- Mimir API: `MARIADB_URL` → `DATABASE_URL`
- Bifrost healthcheck: `/health` → `/healthz`

### 📦 Components (7 + infra)
| Component | Version | Tests |
|:--|:--|:--|
| 🛡️ Heimdall | v0.4.0 | Benchmarked |
| 🧠 Mimir | Sprint 29 | 255+ |
| ⚡ Bifrost | v0.5.0 | 99 |
| 🐺 Fenrir | v0.2.0 | 35 |
| 🏥 Eir | v0.3.0 | 47 |
| 🌳 Yggdrasil | v0.2.0 | 19 |
| 🛡️ Várðr | v0.1.0 | 5 |
| **Total** | | **460+** |

---

## v1.0-alpha — Phase 1 Complete (2026-03-12)

> **Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.**

### 🏰 Platform Milestone
All 6 components have completed Sprint 1 or later. The entire platform can be started with a single `docker compose up` command.

### 📦 Components
| Component | Version | Tests | Highlights |
|:--|:--|:--|:--|
| 🛡️ Heimdall | v0.4.0 | Benchmarked | Multi-backend LLM Gateway (Ollama/MLX/Gemini/OpenAI) |
| 🧠 Mimir | Sprint 28 | 255+ | RAG Pipeline + Agent Builder + Dashboard |
| ⚡ Bifrost | v0.4.0 | 99 | ReAct + MCP + Multi-Agent + PSO |
| 🐺 Fenrir | v0.1.0 | 35 | MCP Server + FHIR R4 + Browser Use |
| 🏥 Eir | v0.3.0 | 47 | Rust API Gateway + Agent Tools + A2A |
| 🌳 Yggdrasil | v0.1.0 | 19 | Auth + JWT SDK |
| **Total** | | **455+** | |

### 📄 ISO 29110 Documentation
Every component has complete PM (Project Plan, Sprint Reports, Status) and SI (Requirements, Design, Traceability, Test Reports) documentation.

---

*Asgard เป็นของทุกคนแล้ว — Asgard belongs to everyone.*
