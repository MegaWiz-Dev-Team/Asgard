# tyr-archive K8s manifests

Deployment for the `tyr-archive` daemon (Rust binary at `Tyr/tyr-archive/`).
**Not applied automatically** — operators run `kubectl apply -f .` per
[runbook.md §1](../../../../docs/technical/cloud-archive/runbook.md).

## Files

| File | Purpose |
|---|---|
| `00-namespace.yaml` | `asgard-archive` namespace |
| `01-secrets.yaml` | shapes for `tyr-archive-gcp-sa`, `tyr-archive-license`, `tyr-archive-wazuh` — placeholder values, replace before apply |
| `02-configmap.yaml` | `catalog.toml` ConfigMap for the daemon |
| `10-cronjob-daily.yaml` | Tyr alerts/audit/fim + every other dataset, fires 02:00 BKK |
| `11-cronjob-hourly-bifrost.yaml` | Bifrost frames, fires xx:55 every hour |

## Prereqs

1. `tyr-archive:0.1.0` image must exist on every node (build via `Tyr/tyr-archive/Dockerfile`).
2. Real `tyr-archive-gcp-sa` Secret populated from Vault (issued by Megawiz ops).
3. Real `tyr-archive-license` Secret populated with a Yggdrasil-signed JWT.
4. `bifrost-data-pvc` must be readable from the `asgard-archive` namespace (PV-level binding decision).
5. `gs://asgard-archive` bucket must exist (already does, see [bucket-layout.md](../../../../docs/technical/cloud-archive/bucket-layout.md)).
6. For CMEK datasets (bifrost-frames, eir, mimir, syn) — KMS keyring + crypto key created in `asia-southeast1` and SA bound `cloudkms.cryptoKeyEncrypter`. Phase C task.

## Verify

```bash
kubectl get cronjobs -n asgard-archive
# Manually trigger the daily run for testing:
kubectl create job --from=cronjob/tyr-archive-daily \
  tyr-archive-daily-manual-$(date +%s) -n asgard-archive
kubectl logs -n asgard-archive job/tyr-archive-daily-manual-<ts>
```

## Decommission

```bash
kubectl delete -f .
# Bucket data is retained per lifecycle policy. SA + license rotate via vault.
```
