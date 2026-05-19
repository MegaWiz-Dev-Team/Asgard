# Archive Runbook

Operational procedures for the `tyr-archive` daemon. Audience: Megawiz ops + customer Mac mini admin (read-only sections only).

## 1. First-time setup (per customer Mac mini)

Pre-req: customer signed Commercial license DPA; Megawiz ops has GCP `asgard-489513` access; customer KMS keyring exists (if PHI tenant).

```bash
# (Megawiz ops, on workstation with GCP access)
# 1. Provision per-tenant service account
gcloud iam service-accounts create tyr-archive-uploader-<tenant_id> \
  --project=asgard-489513 \
  --display-name="Archive uploader for <tenant_id>"

# 2. Bind write-only IAM with prefix condition
gcloud storage buckets add-iam-policy-binding gs://asgard-archive \
  --member="serviceAccount:tyr-archive-uploader-<tenant_id>@asgard-489513.iam.gserviceaccount.com" \
  --role=roles/storage.objectCreator \
  --condition='expression=resource.name.startsWith("projects/_/buckets/asgard-archive/objects/tenants/<tenant_id>/"),title=write_only_own_tenant'

# 3. Issue SA key, seal in customer Vault
gcloud iam service-accounts keys create /tmp/sa-key.json \
  --iam-account=tyr-archive-uploader-<tenant_id>@asgard-489513.iam.gserviceaccount.com
kubectl -n vault exec deploy/vault -- vault kv put \
  secret/<tenant_id>/archive sa_key=@/tmp/sa-key.json
shred -u /tmp/sa-key.json

# 4. Issue commercial license JWT (signed by Yggdrasil RS256)
yggdrasil issue --aud tyr-archive --tenant <tenant_id> --tier commercial \
  --features cloud-archive --exp 365d > /tmp/license.jwt
kubectl -n vault exec deploy/vault -- vault kv put \
  secret/<tenant_id>/archive license_jwt=@/tmp/license.jwt
shred -u /tmp/license.jwt
```

```bash
# (customer Mac mini)
# 5. Deploy tyr-archive
kubectl apply -f Asgard/k8s/04-security/tyr/archive/  # built once tyr-archive ships

# 6. Validate
kubectl -n asgard-archive logs job/tyr-archive-init-check
# Expect: "license=commercial features=[cloud-archive] valid_until=2027-05-19"
# Expect: "test write to gs://asgard-archive/tenants/<tenant_id>/_meta/init-probe.json SUCCESS"
```

## 2. Daily health check

```bash
# Confirm yesterday's jobs ran
kubectl get cronjobs -n asgard-archive
kubectl get jobs -n asgard-archive --sort-by=.metadata.creationTimestamp | tail -10

# Inspect the latest catalog manifest in GCS
gsutil cat gs://asgard-archive/tenants/<tenant_id>/_meta/catalog.json | jq '.last_run_per_dataset'

# Tyr alerts for archive failures
curl -sk https://wazuh-indexer:9200/wazuh-alerts-*/_search?q=rule.id:ASGARD-ARCHIVE-FAIL+AND+@timestamp:[now-24h+TO+now]
```

If any dataset has `last_run_per_dataset.<id>.status == "failed"`, escalate to step 3.

## 3. Investigate a failed upload

```bash
# Find the failing pod
FAIL=$(kubectl get jobs -n asgard-archive -o json | jq -r '.items[] | select(.status.failed > 0) | .metadata.name' | head -1)
kubectl logs -n asgard-archive job/$FAIL --tail=200

# Common failure classes (logs match these):
#   "license expired"          → renew JWT (see §6)
#   "skuggi gate rejected"     → PII leak detected, see §4
#   "gcs 403"                  → IAM drift, re-bind SA
#   "gcs 5xx + 3 retries"      → GCS transient, will catch up tomorrow
#   "source unreachable"       → upstream service down, fix it first
```

## 4. Skuggi gate rejection

If Skuggi blocks an upload (a PII/PHI string was found in a payload that shouldn't have it), the file is NOT uploaded. The pod logs the rejection with redacted line + row counts.

**Do not bypass.** The whole point of the gate is to stop accidental exfiltration.

Triage:
```bash
# Find the rejected payload locally (kept on Mac mini for 24h then purged)
ls /var/lib/tyr-archive/quarantine/
# Inspect the Skuggi reason
cat /var/lib/tyr-archive/quarantine/<file>.skuggi-report.json
```

If the rejection is correct → fix the upstream so PII doesn't leak into that stream. Re-run.
If false positive → file Skuggi tuning issue and tag `skuggi-tuning`. Do NOT add a bypass exception in tyr-archive config.

## 5. Restore

### 5a. Read-only browse (no decrypt)

```bash
# Megawiz ops can list any tenant's prefix to see what exists
gsutil ls -r gs://asgard-archive/tenants/<tenant_id>/tyr/alerts/2026/05/

# Cannot read content without the customer's KMS key for CMEK objects
gsutil cat gs://asgard-archive/tenants/<tenant_id>/eir/db-dumps/2026/05/19/openemr-2026-05-19.sql.zst
# → "Permission denied" because Megawiz lacks cloudkms.cryptoKeyDecrypter on customer key
```

### 5b. Full restore of one dataset (requires customer KMS access)

```bash
# (run on customer Mac mini with proper Vault unsealing first)
TENANT=asgard_medical
DATASET=eir-openemr-db
DATE=2026-05-19

tyr-archive restore \
  --tenant $TENANT \
  --dataset $DATASET \
  --date $DATE \
  --output /var/lib/asgard-restore/$DATE/

# For PHI datasets (CMEK), restore-time SA needs:
#   roles/storage.objectViewer on prefix
#   roles/cloudkms.cryptoKeyDecrypter on tenant key
# Issued on demand via:
gcloud iam service-accounts create restore-$TENANT-$(date +%s) --project=asgard-489513
# bind with 24h IAM Condition expiry
```

### 5c. Restore database

```bash
# OpenEMR DB
zstd -d openemr-2026-05-19.sql.zst | \
  kubectl -n asgard-medical exec -i deploy/mariadb -- mariadb -uroot -p$PW openemr

# Mimir MariaDB
zstd -d mimir-2026-05-19.sql.zst | \
  kubectl -n asgard-infra exec -i deploy/mariadb -- mariadb -uroot -p$PW mimir

# Qdrant collection
gsutil cp gs://asgard-archive/tenants/$TENANT/mimir/qdrant/2026/05/19/icd10-th.snapshot .
curl -X PUT 'http://qdrant:6333/collections/icd10-th/snapshots/recover?wait=true' \
  -F snapshot=@icd10-th.snapshot

# Neo4j (idempotent re-import is the canonical path)
zstd -d primekg-dump.cypher.zst | \
  kubectl -n asgard-infra exec -i deploy/neo4j -- cypher-shell -u neo4j -p $PW
# Alternative: re-run primekg_import.sh against the kg.csv (per `mimir_guideline_lineage_plan` and the original backup-shared-kbs note)
```

### 5d. Restore Bifrost frames for a specific patient session

```bash
SESSION_ID=...
# Frames are organized by date — search by metadata
gsutil ls "gs://asgard-archive/tenants/$TENANT/bifrost/frames/2026/05/*/${SESSION_ID}.mv2"
gsutil cp "gs://asgard-archive/tenants/$TENANT/bifrost/frames/2026/05/19/${SESSION_ID}.mv2" \
  /tmp/restored/
# Then bring up Bifrost replay tool to inspect frame-by-frame
```

## 6. Key + license rotation

### Quarterly SA key rotation
```bash
# 1. Issue new key
gcloud iam service-accounts keys create /tmp/sa-new.json \
  --iam-account=tyr-archive-uploader-<tenant_id>@asgard-489513.iam.gserviceaccount.com

# 2. Vault update (versioned KV; old key kept for 24h)
vault kv put secret/<tenant_id>/archive sa_key=@/tmp/sa-new.json

# 3. Restart tyr-archive to pick up new key
kubectl -n asgard-archive rollout restart deployment/tyr-archive

# 4. Wait 24h, delete old key
gcloud iam service-accounts keys delete <OLD_KEY_ID> \
  --iam-account=tyr-archive-uploader-<tenant_id>@asgard-489513.iam.gserviceaccount.com

shred -u /tmp/sa-new.json
```

### Yearly license JWT rotation
```bash
# Issued by Yggdrasil ahead of expiry (90 days before)
yggdrasil issue --aud tyr-archive --tenant <tenant_id> --tier commercial \
  --features cloud-archive --exp 365d > /tmp/license-new.jwt
vault kv put secret/<tenant_id>/archive license_jwt=@/tmp/license-new.jwt
kubectl -n asgard-archive rollout restart deployment/tyr-archive
shred -u /tmp/license-new.jwt
```

## 7. Disaster scenarios

### 7a. Mac mini lost / stolen / fried

1. Power up replacement Mac mini.
2. Run `./scripts/deploy-all.sh` per `asgard_complete_deploy_script` (~5-15 min).
3. Recover tenant per `asgard_tenant_recovery` — `Mimir/scripts/recover-asgard-tenant.sql`.
4. Restore Eir/OpenEMR DB from latest archive (§5c).
5. Restore Mimir state from latest weekly snapshot + replay forward from latest Bifrost frames + Tyr alerts.
6. Verify catalog: `tyr-archive verify --tenant <id> --since-days 7`.
7. Issue NEW SA key + license JWT (assume old Mac mini compromised). Old SA key is revoked.

RTO target: 4 hours for non-PHI data; 8 hours including PHI restore (CMEK key access + DB import time).

### 7b. T7 Shield disconnected mid-archive

`tyr-archive` is resumable. Next cron picks up where it left off using upload tracker in `/var/lib/tyr-archive/state/<dataset>.last`. No re-upload of completed objects (idempotent based on object_id sha256).

### 7c. Bucket deleted / IAM compromise / suspected exfil

GCS Bucket Lock prevents deletion within the retention window — bucket cannot be deleted.

If suspected: rotate every tenant's SA key immediately (§6), revoke compromised principal in GCP audit logs, file incident per `asgard_incident_docs` convention.

## 8. Decommissioning a tenant

When a customer leaves:

```bash
# 1. Stop archive (immediate)
kubectl -n asgard-archive scale deployment tyr-archive --replicas=0

# 2. Revoke SA
gcloud iam service-accounts disable \
  tyr-archive-uploader-<tenant_id>@asgard-489513.iam.gserviceaccount.com

# 3. (per contract) — delete data OR keep retention
# Option A: customer requests deletion → cannot delete before retention period (Bucket Lock)
#   → mark with deletion-pending lifecycle, document for customer
# Option B: customer agrees to retain through retention window
#   → leave in place, lifecycle deletes when due
gsutil retention temp set 1d gs://asgard-archive/tenants/<tenant_id>/**  # only after Bucket Lock expires

# 4. After retention expiry + lifecycle deletes, revoke SA + delete KMS key
gcloud kms keys versions destroy <version> \
  --location=asia-southeast1 \
  --keyring=<tenant_id> \
  --key=asgard-archive
```

## 9. Cost monitoring

```bash
# Per-tenant size + cost projection
gcloud storage du gs://asgard-archive/tenants/<tenant_id>/ \
  --summarize --readable

# Per-data-class breakdown
for cls in tyr bifrost eir mimir syn heimdall; do
  bytes=$(gcloud storage du -s gs://asgard-archive/tenants/<tenant_id>/$cls/ --format='value(size)' 2>/dev/null)
  printf '%-12s %s\n' "$cls" "$(numfmt --to=iec $bytes)"
done

# Billing — uses GCP billing export to BigQuery (if enabled)
bq query --nouse_legacy_sql '
SELECT service.description AS svc, sku.description AS sku, SUM(cost) AS usd
FROM `asgard-489513.billing_export.gcp_billing_export_v1_*`
WHERE invoice.month = FORMAT_TIMESTAMP("%Y%m", CURRENT_TIMESTAMP())
  AND service.description = "Cloud Storage"
GROUP BY 1,2 ORDER BY usd DESC;'
```

## 10. Audit / compliance evidence

To produce a compliance evidence pack for an auditor:

```bash
TENANT=asgard_medical
PERIOD_START=2026-01-01
PERIOD_END=2026-03-31

tyr-archive audit-pack \
  --tenant $TENANT \
  --since $PERIOD_START --until $PERIOD_END \
  --output /tmp/audit-pack-${TENANT}-Q1.tar
```

Pack contains:
- `catalog.json` snapshot at period end
- Object listing under each prefix with size + SHA-256 + WORM expiry
- Skuggi rejection summary (count + redacted samples)
- Tyr alert excerpts referencing `ASGARD-ARCHIVE-*` rule IDs
- IAM binding snapshot
- KMS key audit log (rotations + access)

Hand directly to auditor. Never includes actual archived content.
