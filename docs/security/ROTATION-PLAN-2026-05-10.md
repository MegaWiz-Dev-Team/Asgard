# 🔄 Asgard Secret Rotation Plan — Sprint 51e Burn Recovery

**Trigger:** Sprint 51d open-core go-live made the Asgard repo public; chart templates and k8s manifests had committed plaintext secrets since commit `73a004f`. PR #31 (merged 2026-05-10) refactored the chart to read from a K8s Secret, but **the values previously committed to git are burned** and must be rotated.

**Status:** 📝 Plan drafted, **not yet executed.**

**Estimated total time:** ~90 min hands-on + ~30 min verification.
**Worst-case downtime:** Mimir login ~5 min × 2 (during OIDC + DB rotations).

---

## Execution order (dependency-aware)

The order below minimizes downtime and avoids lock-out scenarios. **Do not skip ahead.**

| # | Step | Type | Downtime | Reversible? |
|---|---|---|---|---|
| **0** | **Verify chart applied (PR #31)** ⚠️ | **prerequisite** | varies | yes |
| 1 | Pre-flight check + inventory | inspection | — | n/a |
| 2 | Heimdall API key | independent | none (host-side) | yes |
| 3 | Laminar API key | independent (disabled) | none | yes |
| 4 | Neo4j password | DB | ~2 min mimir restart | yes |
| 5 | MariaDB user password | DB | ~2 min mimir restart | yes |
| 6 | Postgres password (Zitadel DB) | DB | ~3 min Yggdrasil restart | yes |
| 7 | Yggdrasil OIDC client secrets (Mimir + Eir) | UI + Secret | ~2 min mimir+eir restart | yes |
| 8 | Yggdrasil masterkey | ⚠️ complex | ~10 min + re-encrypt | *partial* |
| 9 | Bulk-seed verification | inspection | — | n/a |

---

## Step 0 — Verify chart applied (PR #31) ⚠️ NEW

**Why this step exists:** PR #31 refactored the chart to read secrets via `secretKeyRef` / `envFrom`. **Merging the PR is not enough — the chart must be installed/upgraded into the cluster.** If the running Deployments still have plaintext `env:` values (pre-PR #31 state), patching `asgard-secrets` is a **no-op**: the inline plaintext wins over the Secret.

Verify zero drift before any rotation:

```bash
# All three should print 0. Non-zero = drift = chart not applied.
kubectl get deploy yggdrasil    -n asgard -o yaml | grep -c 'yggdrasil-secret\|yggdrasil-masterkey-change-me-ok'
kubectl get deploy mimir-api    -n asgard -o yaml | grep -c 'REDACTED-PW\|mimir_password\|jlQ7malc'
kubectl get deploy mimir-dashboard -n asgard -o yaml | grep -c 'jlQ7malc'
```

If any prints `>0`:

```bash
# Re-apply the chart (or kubectl-apply the raw manifests post-merge)
cd /path/to/Asgard
helm upgrade asgard ./charts/asgard -n asgard -f charts/asgard/values-dev.yaml
# OR if you use raw manifests:
kubectl apply -f k8s/02-services/yggdrasil/ -f k8s/02-services/mimir-api/ -f k8s/02-services/mimir-dashboard/
```

Re-run the verification — all three must print 0 before proceeding to Step 1. **Otherwise rotation will silently fail.**

---

## Step 1 — Pre-flight check + inventory

Before touching anything, capture current state:

```bash
# Cluster context
kubectl config current-context

# Snapshot the existing asgard-secrets (if any) — for rollback reference
kubectl get secret asgard-secrets -n asgard -o yaml > /tmp/asgard-secrets-backup-$(date +%Y%m%d-%H%M).yaml

# INVENTORY existing keys — needed to decide patch vs create per step.
# If a key is MISSING from current Secret, patch with `merge` (creates it).
# If a key EXISTS, patch with `merge` (overwrites).
kubectl get secret asgard-secrets -n asgard -o jsonpath='{.data}' | jq 'keys'

# Confirm running pods (Deployments in this cluster, NOT StatefulSets)
kubectl get pods -n asgard
kubectl get pods -n asgard-infra

# Capture current Yggdrasil URL + readiness
curl -sf https://sso.asgard.internal/.well-known/openid-configuration | jq '.issuer'
```

**Stop here if:**
- The backup file is empty (no existing Secret yet → fresh seed instead, see Step 9 bulk-seed)
- Any critical pod is `CrashLoopBackOff` (fix that first)
- Step 0 not done (rotation will be no-op)

**Patch pattern used below.** All steps use `--type=merge` with `stringData` (auto-base64). This works for both existing AND missing keys — unlike `--type=json` `op: replace` which fails on missing keys:

```bash
kubectl patch secret asgard-secrets -n asgard --type=merge \
  -p "$(cat <<EOF
{"stringData": {"<KEY>": "$NEW_VALUE"}}
EOF
)"
```

---

## Step 2 — Heimdall API key

**Why first:** independent of everything else, host-side rotation, zero cluster downtime.

```bash
# 1. On Heimdall host (Mac mini), regenerate API key
ssh mac-mini  # or wherever Heimdall runs natively
cd ~/Heimdall && cargo run --bin keygen -- --rotate

# Save the new key — you'll paste it in Step 9
NEW_HEIMDALL_KEY="<paste output>"

# 2. Update K8s Secret (merge patch — works whether key exists or not)
kubectl patch secret asgard-secrets -n asgard --type=merge \
  -p "{\"stringData\": {\"HEIMDALL_API_KEY\": \"$NEW_HEIMDALL_KEY\"}}"

# 3. Restart consumers (Bifrost + Mimir-api use HEIMDALL_API_KEY)
kubectl rollout restart deploy/bifrost deploy/mimir-api -n asgard
kubectl rollout status deploy/bifrost deploy/mimir-api -n asgard --timeout=2m
```

**Verify:** `kubectl logs -n asgard deploy/bifrost --tail=20` shows "Heimdall connected" or first LLM call succeeds.

---

## Step 3 — Laminar API key

**Why early:** Laminar is disabled in umbrella chart (`laminar.enabled: false`), so rotation is paperwork until re-enabled. But the leaked key (`UZfUPh7uU6Z75uQeeVpuED3HpjcJM3BBL7UnYIlkd18AseLjvrjIVnU9MoXGptVC`) needs to be revoked at Laminar's side anyway.

```bash
# 1. In Laminar admin UI (when enabled): Settings → API Keys → revoke leaked key + create new
# 2. Update K8s Secret slot (no consumer to restart since laminar is disabled)
kubectl patch secret asgard-secrets -n asgard --type=merge \
  -p '{"stringData": {"LAMINAR_API_KEY": "<NEW>"}}'
```

If Laminar isn't running anywhere reachable: just log in https://www.laminar.so/ (or whichever instance held the key), revoke the key, mark this step done, leave the slot empty (`""`).

---

## Step 4 — Neo4j password

```bash
# 1. Generate new password (avoid single-quote chars — cypher uses '...')
NEW_NEO4J_PW=$(openssl rand -base64 24 | tr -d "'\"\\\\")

# 2. Connect to Neo4j and ALTER USER (requires Neo4j 4+ — verify image version)
#    Older versions use `CALL dbms.security.changePassword`.
kubectl exec -n asgard-infra deploy/neo4j -- cypher-shell -u neo4j -p "<OLD_PW>" \
  "ALTER USER neo4j SET PASSWORD '$NEW_NEO4J_PW';"

# 3. Update K8s Secret (merge patch — safe whether key exists or not)
kubectl patch secret asgard-secrets -n asgard --type=merge \
  -p "{\"stringData\": {\"NEO4J_PASSWORD\": \"$NEW_NEO4J_PW\"}}"

# 4. Restart Mimir API (only Mimir uses NEO4J_PASSWORD)
kubectl rollout restart deploy/mimir-api -n asgard
kubectl rollout status deploy/mimir-api -n asgard --timeout=3m
```

**Verify (note: `/healthz` does NOT probe Neo4j — only HTTP server alive):**

```bash
# Check Mimir logs for Neo4j connect
kubectl logs -n asgard deploy/mimir-api --tail=50 | grep -iE "neo4j|graph"

# Hit a graph-query endpoint (replace with actual route)
curl -sf https://mimir.asgard.internal/api/v1/knowledge/graph/health
```

**Rollback:** if mimir-api fails to start, ALTER USER back to old password, patch Secret with old value (from backup file).

---

## Step 5 — MariaDB user password (mimir database)

**Note:** also update `MIMIR_DATABASE_URL` in the same Secret patch — the URL embeds the password.

```bash
# 1. Generate new password (URL-safe — avoid every char that has special URL meaning)
NEW_MARIADB_PW=$(openssl rand -base64 24 | tr -d '/=+@:?#&')

# 2. ALTER USER on MariaDB
#    NOTE: MariaDB runs as a Deployment in this cluster (NOT a StatefulSet).
#    Use `deploy/mariadb` selector instead of pod name like `mariadb-0`.
kubectl exec -n asgard-infra deploy/mariadb -- mariadb \
  -u root -p"<OLD_ROOT_PW>" \
  -e "ALTER USER 'mimir'@'%' IDENTIFIED BY '$NEW_MARIADB_PW'; FLUSH PRIVILEGES;"

# (Optional — also rotate root password)
# kubectl exec -n asgard-infra deploy/mariadb -- mariadb -u root -p"<OLD_ROOT_PW>" \
#   -e "ALTER USER 'root'@'%' IDENTIFIED BY '$NEW_ROOT_PW'; FLUSH PRIVILEGES;"

# 3. Update both Secret keys (merge patch — sets both in one call)
NEW_URL="mysql://mimir:${NEW_MARIADB_PW}@mariadb.asgard-infra.svc:3306/mimir"
kubectl patch secret asgard-secrets -n asgard --type=merge \
  -p "{\"stringData\": {\"MARIADB_PASSWORD\": \"$NEW_MARIADB_PW\", \"MIMIR_DATABASE_URL\": \"$NEW_URL\"}}"

# 4. Restart Mimir API
kubectl rollout restart deploy/mimir-api -n asgard
kubectl rollout status deploy/mimir-api -n asgard --timeout=3m
```

**Verify:** `kubectl logs -n asgard deploy/mimir-api | grep -i "database connected"`.

**Bonus rotate (optional):** also rotate `MARIADB_ROOT_PASSWORD` separately — only used by `mariadb-0` itself.

---

## Step 6 — Postgres password (Zitadel DB)

⚠️ **Zitadel reads this password at boot. Rotation requires Yggdrasil restart.**

```bash
# 1. Generate new password (URL-safe)
NEW_POSTGRES_PW=$(openssl rand -base64 24 | tr -d '/=+@:?#&')

# 2. ALTER USER on Postgres
#    NOTE: Postgres also runs as a Deployment here (NOT StatefulSet).
#    Yggdrasil/Zitadel uses the `postgres` superuser per chart config.
#    If any other service uses a separate role (e.g. `mimir` or `zitadel`),
#    enumerate first: kubectl exec deploy/postgres -- psql -U postgres -c '\du'
#    and rotate each separately.
kubectl exec -n asgard-infra deploy/postgres -- psql -U postgres \
  -c "ALTER USER postgres WITH PASSWORD '$NEW_POSTGRES_PW';"

# 3. Update Secret (merge — works whether key existed or not)
kubectl patch secret asgard-secrets -n asgard --type=merge \
  -p "{\"stringData\": {\"YGGDRASIL_POSTGRES_PASSWORD\": \"$NEW_POSTGRES_PW\"}}"

# 4. Restart Yggdrasil
kubectl rollout restart deploy/yggdrasil -n asgard
kubectl rollout status deploy/yggdrasil -n asgard --timeout=5m
```

**Verify:** `curl -sf https://sso.asgard.internal/debug/healthz` returns 200; admin UI login still works.

**Lock-out risk:** if you change Postgres password but Yggdrasil still uses old one in the Secret, Yggdrasil pod will `CrashLoopBackOff`. Recovery: revert Secret to backup file, then redo carefully.

---

## Step 7 — OIDC client secrets (Mimir + Eir)

Two separate OIDC apps in Zitadel admin UI. Each has its own client secret.

### 7a. Mimir client

```bash
# 1. Browser → https://sso.asgard.internal/ui/console → log in
#    → Projects → "Asgard" → Applications → "Mimir"
#    → Click "Reset Client Secret" → COPY immediately (shown once)
NEW_MIMIR_OIDC_SECRET="<paste here>"

# 2. Update Secret (merge patch)
kubectl patch secret asgard-secrets -n asgard --type=merge \
  -p "{\"stringData\": {\"YGGDRASIL_CLIENT_SECRET\": \"$NEW_MIMIR_OIDC_SECRET\"}}"

# 3. Restart consumers
kubectl rollout restart deploy/mimir-api deploy/mimir-dashboard deploy/bifrost -n asgard
```

### 7b. Eir Gateway client

```bash
# 1. Same UI flow, different application: "Eir-Gateway"
NEW_EIR_OIDC_SECRET="<paste here>"

# 2. Update Secret (merge patch)
kubectl patch secret asgard-secrets -n asgard --type=merge \
  -p "{\"stringData\": {\"EIR_CLIENT_SECRET\": \"$NEW_EIR_OIDC_SECRET\"}}"

# 3. Restart Eir-Gateway
kubectl rollout restart deploy/eir-gateway -n asgard
```

**Verify (Mimir):** browser to `https://mimir.asgard.internal` → login flow → arrive at dashboard.
**Verify (Eir):** browser to `https://ehr.asgard.internal` → login flow → arrive at OpenEMR.

**Rollback:** in Zitadel UI, you cannot restore a previous secret — but you can generate yet another new one if a botched paste broke things.

---

## Step 8 — Yggdrasil masterkey ⚠️

**Most disruptive step. Read fully before starting.**

The masterkey is what Zitadel uses to encrypt OTHER secrets stored in its database (encrypted IDP credentials, SMTP passwords, etc.). Rotating it requires Zitadel's `setup` command to re-encrypt the DB.

**Options:**

### Option 8A — Defer (recommended for now)

The leaked masterkey was the literal placeholder `yggdrasil-masterkey-change-me-ok`. If Zitadel was ever started with that value, **everything currently in Zitadel DB is encrypted with that key**. An attacker with both (a) git history and (b) Postgres DB dump could decrypt downstream IDP secrets.

**Mitigation without rotation:** confirm no IDP credentials, no SMTP relay, no critical encrypted-at-rest data is in Zitadel yet. If yes: safe to defer until Sprint 51e+1 with proper Zitadel masterkey rotation runbook.

### Option 8B — Full rotation (do later when planned)

```bash
# 1. Stop all Yggdrasil traffic (read-only mode by scaling to 0 replicas)
kubectl scale deploy/yggdrasil -n asgard --replicas=0

# 2. Generate new masterkey (must be exactly 32 bytes for Zitadel)
NEW_MASTERKEY=$(openssl rand -hex 16)  # 32 hex chars = 32 bytes

# 3. Run zitadel re-encrypt (in a one-shot pod with Postgres access)
# See: https://zitadel.com/docs/self-hosting/manage/key
# Pseudocode — actual command varies by Zitadel version
kubectl run zitadel-rotate --rm -it --image=ghcr.io/zitadel/zitadel:v2.71.6 \
  --env=ZITADEL_MASTERKEY=<OLD_MASTERKEY> \
  --env=ZITADEL_NEW_MASTERKEY=$NEW_MASTERKEY \
  -- zitadel setup --steps re-encrypt

# 4. Update Secret + scale back up
kubectl patch secret asgard-secrets -n asgard --type=merge \
  -p "{\"stringData\": {\"YGGDRASIL_MASTERKEY\": \"$NEW_MASTERKEY\"}}"
kubectl scale deploy/yggdrasil -n asgard --replicas=1
kubectl rollout status deploy/yggdrasil -n asgard --timeout=10m
```

**This step is bookmarked for a separate rotation session — execute when scope of encrypted data in Zitadel justifies the effort.**

---

## Step 9 — Bulk-seed verification

After all steps above, confirm the Secret has all expected keys with non-empty values:

```bash
# Should print all 13 keys (no missing, no empty)
kubectl get secret asgard-secrets -n asgard -o json | jq -r '
  .data
  | to_entries[]
  | "\(.key): \(.value | @base64d | length) bytes"
'
```

Expected output (lengths will vary):

```
EIR_CLIENT_ID: 43 bytes
EIR_CLIENT_SECRET: 88 bytes
HEIMDALL_API_KEY: 64 bytes
LAMINAR_API_KEY: 64 bytes
MARIADB_PASSWORD: 22 bytes
MARIADB_ROOT_PASSWORD: 22 bytes
MIMIR_DATABASE_URL: 84 bytes
NEO4J_PASSWORD: 22 bytes
YGGDRASIL_CLIENT_ID: 18 bytes
YGGDRASIL_CLIENT_SECRET: 88 bytes
YGGDRASIL_MASTERKEY: 32 bytes        # ← only present after Step 8
YGGDRASIL_POSTGRES_PASSWORD: 22 bytes
```

**Final smoke test:**

```bash
# All pods Running
kubectl get pods -n asgard
kubectl get pods -n asgard-infra

# End-to-end auth flow
open https://mimir.asgard.internal      # OIDC redirect → login → dashboard
open https://ehr.asgard.internal        # OIDC redirect → login → OpenEMR
```

---

## Cleanup

After successful rotation:

```bash
# Delete the backup file (contains old burned secrets)
shred -u /tmp/asgard-secrets-backup-*.yaml 2>/dev/null || rm -P /tmp/asgard-secrets-backup-*.yaml

# Add a CHANGELOG entry
echo "$(date +%Y-%m-%d): Rotated all secrets per docs/security/ROTATION-PLAN-2026-05-10.md following PR #31 burn." \
  >> docs/security/ROTATION-LOG.md
```

Optionally: file a private GitHub Security Advisory at https://github.com/MegaWiz-Dev-Team/Asgard/security/advisories documenting the leak window (commit `73a004f` → PR #31 merge `d081177`) and confirming rotation.

---

## When you actually run this

Update this file's frontmatter to mark each step done:

```markdown
- [x] Step 1 — Pre-flight check (2026-05-XX)
- [x] Step 2 — Heimdall API key (2026-05-XX)
...
```

And delete the file once rotation is complete (or move to `docs/security/rotations/2026-05-10/`).
