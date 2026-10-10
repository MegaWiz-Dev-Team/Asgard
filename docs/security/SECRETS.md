# 🔐 Asgard Secret Management

> Status: **Sprint 51e — initial migration to K8s Secrets**.
> Long-term plan: Vault Agent Injector (Hashicorp Vault is already in cluster).

## Where secrets live now

All chart-managed secrets are centralized in a single K8s Secret named
`asgard-secrets` (override via `global.secretsName`). Subcharts reference
values via `secretKeyRef` — no plaintext rendering in deployment manifests.

| Key | Used by | Source of truth |
|---|---|---|
| `YGGDRASIL_MASTERKEY` | Yggdrasil (Zitadel) | Generated once during install. **Rotation invalidates all sessions.** |
| `YGGDRASIL_POSTGRES_PASSWORD` | Yggdrasil + infra Postgres | Generated once. Rotate via Postgres `ALTER ROLE`. |
| `YGGDRASIL_CLIENT_ID` | Mimir + Bifrost | Created in Zitadel admin UI per OIDC client. |
| `YGGDRASIL_CLIENT_SECRET` | Mimir + Bifrost | Regenerated in Zitadel admin UI ("Reset Secret"). |
| `MARIADB_ROOT_PASSWORD` / `MARIADB_PASSWORD` | infra MariaDB + Mimir | Generated once. Rotate via MariaDB `SET PASSWORD`. |
| `MIMIR_DATABASE_URL` | Mimir API | Derived from MARIADB_PASSWORD; redepoy mimir after rotation. |
| `NEO4J_PASSWORD` | Mimir API + Neo4j init | Set during Neo4j first-boot; rotate via cypher `ALTER USER`. |
| `HEIMDALL_API_KEY` | Bifrost + Mimir | Issued by Heimdall (host-side); rotate by re-running Heimdall key-gen. |
| `EIR_CLIENT_ID` / `EIR_CLIENT_SECRET` | Eir Gateway → Bifrost agent | OIDC app in Zitadel. |
| `EIR_MYSQL_ROOT_PASSWORD` | Eir (OpenEMR) container | Set once at OpenEMR install; rotate via MariaDB `ALTER USER 'root'@...`. Added 10 Oct 2026 (was plaintext `MYSQL_ROOT_PASS: root` in eir.yaml — public-repo audit). |
| `EIR_MYSQL_PASSWORD` | Eir (OpenEMR) container | Rotate via MariaDB `ALTER USER 'openemr'@...`. Added 10 Oct 2026 (was plaintext `MYSQL_PASS: openemr`). |
| `EIR_OE_PASSWORD` | Eir (OpenEMR) container, admin UI login | OpenEMR admin password set at install. Rotate via OpenEMR admin UI or `oe_pass_reset`. Added 10 Oct 2026 (was plaintext `OE_PASS`). |

Disabled but committed (will be active when laminar re-enabled):

`LAMINAR_API_KEY`, `LAMINAR_POSTGRES_PASSWORD`, `LAMINAR_POSTGRES_URL`,
`LAMINAR_CLICKHOUSE_PASSWORD`, `LAMINAR_CLICKHOUSE_RO_PASSWORD`,
`LAMINAR_NEXTAUTH_SECRET`.

## Two install modes

### Helm-managed (dev / test / lab cluster)

```yaml
# values-dev.yaml
secrets:
  create: true
  yggdrasil:
    masterKey: <random 32-byte hex>
    postgresPassword: <strong random>
    clientId: <from Zitadel UI>
    clientSecret: <from Zitadel UI>
  mariadb:
    rootPassword: <strong random>
    password: <strong random>
  # ... rest as needed
```

```bash
helm upgrade --install asgard ./charts/asgard \
  -n asgard \
  -f values-dev.yaml
```

### Externally-managed (prod / Vault / sealed-secrets / ESO)

```yaml
# values-prod.yaml
secrets:
  create: false   # don't let Helm own the Secret
```

Operator pre-creates `asgard-secrets` in the release namespace by whichever
mechanism (Vault Agent Injector → annotations on Deployment, External
Secrets Operator → `ExternalSecret` CR, etc.).

## Rotation runbook

### YGGDRASIL_CLIENT_SECRET (most common rotation)

When a client secret is suspected leaked or as part of routine rotation:

1. **Zitadel admin UI** → Project → Application → click "Reset Client Secret"
2. Copy the new secret immediately (shown only once)
3. Patch the K8s Secret:
   ```bash
   kubectl patch secret asgard-secrets -n asgard \
     --type='json' \
     -p='[{"op":"replace","path":"/data/YGGDRASIL_CLIENT_SECRET","value":"'$(echo -n "<NEW_SECRET>" | base64)'"}]'
   ```
4. Restart consumers (env vars are evaluated at pod start):
   ```bash
   kubectl rollout restart deploy/mimir-api deploy/mimir-dashboard deploy/bifrost -n asgard
   ```
5. Verify login flow at https://sso.asgard.internal still works.

### Database password rotation

Order matters — change DB-side first, then K8s, then restart consumers:

```bash
# 1. Change in DB
kubectl exec -n asgard-infra mariadb-0 -- mariadb -u root -p \
  -e "ALTER USER 'mimir'@'%' IDENTIFIED BY '<NEW_PW>'; FLUSH PRIVILEGES;"

# 2. Update K8s Secret
kubectl create secret generic asgard-secrets -n asgard \
  --from-literal=MARIADB_PASSWORD="<NEW_PW>" \
  --from-literal=MIMIR_DATABASE_URL="mysql://mimir:<NEW_PW>@mariadb.asgard-infra.svc:3306/mimir" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart consumers
kubectl rollout restart deploy/mimir-api -n asgard
```

### Bulk seed (fresh cluster)

```bash
kubectl create secret generic asgard-secrets -n asgard \
  --from-literal=YGGDRASIL_MASTERKEY="$(openssl rand -hex 32)" \
  --from-literal=YGGDRASIL_POSTGRES_PASSWORD="$(openssl rand -base64 32)" \
  --from-literal=YGGDRASIL_CLIENT_ID="<from-zitadel-ui>" \
  --from-literal=YGGDRASIL_CLIENT_SECRET="<from-zitadel-ui>" \
  --from-literal=MARIADB_ROOT_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=MARIADB_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=NEO4J_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=HEIMDALL_API_KEY="<from-heimdall-keygen>" \
  --from-literal=EIR_CLIENT_ID="<from-zitadel-ui>" \
  --from-literal=EIR_CLIENT_SECRET="<from-zitadel-ui>" \
  --from-literal=EIR_MYSQL_ROOT_PASSWORD="<strong random>" \
  --from-literal=EIR_MYSQL_PASSWORD="<strong random>" \
  --from-literal=EIR_OE_PASSWORD="<strong random>"
```

### EIR_MYSQL_ROOT_PASSWORD / EIR_MYSQL_PASSWORD / EIR_OE_PASSWORD (10 Oct 2026 containment)

These replace plaintext `MYSQL_ROOT_PASS` / `MYSQL_PASS` / `OE_PASS` env values that were
committed directly in `k8s/02-services/eir/eir.yaml`. The `eir` Deployment now reads them via
`secretKeyRef`, so `asgard-secrets` must carry all three keys before the next rollout of
`eir`, or the pod will fail to start:

```bash
kubectl create secret generic asgard-secrets -n asgard \
  --from-literal=EIR_MYSQL_ROOT_PASSWORD="<value>" \
  --from-literal=EIR_MYSQL_PASSWORD="<value>" \
  --from-literal=EIR_OE_PASSWORD="<value>" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Per the incident-response section below, prefer rotating these three credentials now that the
old values are public (git history), rather than carrying the leaked values forward unrotated.

## Security incident response (post-leak)

If a secret is committed to a public repo (e.g. as happened pre-Sprint 51e):

1. **Treat it as burned** — git scrub doesn't help; assume forks/clones cached it.
2. Rotate the upstream credential **first** (Zitadel UI / DB / Heimdall).
3. Update K8s Secret (patch or recreate).
4. Restart all consumers.
5. Audit access logs for unusual activity in the rotation window.
6. Open a private GitHub Security Advisory (no public issue) describing scope.

## What's still on the roadmap

- Vault Agent Injector (annotation-based) — eliminate static K8s Secrets entirely
- ExternalSecrets Operator + Vault as backend
- SOPS encrypted values files for GitOps deploys

These are tracked in [Asgard issue #TODO](https://github.com/MegaWiz-Dev-Team/Asgard/issues) as a follow-up to the Sprint 51e refactor.
