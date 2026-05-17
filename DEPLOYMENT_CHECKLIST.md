# K8s Deployment Checklist

**Purpose:** Prevent configuration errors like INC-2026-05-17-001 (Mimir 503 due to missing MYSQL_USER env var)

**When to use:** Before every `kubectl apply` or `./scripts/deploy-all.sh`

---

## Pre-Deployment Checklist

### 1. Validate Manifests
```bash
./scripts/validate-k8s-before-deploy.sh
```

**What it checks:**
- ✅ All required environment variables present (MYSQL_USER, MYSQL_PASSWORD, etc.)
- ✅ Image pull policies correct for K3s (imagePullPolicy: Never)
- ✅ PersistentVolumeClaims exist
- ✅ Required secrets configured
- ✅ Health checks defined

**If it fails:** Fix errors before proceeding to step 2

---

### 2. Review Manifest Diff
```bash
kubectl diff -f k8s/asgard
kubectl diff -f k8s/asgard-infra
```

**Look for:**
- Unexpected changes to critical configs
- Missing or removed volumes
- Changed resource limits
- Removed environment variables

**If unexpected:** Revert and investigate

---

### 3. Check Current Pod Status
```bash
kubectl get pods -A
kubectl get pvc -A
```

**Ensure:**
- No pods in CrashLoopBackOff
- All PVCs are Bound (not Pending)
- No stale pods from previous deployments

---

### 4. Apply Changes
```bash
# Dry-run first
kubectl apply -f k8s/asgard --dry-run=client

# If OK, apply for real
kubectl apply -f k8s/asgard
kubectl apply -f k8s/asgard-infra
```

---

### 5. Verify Deployment

```bash
# Wait for pods to be ready (2-3 min typical)
kubectl wait --for=condition=ready pod -l app=mimir-api -n asgard --timeout=300s
kubectl wait --for=condition=ready pod -l app=mariadb -n asgard-infra --timeout=300s

# Check all pods are running
kubectl get pods -A | grep -E "Running|Ready"

# Check logs for errors
kubectl logs -n asgard -l app=mimir-api --tail=20
kubectl logs -n asgard-infra -l app=mariadb --tail=20
```

**Expected:**
- Mimir API: `listening on 0.0.0.0:8080`
- MariaDB: `ready for connections`
- No ERROR or panic messages

---

## Required Environment Variables

### MariaDB (`k8s/asgard-infra/mariadb-deployment.yaml`)

| Variable | Required? | Default | Notes |
|----------|-----------|---------|-------|
| MYSQL_ROOT_PASSWORD | ✅ YES | — | Root user password |
| MYSQL_DATABASE | ✅ YES | — | Initial database name (should be `mimir`) |
| MYSQL_USER | ✅ YES | — | App user name (should be `mimir`) |
| MYSQL_PASSWORD | ✅ YES | — | App user password |

**If ANY are missing:**
- MariaDB will start with no users
- Mimir will crash with: `ERROR 1045 (28000): Access denied for user 'mimir'`
- Service down until fixed

### Mimir (`k8s/asgard/mimir-api-deployment.yaml`)

| Variable | Required? | Source | Notes |
|----------|-----------|--------|-------|
| DATABASE_URL | ✅ YES | Secret | `mysql://mimir:PASSWORD@mariadb:3306/mimir` |
| PORT | Optional | — | Default: 8080 |
| RUST_LOG | Optional | — | Default: info |

---

## Common Issues & Solutions

### Issue: "Access denied for user 'mimir'"
```
ERROR 1045 (28000): Access denied for user 'mimir'@'192.168.194.X' (using password: YES)
```

**Cause:** MYSQL_USER or MYSQL_PASSWORD env var missing/wrong

**Fix:**
```bash
# Check what's set
kubectl get deployment mariadb -n asgard-infra -o yaml | grep -A 10 "env:"

# If missing, add them
kubectl set env deployment/mariadb -n asgard-infra \
  MYSQL_USER=mimir \
  MYSQL_PASSWORD=<from-secret>

# Restart
kubectl rollout restart deployment/mariadb -n asgard-infra
```

---

### Issue: Pod stuck in CrashLoopBackOff
```
mimir-api-XXXXX   0/1     CrashLoopBackOff   5 (2m ago)
```

**Debug:**
```bash
# Check pod logs
kubectl logs mimir-api-XXXXX -n asgard --tail=50

# Common causes:
# - Database not ready (check MariaDB)
# - Database user/password wrong (see above)
# - Missing env vars (run validation script)
# - Image pull failed (check imagePullPolicy)
```

---

### Issue: PVC stuck in Pending
```
mariadb-data   Pending   — 5m
```

**Cause:** Storage not allocated, or node doesn't have capacity

**Check:**
```bash
kubectl describe pvc mariadb-data -n asgard-infra
# Look for "Events:" section with error messages

# Typical fix:
kubectl delete pvc mariadb-data -n asgard-infra
# (will be recreated with fresh storage)
```

---

## Health Check Endpoints

After deployment, verify these respond:

```bash
# Mimir health
curl -v http://mimir.asgard.svc:8080/healthz
# Expected: HTTP 200 OK

# MariaDB
kubectl exec -n asgard-infra mariadb-XXXXX -- \
  mariadb -u mimir -p<PASSWORD> -e "SELECT 1;"
# Expected: 1 row returned
```

---

## Rollback (If Something Goes Wrong)

```bash
# Revert to previous K8s state
kubectl rollout undo deployment/mimir-api -n asgard
kubectl rollout undo deployment/mariadb -n asgard-infra

# Check status
kubectl rollout status deployment/mimir-api -n asgard
```

---

## Incident History

- **INC-2026-05-17-001:** Missing MYSQL_USER/MYSQL_PASSWORD → 4h 6m outage
  - **Prevention:** This checklist + validation script

---

## Questions?

See:
- [INCIDENT_REPORT_2026_05_17.md](../INCIDENT_REPORT_2026_05_17.md) — Full technical analysis
- [POSTMORTEM_2026_05_17.md](../POSTMORTEM_2026_05_17.md) — Team learning
- `./scripts/validate-k8s-before-deploy.sh` — Automated validation
