# MinIO credential rotation — remove the `minioadmin` default

**Why:** the security scan found the MinIO root credentials hard-coded as the
shipped default `minioadmin:minioadmin` — on the store that holds **FHIR + de-id
analytics (PHI)** for Asgard Nótt, plus `mimir-uploads`. Both the **server**
(`asgard-infra/minio`) root creds and **every client** used the default.
(CWE-798 / OWASP A02:2025.) MinIO is `ClusterIP`-only, so this is defense-in-depth
— but a default credential on a PHI store must be rotated.

The manifests now read credentials from a `minio-credentials` secret. This
rotation is a **coordinated, multi-namespace operation** — the server root
password and all clients must switch together or clients will fail to auth.

## Affected components (rotate together)

| Component | Namespace | Where |
|---|---|---|
| MinIO **server** (root) | `asgard-infra` | `Asgard/k8s/01-infra/minio/02-deployment.yaml` |
| mimir-sleep-api (Nótt) | `asgard` | `asgard-nott/k8s/mimir-sleep-api.yaml` + `s3sink.rs` |
| Mimir lab / core-ai | `asgard` | `Mimir/ro-ai-bridge/mimir-lab/src/storage.rs`, `…/config.rs` |

> Confirm the full list first: `grep -ril minioadmin` across all repos. Anything
> still using `minioadmin` after rotation will break.

## Rotation steps (minimal-downtime order)

```sh
# 1. Generate strong creds
ACCESS=minio-asgard
SECRET=$(openssl rand -base64 24)

# 2. Create the SAME secret in every namespace that talks to MinIO
for NS in asgard-infra asgard; do
  kubectl -n "$NS" create secret generic minio-credentials \
    --from-literal=access-key="$ACCESS" \
    --from-literal=secret-key="$SECRET"
done

# 3. Apply manifests (now reference the secret) + restart server, then clients
kubectl apply -f Asgard/k8s/01-infra/minio/02-deployment.yaml
kubectl -n asgard-infra rollout restart deploy/minio        # server now uses new root creds
kubectl apply -f asgard-nott/k8s/mimir-sleep-api.yaml
kubectl -n asgard rollout restart deploy/mimir-sleep-api    # client picks up new creds
# …repeat apply + rollout restart for every other client (Mimir, …)

# 4. Verify: client can write to the bucket, no auth errors
kubectl -n asgard logs deploy/mimir-sleep-api | grep -iE 's3|minio|denied|403' | tail
```

Between the server restart (step 3) and each client restart there is a brief
window where that client gets `403`; PHI writes should retry. Restart clients
immediately after the server.

## Notes

- **Don't commit real values.** The secret is created from the CLI (or sealed/
  Vault-managed); `00-secret.template.yaml` carries placeholders only.
- **Fail-closed:** `s3sink.rs` no longer falls back to `minioadmin` — a client
  with no creds now errors instead of silently using the default.
- **Hardening follow-up:** give each client a *dedicated* MinIO user scoped to
  its bucket (`mc admin user add` + a bucket-scoped policy) instead of sharing
  root. Then only the server holds root.
