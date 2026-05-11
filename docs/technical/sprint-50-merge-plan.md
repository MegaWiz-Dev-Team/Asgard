# Sprint 50 + 50b — Merge Plan

**Generated:** 2026-05-12
**Open PRs:** 22 across 5 repos
**Build status:** all release builds clean locally (see § Build verification)

---

## Why this doc

22 PRs is a lot of branches to merge. They're not all independent — Sprint 50b's PRs form a 5-deep stack in Mimir, and Heimdall #7 has a cross-repo path dep that requires Mimir #274 to merge first. Wrong order = avoidable rebases. This doc encodes the right order.

---

## Pre-merge gate (already done)

Every top-of-stack branch was built locally because GitHub PRs have **empty `statusCheckRollup`** — no auto CI gate. Local releases are the de facto check.

| Repo | Branch built | Result |
|---|---|---|
| Mimir | `feat/b-50b-8-skuggi-audit-history` | `cargo build --release` ✓ · `npm run build` 34/34 pages ✓ · my tests 26/26 ✓ |
| Heimdall | `feat/b-50b-skuggi-core-path-dep-on-anchored` | `cargo build --release` ✓ · 27/27 Skuggi tests ✓ |
| Bifrost | `feat/b-50d-bifrost-ocr-preprocess` | `cargo build --release` ✓ · 3/3 ocr_preprocess tests ✓ |
| Syn | `feat/b-50h-medical-cert-benchmark` | `python3 benchmarks/pii_bench.py` F1 ≥ 0.91 on all 5 categories ✓ |

Note: `cargo test --workspace` has **pre-existing breakage** in `mimir-core-ai/src/services/mcp_server.rs` + `evaluation/runner.rs` + `models/iam.rs` — not from this Sprint's work. Production builds are unaffected.

---

## Merge order

Branches must merge in this order to avoid cross-repo rebase loops:

### Phase 1 — Mimir Sprint 50 Lane A (one-by-one stack)

```
#264 (B-50e audit writer)              ← root of OCR stack
  ↓
#265 (B-50b Path A delegation)
  ↓
#266 (B-50m cost guard backend)
  ↓
#267 (OCR Cost Guard dashboard tab)
  ↓
#268 (/ocr/admin/recent + table)
  ↓
#269 (B-50g eir tool allowlist + insurance note)   ← can fork here (#270 too)
  ↓
#270 (B-50i /playground OCR upload)
  ↓
#271 (release-prep v1.3.0)             ← merges LAST
```

### Phase 2 — Sprint 50b text-PII stack (after Phase 1 lands)

```
#272 (PII test corpus migration)        ← can land anytime after #264
  ↓
#273 (admin corpus + score-batch API)
  ↓
#274 (skuggi-core unification + leak-runner + text-metrics)   ★ unblocks Heimdall #7
  ↓
#275 (Skuggi config UI + policy endpoint)
  ↓
#276 (audit history dashboard)
```

### Phase 3 — Heimdall (after Mimir #274 lands)

```
#6 (Tier 1b anchored patterns + leak contract)
  ↓
#7 (skuggi-core path dep refactor)     ← needs Mimir #274 on main for cross-repo path
```

### Phase 4 — Independent companions (merge anytime)

| Repo | PR | Title |
|---|---|---|
| Bifrost | #13 | B-50d transparent OCR |
| Bifrost | #14 | release-prep v0.3.0 (merge AFTER #13) |
| Asgard | #35 | B-50j E2E runbook + script |
| Asgard | #36 | umbrella release-prep v1.3-alpha |
| Syn | #5 | B-50h.0 benchmark harness |
| Syn | #6 | release-prep v0.2.0 (merge AFTER #5) |

---

## Merge commands

GitHub web UI works fine, but if you want CLI:

```bash
# Phase 1
gh pr merge 264 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 265 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 266 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 267 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 268 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 269 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 270 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 271 --repo MegaWiz-Dev-Team/Mimir --squash

# Phase 2
gh pr merge 272 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 273 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 274 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 275 --repo MegaWiz-Dev-Team/Mimir --squash
gh pr merge 276 --repo MegaWiz-Dev-Team/Mimir --squash

# Phase 3 (wait for #274 to land first!)
gh pr merge 6 --repo MegaWiz-Dev-Team/Heimdall --squash
gh pr merge 7 --repo MegaWiz-Dev-Team/Heimdall --squash

# Phase 4
gh pr merge 13 --repo MegaWiz-Dev-Team/Bifrost --squash
gh pr merge 14 --repo MegaWiz-Dev-Team/Bifrost --squash
gh pr merge 5  --repo MegaWiz-Dev-Team/Syn      --squash
gh pr merge 6  --repo MegaWiz-Dev-Team/Syn      --squash
gh pr merge 35 --repo MegaWiz-Dev-Team/Asgard   --squash
gh pr merge 36 --repo MegaWiz-Dev-Team/Asgard   --squash
```

GitHub's stacked-PR auto-update keeps things sane — after each merge, the next PR in the stack auto-rebases its base to `main`.

---

## Migrations to apply post-merge

After Mimir PRs land, two SQL migrations need to run against MariaDB:

```bash
# In the mimir-api pod or with a mysql client:
mysql -h <host> -u <user> -p<pass> mimir < \
  Mimir/ro-ai-bridge/migrations/sprint50_eir_ocr_allowlist.sql

# After insurance tenant migration is applied:
mysql -h <host> -u <user> -p<pass> mimir < \
  Mimir/ro-ai-bridge/mimir-core-ai/migrations/20260512000000_pii_test_corpus.sql
```

If the `pii_test_corpus.sql` depends on `tenant_configs.asgard_insurance` row existing first, apply the insurance-tenant migration before it (from the parallel-session work):

```bash
mysql -h <host> -u <user> -p<pass> mimir < \
  Mimir/ro-ai-bridge/mimir-core-ai/migrations/20260511000000_asgard_insurance_tenant.sql
```

---

## Deploy via Helm umbrella

After CI builds artifacts (or if deploying manually from local builds):

```bash
cd Asgard/

# Update tags in values.yaml (or pass --set)
helm upgrade --install asgard charts/asgard \
  --set mimir.image.tag=v1.3.0 \
  --set bifrost.image.tag=v0.3.0 \
  --set heimdall.image.tag=v0.5.0 \
  --set syn.image.tag=v0.2.0 \
  --namespace asgard
```

Asgard PR #36 already pins `version: 0.3.0` + `appVersion: "0.50.0"` in `charts/asgard/Chart.yaml`.

---

## Smoke test (post-deploy, OrbStack)

```bash
# 1. Health checks
curl https://mimir.asgard.internal/healthz
curl https://heimdall.asgard.internal/healthz
curl https://bifrost.asgard.internal/healthz

# 2. Skuggi corpus endpoint
curl -H "X-Tenant-Id: asgard_insurance" \
  https://mimir.asgard.internal/api/v1/admin/skuggi/corpus

# 3. Skuggi end-to-end leak gate
cargo run --bin skuggi-leak-runner -- \
  --mimir-url https://mimir.asgard.internal \
  --tenant-id asgard_insurance \
  --agent-id <some_eir_agent_id>

# 4. B-50j lab → ICD-10 chain
./Asgard/scripts/e2e/lab_icd10.sh path/to/lab_report.png

# 5. Dashboard sanity
open https://mimir.asgard.internal/admin/skuggi
open https://mimir.asgard.internal/analytics/llm    # OCR Cost Guard tab
```

---

## Skuggi guardrail status (post-merge)

| ID | Status |
|---|---|
| B-50b-1 schema | ✅ shipped sprint50 day-1 |
| B-50b-2 middleware (proxy.rs dispatch) | ✅ already in main |
| **B-50b-3** image PII (OpenCV YuNet) | ❌ Python sidecar; deferred |
| B-50b-4 text Tier 1 (8 categories) | ✅ Heimdall #6 + #7 + skuggi-core (#274) |
| B-50b-5 text Tier 2 (PyThaiNLP) | ✅ client + heuristic; sidecar deploy pending |
| B-50b-6 Skuggi config UI | ✅ Mimir #275 |
| B-50b-7 test set | ✅ Mimir #272 + Heimdall #6 leak contract |
| B-50b-8 audit history dashboard | ✅ Mimir #276 |

**7 of 8 done.** Only B-50b-3 (image PII via OpenCV sidecar) remains.

---

## Out of scope — Python cleanup (future)

Audit during this sprint flagged Python files to retire:
- `Mimir/scripts/icd10_lookup.py` — duplicates Hermodr's Rust impl
- `Bifrost/.bifrost_python_backup/` + its `test_*.py` — pre-rewrite legacy
- `Syn/benchmarks/pii_bench.py` — replaceable with thin Rust CLI on `skuggi-core`
- `Syn/benchmarks/metrics.py` — already replaced by `mimir-text-metrics` (#274); switch `run_bench.py` consumers

Total: ~4 small cleanup PRs anytime.
