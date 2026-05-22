# Archive Schedule

Cron cadence per data source, RPO targets, and how the daily windows interleave to avoid resource contention on a single Mac mini.

## Daily window (tenant-local 02:00 – 03:30)

Designed so a single Mac mini (64 GB RAM, ANE shared) doesn't compete with itself.

| Local time | Job | Source | Approx duration | Approx size/day |
|---|---|---|---|---|
| 00:55 (hourly) | bifrost-frames | `data/agents/*.mv2` | ~15s | ~15 MB |
| 02:00 | tyr-alerts | OpenSearch | ~30s | ~50 MB |
| 02:15 | tyr-audit | OpenSearch | ~30s | ~30 MB |
| 02:30 | tyr-fim | OpenSearch | ~30s | ~20 MB |
| 02:30 | heimdall-calls | Heimdall logs | ~20s | ~10 MB |
| 02:45 | syn-redactions | MariaDB tables | ~30s | ~10 MB |
| 03:00 | eir-openemr-db | MariaDB dump | ~3 min | ~80 MB |
| 03:30 | sentinel-verify | catalog.json + restore probe | ~1 min | n/a |

Heimdall and Syn run in parallel — both fast, no source overlap.

## Weekly window (Sunday 04:00 – 06:00)

Heavy snapshot day. Done on Sunday to avoid weekday operational load.

| Local time | Job | Source | Approx duration | Approx size/week |
|---|---|---|---|---|
| 04:00 | mimir-mariadb | MariaDB `mimir` schema | ~5 min | ~150 MB |
| 04:30 | mimir-qdrant | Qdrant snapshot API per collection | ~10 min | ~900 MB (all collections) |
| 05:00 | mimir-neo4j | cypher-shell dump | ~3 min | ~250 MB |
| 06:00 | platform-code-snapshots | tar of repos (megawiz machine only, not customer) | ~10 min | ~5 GB |

`mimir-qdrant` is the heaviest. Run separately from MariaDB to allow Qdrant to free its segment cache between collections.

## Real-time / streaming (no cron)

- **vardr-traces** — Tempo writes blocks continuously to GCS via S3-compatible backend. Not a cron job. Lifecycle managed by Tempo's `compactor.blocklist_poll`.

## On-demand (manual)

- **platform-eval-baselines** — after each canonical baseline locks (M1, S1, OCR, etc.), ops manually pushes the scoreboard + traces. Runbook command: `tyr-archive push platform eval --label <bench>-<YYYY-MM-DD>`.
- **platform-models** — after each fine-tune finishes (Sprint 55+). `tyr-archive push platform model --name <model> --version <semver>`.
- **emergency-snapshot** — before destructive operations (schema migration, mass re-ingest, model swap). `tyr-archive push emergency --label <reason>`.

## RPO targets

| Dataset | Target RPO | Achieved with daily cron |
|---|---|---|
| tyr-alerts | 24 h | ✓ |
| tyr-audit | 24 h | ✓ |
| bifrost-frames | 1 h | ✓ (hourly cron) |
| eir-openemr-db | 24 h | ✓ |
| mimir-* | 7 days | ✓ (weekly) — accept the lag because Mimir state is reconstructable from Eir + source docs |
| syn-redactions | 24 h | ✓ |
| heimdall-calls | 24 h | ✓ |
| vardr-traces | near real-time | ✓ via Tempo |

If RPO requirements tighten later (e.g., Bifrost moves to 5-min RPO), switch from K8s CronJob to a tyr-archive long-running mode with internal scheduling — same daemon, different invocation flag.

## Timezone policy

- **Cron** runs in `Asia/Bangkok` (tenant-local convenience).
- **Object keys** use UTC date (`<YYYY>/<MM>/<DD>`) for cross-tenant analytics consistency.
- Cron `0 2 * * *` Asia/Bangkok = 19:00 UTC previous day. The 02:00 BKK run on 2026-05-20 writes objects under UTC `2026/05/19/` if it processed yesterday's data.

This trades cron-readability for analyst-readability. Analysts can `gsutil ls tenants/*/tyr/alerts/2026/05/19/` and get every tenant's 2026-05-19 alerts regardless of where each is physically located.

## Contention with other Asgard workloads

| Time | What else runs | Conflict? |
|---|---|---|
| 00:00 – 02:00 | low — most LLM inference idle | none |
| 02:00 – 03:30 | archive jobs | other ops should AVOID this window |
| 03:30 – 06:00 | low | none |
| 06:00 – 08:00 | scheduled MLX warmup, model A/B sweeps | none (archive done by then) |
| 08:00 – 22:00 | active hours | nothing scheduled (besides hourly bifrost-frames at xx:55) |
| 22:00 – 24:00 | nightly eval runs (Mimir HealthBench-Pro) | none |

If contention is observed, archive jobs run at `nice 19` (lowest CPU priority) and use `ionice -c 3` so they yield to anything else.

## Job concurrency

`concurrencyPolicy: Forbid` on every CronJob. If yesterday's run is still uploading at today's start, today is skipped (logged + alert). Catches up next cycle. Bifrost hourly is exception — uses `concurrencyPolicy: Replace` because frame slices are independent.

## Failure / retry

- Each CronJob: `backoffLimit: 3`, `activeDeadlineSeconds: 1800` (30 min cap).
- On failure: emits Tyr alert with rule ID `ASGARD-ARCHIVE-FAIL`, severity 7.
- 3 consecutive failures → Tyr alert escalated severity 12; pages on-call (when on-call exists).
- Manual retry: `kubectl create job --from=cronjob/tyr-archive-alerts tyr-archive-alerts-manual-$(date +%s) -n asgard-archive`.

## Notes for operators

- **First run takes longer** — bucket may need to issue per-tenant SA token from Vault on first activation. Plan ~5 min extra on day 0.
- **Restoration windows**: never overlap restore + archive on the same dataset. The `tyr-archive lock <dataset>` command takes an advisory lock that blocks the next CronJob.
- **Holiday / freeze windows** (per `mega_care_deploy_pipeline` — Thursday merge freezes): archives keep running, they don't deploy code.
