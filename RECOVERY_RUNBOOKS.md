# Recovery Runbooks — Asgard K8s

**Quick fixes for common Asgard incidents**

Use these when something goes wrong. Always run deployment validation after fixes.

---

## 🚨 Mimir 503 Service Unavailable

**Symptoms:**
- Browser: "503 Service Temporarily Unavailable"
- `kubectl get pods` shows: mimir-api in CrashLoopBackOff

**Recovery (5-10 min):**

```bash
# Step 1: Check pod status
kubectl get pods -n asgard -l app=mimir-api

# Step 2: Read logs to find root cause
kubectl logs -n asgard mimir-api-XXXXX --tail=50

# Common issues:
# - "ERROR 1045: Access denied" → MariaDB issue (see below)
# - "Failed to initialize database" → Migration issue
# - "Connection refused" → MariaDB not running
```

**If MariaDB auth error:**
```bash
# Check MariaDB is running
kubectl get pods -n asgard-infra -l app=mariadb

# If not ready, check why
kubectl describe pod mariadb-XXXXX -n asgard-infra

# If password is wrong, reset it
kubectl exec mariadb-XXXXX -n asgard-infra -- mariadb -u root -proot -e \
  "ALTER USER 'mimir'@'%' IDENTIFIED BY '<password>'; FLUSH PRIVILEGES;"

# Restart Mimir
kubectl delete pods -n asgard -l app=mimir-api
```

**If migration error:**
```bash
# This means stale DB state. Full reset needed:
kubectl delete pvc mariadb-data -n asgard-infra
kubectl delete pods -n asgard-infra -l app=mariadb
# Wait for MariaDB to restart with fresh DB
kubectl wait --for=condition=ready pod -l app=mariadb -n asgard-infra --timeout=60s

# Then restart Mimir
kubectl delete pods -n asgard -l app=mimir-api
```

---

## 🚨 MariaDB Pod Stuck in Pending

**Symptoms:**
```
mariadb-XXXXX   0/1     Pending   0           5m
```

**Recovery (5 min):**

```bash
# Check why it's pending
kubectl describe pvc mariadb-data -n asgard-infra
# Look for error in Events section

# Option 1: Delete PVC to let K8s create fresh one
kubectl delete pvc mariadb-data -n asgard-infra

# Option 2: Check node capacity
kubectl describe nodes
# Look for "Allocatable" resources and "Allocated resources"
```

---

## 🚨 Pod CrashLoopBackOff (Any Service)

**Symptoms:**
```
eir-gateway-XXXXX   0/1     CrashLoopBackOff   5 (30s ago)
```

**Recovery (2-3 min):**

```bash
# Step 1: Get logs
kubectl logs <pod-name> -n <namespace> --tail=100

# Step 2: Identify error (look for ERROR, panic, failed to)

# Step 3: Fix based on error type:

# If image pull error:
#   → Check imagePullPolicy is "Never" for K3s
#   → Check docker image exists: docker image ls | grep <name>

# If connection error:
#   → Check dependent service is running
#   → Check networking (kubectl get svc)

# If config error:
#   → Check env vars: kubectl describe pod <name>
#   → Check secrets: kubectl get secrets -n <namespace>

# Step 4: Restart pod
kubectl delete pod <pod-name> -n <namespace>
```

---

## 🚨 OrbStack / Local Docker Dead

**Symptoms:**
```
Cannot connect to the Docker daemon at unix:///Users/mimir/.orbstack/run/docker.sock
```

**Recovery (5 min):**

```bash
# Force kill OrbStack
pkill -9 -i orbstack

# Clean up socket
rm -rf ~/.orbstack/run

# Restart OrbStack
open /Applications/OrbStack.app

# Wait ~10 seconds for Docker to come online
docker ps

# If still failing, check System Preferences → OrbStack
```

---

## 🚨 Database User Missing (INC-2026-05-17-001)

**Symptoms:**
```
ERROR 1045 (28000): Access denied for user 'mimir'@'X.X.X.X' (using password: YES)
```

**Recovery (3 min):**

```bash
# Check if user exists
kubectl exec mariadb-XXXXX -n asgard-infra -- \
  mariadb -u root -proot -e "SELECT user, host FROM mysql.user;"

# If mimir user NOT listed:
kubectl exec mariadb-XXXXX -n asgard-infra -- mariadb -u root -proot -e \
  "CREATE USER 'mimir'@'%' IDENTIFIED BY '<password>';
   GRANT ALL PRIVILEGES ON mimir.* TO 'mimir'@'%';
   FLUSH PRIVILEGES;"

# If user exists but password wrong:
kubectl exec mariadb-XXXXX -n asgard-infra -- mariadb -u root -proot -e \
  "ALTER USER 'mimir'@'%' IDENTIFIED BY '<password>';
   FLUSH PRIVILEGES;"

# Test connection
kubectl exec mariadb-XXXXX -n asgard-infra -- \
  mariadb -u mimir -p<password> -e "SELECT 'SUCCESS';"
```

**To prevent:** Run `./scripts/validate-k8s-before-deploy.sh` before deploy

---

## 🚨 Deployment Won't Complete (Stuck Rolling)

**Symptoms:**
```
kubectl rollout status deployment/mimir-api -n asgard
# Waiting for rollout to finish...
```

**Recovery (5 min):**

```bash
# Check pod events
kubectl describe pod mimir-api-XXXXX -n asgard

# Common causes:
# - Readiness probe failing → pod not ready
# - PVC not bound → storage issue
# - Image pull failing → docker image missing

# If pod is stuck on same error for >5 min, force restart
kubectl rollout restart deployment/mimir-api -n asgard

# Wait for new rollout
kubectl rollout status deployment/mimir-api -n asgard --timeout=300s
```

---

## 🚨 Can't Connect to Database from Local Machine

**Symptoms:**
```
$ mysql -h 127.0.0.1 -u mimir -p
ERROR 2003 (HY000): Can't connect to MySQL server on '127.0.0.1:3306'
```

**Recovery (2 min):**

```bash
# Check if MariaDB pod is port-forwarding
kubectl port-forward -n asgard-infra svc/mariadb 3306:3306

# In another terminal:
mysql -h 127.0.0.1 -u mimir -p

# Or use kubectl exec directly:
kubectl exec -it mariadb-XXXXX -n asgard-infra -- \
  mariadb -u mimir -p
```

---

## Emergency: Reset Everything

**⚠️ WARNING: This deletes all data. Only use if completely stuck.**

```bash
# Delete all Asgard resources
kubectl delete namespace asgard asgard-infra --wait=true

# Wait for deletion (~1 min)
kubectl get namespace

# Redeploy from scratch
cd /Users/mimir/Developer/Asgard
./scripts/validate-k8s-before-deploy.sh
./scripts/deploy-all.sh

# Verify
kubectl get pods -A
```

---

## Need Help?

Before escalating:

1. **Run validation script:**
   ```bash
   ./scripts/validate-k8s-before-deploy.sh
   ```

2. **Check logs:**
   ```bash
   kubectl logs <pod-name> -n <namespace> --tail=100
   ```

3. **Review recent changes:**
   ```bash
   git log --oneline -10
   git diff HEAD~1
   ```

4. **Check incident history:**
   - [Incident report](./docs/incidents/2026-05-17-mimir-503/incident-report.md)
   - [Postmortem](./docs/incidents/2026-05-17-mimir-503/postmortem.md)

---

## Escalation

If issue persists after recovery steps:

1. Create incident in Linear (label: `asgard-incident`)
2. Post in #incidents Slack channel with:
   - Service affected
   - Last known good time
   - Error messages from logs
   - Recovery steps already tried
3. Page on-call engineer (if P1)

---

**Last updated:** 2026-05-18  
**Related incident:** INC-2026-05-17-001  
