# Asgard Cloud Archive

Off-box, write-once long-term storage of Asgard data on Google Cloud Storage Archive tier. Closes the "single Mac mini + local T7 only" failure mode for compliance retention, clinical accountability traces, SIEM audit, and disaster recovery.

## Status

| Item | Status |
|---|---|
| GCP project | `asgard-489513` (Megawiz, ref `asgard_gcp_project`) |
| Bucket | `gs://asgard-archive` (planned, not created) |
| Storage class | Archive ($0.0012/GB/mo, 365-day min) |
| License gate | Commercial tier only — AGPL build = feature disabled |
| Component | `tyr-archive` (Rust, submodule of Tyr per `feedback_no_new_norse_components`) |
| V1 scope | Tyr SIEM + Bifrost agent decision frames |
| V2 scope | Eir OpenEMR DB, Mimir RAG state, Syn redaction audit |
| V3 scope | Heimdall LLM call audit, Vardr traces, custom model artifacts |

## Documents

| File | Purpose |
|---|---|
| [bucket-layout.md](bucket-layout.md) | GCS prefix structure, per-tenant isolation, IAM scoping |
| [data-catalog.md](data-catalog.md) | Every data source — owner, location, sensitivity, retention |
| [schedule.md](schedule.md) | Cron cadence per source, RPO targets, cost projection |
| [runbook.md](runbook.md) | How to operate: install, monitor, restore, rotate keys |

## Why we built this

Pre-2026-05-19 backups were local-only:
- `~/asgard-backups/shared-kbs/` (Mac internal, ~3.7 GB for KB snapshots)
- `/Volumes/T7 Shield/asgard-backup-2026-05-10/` (external SSD, 7.6 GB, 9 days stale)

Single point of failure: theft / fire / Mac mini SSD failure / T7 disconnect (the 2026-05-17 Wazuh outage was an early warning — see `tyr_pvc_t7_shield` memory). Off-site, immutable, encrypted archive is the obvious fix and lets us hold per-tenant compliance retention (HIPAA-equivalent 7 yr, medical records 10 yr, OIC insurance 10 yr) without per-customer infrastructure.

## Key design decisions

1. **Single bucket, per-tenant prefix.** `gs://asgard-archive/tenants/<tenant_id>/<service>/...` — IAM Conditions restrict each customer's service account to its prefix. Avoids GCP-side bucket explosion as customer count grows.
2. **Megawiz owns the bucket; customer holds the encryption key.** CMEK (Customer-Managed Encryption Keys) for any tenant prefix containing PHI. Megawiz stores ciphertext only — zero-knowledge for compliance defensibility.
3. **Skuggi pre-flight on every upload.** Per `feedback_include_tyr_in_pii_designs` — anything leaving the box passes the PII guardrail first. Tier 1 text gate is already shipped (`asgard_skuggi_state` W1); image upload waits on W2/W3.
4. **Bucket Lock + Object Versioning = WORM.** Once written, objects are tamper-proof for retention period. Required for audit defensibility.
5. **License gate at daemon startup.** Yggdrasil RS256 JWT validated against `ASGARD_LICENSE_KEY` (per `asgard_jwt_auth_pattern`); `tier=commercial` enables the feature; AGPL build fails validation and the archive daemon refuses to start.
6. **Rust-first.** `tyr-archive` is a Rust binary per `asgard_rust_first_principle`. K8s CronJob runs it daily.

## What this is NOT

- **Not a sync tool.** Append-only. Once uploaded, objects are immutable until lifecycle deletes them.
- **Not a Vardr replacement.** Vardr is real-time observability; archive is post-hoc cold storage.
- **Not free.** Commercial license required. AGPL community users keep their data on-prem.
- **Not for HF-derived models.** All upstream public weights stay on local T7 + recorded in `model-registry.md` with URL + SHA-256. Only Megawiz-trained fine-tunes are archived.
- **Not for raw Syn images.** Per `syn_data_internal_only`, real medcert images NEVER leave the box. Only hashes + redacted output + audit metadata are archived.

## Quick links

- Reference memory: [asgard_gcp_project](../../../.claude/memory/asgard_gcp_project.md), [feedback_asgard_license](../../../.claude/memory/feedback_asgard_license.md)
- Backup script being replaced: [backup-shared-kbs.sh](../../../../Mimir/scripts/backup-shared-kbs.sh)
- Existing manual full backup: `/Volumes/T7 Shield/asgard-backup-2026-05-10/MANIFEST.md`
