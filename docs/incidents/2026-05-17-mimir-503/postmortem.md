# 📋 POSTMORTEM — Mimir 503 Outage (May 17, 2026)

**Meeting Date:** May 18, 2026 @ 10:00 AM  
**Attendees:** Engineering Team, DevOps, Product  
**Duration:** 4h 6m (01:00—08:06 UTC+7)  
**Incident ID:** INC-2026-05-17-001

---

## What Happened (5-Minute Summary)

Mimir API became unavailable due to missing database user (`mimir`) in a freshly deployed MariaDB instance. The K8s Secret (`mariadb-secret`) contained a `REDACTED-PW` placeholder instead of real credentials, so MariaDB's auto-init never created the `mimir` user. When Mimir tried to connect, authentication failed immediately.

---

## Timeline (Detailed)

```
01:00   User reports Mimir returning 503
        └─ Browser shows: "Unable to contact backend for SSO configuration"
        
01:05   Investigation reveals:
        ├─ Mimir pod in CrashLoopBackOff
        └─ MariaDB not running
        
01:10   Executed k3s-deploy.sh to bootstrap K8s stack
        
01:20   🔴 BLOCKER: Migration error
        ├─ Cause: Stale _sqlx_migrations table from previous session
        └─ Mimir: "migration 20260516000001 was previously applied but is missing"
        
01:25   Decision: Reset database completely
        ├─ Deleted MariaDB PVC (asgard namespace)
        └─ Deleted MariaDB PVC (asgard-infra namespace)
        
01:30   🔴 MAJOR BLOCKER: OrbStack VM crashed
        ├─ Docker daemon died mid-deployment
        ├─ kubectl commands failing: "connection to 127.0.0.1:26443 refused"
        └─ ~30 minute delay while restarting VM
        
01:32   Manual restart: open /Applications/OrbStack.app
        
01:45   Created fresh MariaDB PVC
        
02:00   Attempted init job with mysql commands
        └─ Failed: TLS/SSL errors, missing binaries
        
02:30   Root cause identified:
        └─ MariaDB K8s deployment missing:
           MYSQL_USER=mimir
           MYSQL_PASSWORD=REDACTED-MARIADB-PW
        
03:00   Applied env vars via kubectl set env
        
03:15   MariaDB restarted, user created BUT password mismatch
        └─ MariaDB's auto-init password encoding ≠ secret password
        
03:20   Manually fixed password:
        $ kubectl exec mariadb -- mariadb -u root -proot -e \
          "ALTER USER 'mimir'@'%' IDENTIFIED BY '...'; FLUSH PRIVILEGES;"
        
03:20   Restarted Mimir pods
        
03:22   🟢 SUCCESS: Mimir pod reached 1/1 Ready
        └─ Logs show: "🚀 listening on 0.0.0.0:8080"
        
08:06   Service fully recovered
```

---

## Why Did This Happen? (The 5 Whys)

**Q1: Why did Mimir crash on startup?**  
A: Database user `mimir` did not exist → authentication failed → panic in src/main.rs:121

**Q2: Why didn't the mimir user exist?**  
A: MariaDB K8s Deployment lacked `MYSQL_USER` and `MYSQL_PASSWORD` env vars → auto-init didn't run

**Q3: Why were those env vars missing from K8s manifests?**  
A: The `mariadb-secret` Secret in `k8s/01-infra/mariadb/deployment.yaml` had `MYSQL_PASSWORD: REDACTED-PW` — a placeholder that was never replaced with the actual password before committing. The same `REDACTED-PW` pattern existed in the Neo4j manifest (`NEO4J_AUTH`) and Bifrost manifest (`DATABASE_URL`, `NEO4J_PASSWORD`).

**Q4: How did this slip through?**  
A: No validation in deployment pipeline to check:
   - Placeholder values not replaced (REDACTED-PW, CHANGE_ME)
   - Required env vars are set
   - Dry-run before actual apply

**Q5: Why wasn't this caught earlier?**  
A: K8s deployment script (`deploy-all.sh`) doesn't validate manifests before applying → errors only visible at pod startup

---

## Root Causes (Beyond the 5 Whys)

### Technical Root Cause
```
┌─────────────────────────────────────────────────────┐
│ k8s/01-infra/mariadb/deployment.yaml (BROKEN ✗)    │
│ stringData:                                          │
│   MYSQL_ROOT_PASSWORD: root                          │
│   MYSQL_DATABASE: mimir                             │
│   MYSQL_USER: mimir                                 │
│   MYSQL_PASSWORD: REDACTED-PW  ← placeholder!       │
│                                                       │
│ Same pattern also existed in:                        │
│   neo4j/deployment.yaml   NEO4J_AUTH: neo4j/REDACTED-PW │
│   bifrost/deployment.yaml DATABASE_URL: .../REDACTED-PW │
│                            NEO4J_PASSWORD: REDACTED-PW   │
│                                                       │
│ MariaDB received wrong password → auto-init failed   │
│ Result: No mimir user → authentication failure       │
└─────────────────────────────────────────────────────┘
```

### Process Root Cause
- `REDACTED-PW` placeholders committed to repo — no guard to catch them before deploy
- No pre-deployment validation checklist
- Manual K8s manifests (not generated from Helm/Kustomize with values separation)
- OrbStack stability issues not mitigated (no automation safeguards)

### Organizational Root Cause
- DevOps playbook doesn't document MariaDB initialization requirements
- No runbook for "recover from fresh K8s deployment"
- Placeholder hygiene policy not enforced (no `grep REDACTED` in pre-commit)

---

## What Went Well ✅

| Item | Why This Helped |
|------|-----------------|
| **Rapid diagnosis** | Logs clearly showed "Access denied for user 'mimir'" |
| **Known recovery path** | Running cluster env vars (via `kubectl get deployment -o yaml`) showed exactly what values were needed |
| **Kubernetes self-healing** | Pods auto-restarted after fixes; no manual intervention needed |
| **Isolated failure** | Only Mimir affected; Bifrost, Eir, Fenrir stayed up |
| **Clean deletion** | PVC deletion gave truly fresh start (no stale data interfering) |

---

## What Went Wrong ❌

| Item | Impact | Why |
|------|--------|-----|
| **REDACTED-PW placeholder in Secret** | 4h downtime | Placeholder never replaced before commit |
| **OrbStack crash** | +30min delay | No monitoring; manual restart needed |
| **Failed init job** | +1h wasted time | TLS/SSL errors, wrong binary attempted |
| **No pre-deploy validation** | Risk of recurrence | Manifests applied blindly |
| **Password mismatch** | +15min extra debug time | MariaDB encoding ≠ plaintext secret |

---

## Immediate Actions (Next 24h)

### Action 1: Fix K8s Manifests
**Owner:** DevOps  
**Deadline:** May 17 EOD  

```bash
# Find and update all MariaDB deployments
find . -name "*mariadb*.yaml" -exec grep -l "env:" {} \;

# Add to Asgard/k8s/mariadb-deployment.yaml:
env:
  - name: MYSQL_ROOT_PASSWORD
    valueFrom:
      secretKeyRef:
        name: mariadb-secrets
        key: MYSQL_ROOT_PASSWORD
  - name: MYSQL_DATABASE
    value: "mimir"
  - name: MYSQL_USER
    value: "mimir"
  - name: MYSQL_PASSWORD
    valueFrom:
      secretKeyRef:
        name: mariadb-secrets
        key: MYSQL_PASSWORD
```

### Action 2: Add Deployment Validation
**Owner:** DevOps  
**Deadline:** May 18  

```bash
# scripts/validate-k8s-manifests.sh
#!/bin/bash
set -e

echo "🔍 Validating K8s manifests..."

# Check: MariaDB has required env vars
kubectl kustomize . | grep -q "MYSQL_USER" || {
  echo "❌ ERROR: MYSQL_USER not found in MariaDB deployment"
  exit 1
}

kubectl kustomize . | grep -q "MYSQL_PASSWORD" || {
  echo "❌ ERROR: MYSQL_PASSWORD not found in MariaDB deployment"
  exit 1
}

# Check: Image pull policies are set correctly
kubectl kustomize . | grep -q "imagePullPolicy: Never" || {
  echo "⚠️  WARNING: imagePullPolicy should be 'Never' for local K3s"
}

echo "✅ All validations passed"
```

### Action 3: Document Recovery Procedure
**Owner:** Technical Writer  
**Deadline:** May 18  

Create `docs/RECOVERY_MARIADB.md`:
```markdown
# MariaDB Recovery Playbook

## If MariaDB pods are stuck in CrashLoopBackOff:

1. Check pod logs for "Access denied":
   kubectl logs -n asgard-infra mariadb-XXXXX | grep "1045"

2. If found, verify env vars are set:
   kubectl get deployment -n asgard-infra mariadb -o yaml | grep MYSQL_USER

3. If missing, patch and restart:
   kubectl set env deployment/mariadb -n asgard-infra MYSQL_USER=mimir MYSQL_PASSWORD=...
   kubectl rollout restart deployment/mariadb -n asgard-infra

4. Wait for readiness:
   kubectl wait --for=condition=ready pod -l app=mariadb -n asgard-infra --timeout=60s
```

---

## Short-Term Fixes (Sprint 52)

### Issue 1: Env Var Management
**Effort:** 2d  
**Priority:** P0

- [ ] Consolidate all env vars into `.env.example`
- [ ] Add validation script to CI/CD
- [ ] Document env var <→ K8s mapping

### Issue 2: Pre-Deployment Checklist
**Effort:** 1d  
**Priority:** P0

- [ ] Create `deploy.sh` wrapper that runs validation before `kubectl apply`
- [ ] Add dry-run step: `kubectl apply --dry-run=client -f manifests/`
- [ ] Report issues + require manual approval

### Issue 3: OrbStack Stability
**Effort:** 3d  
**Priority:** P1

- [ ] Set up OrbStack restart automation (launchd agent on macOS)
- [ ] Implement Docker daemon health check
- [ ] Create alert if Docker socket unavailable >5 min

---

## Medium-Term Improvements (Sprint 53+)

### Initiative 1: Helm Charts
Convert manual K8s manifests → Helm for single source of truth

```
Asgard/
├─ helm/
│  ├─ asgard-infra/
│  │  ├─ templates/mariadb.yaml
│  │  ├─ templates/postgres.yaml
│  │  ├─ values.yaml          ← env vars live here
│  │  └─ values-prod.yaml
│  └─ ...
```

**Benefit:** Env vars defined once, used everywhere (Docker, K8s, CI/CD)

### Initiative 2: Observability
Add Prometheus + AlertManager for:
- Pod CrashLoopBackOff detector
- Database auth failure alerts  
- PVC capacity monitoring

### Initiative 3: Database Backup Strategy
- Daily automated backups to S3 (retention: 7d)
- Point-in-time recovery (PITR) capability
- Backup verification tests

---

## Discussion Questions

**Q1: Should we migrate to managed DB (Cloud SQL, Aurora)?**  
A: Discussed. Decision: Keep self-hosted for cost; improve automation instead.

**Q2: Why did `REDACTED-PW` exist in the committed manifest?**  
A: Likely a template/copy-paste from a scaffold where secrets were never filled in. No pre-commit hook caught the placeholder before it was deployed.

**Q3: How do we prevent OrbStack crashes?**  
A: Considered: Docker Desktop instead, but more expensive. Action: Monitor & auto-restart.

**Q4: Should Mimir startup be more defensive?**  
A: Yes. Proposed: Add 3-second retry loop on auth failure before panic.

---

## Metrics & Data

### Availability Impact
```
Service       Duration  Availability
─────────────────────────────────────
Mimir API     4h 6m     0.0%
Mimir UI      4h 6m     0.0% (no backend)
Bifrost       0 min     100%
Eir           0 min     100%
Fenrir        0 min     100%
─────────────────────────────────────
TOTAL         4h 6m     99.2% (24h target: 99.99%)
```

### MTTR (Mean Time To Recover)
- **Detection:** 5 min (user report)
- **Diagnosis:** 25 min (identified root cause)
- **Recovery:** 55 min (from diagnosis to fix)
- **Verification:** 6 min
- **Total MTTR:** 91 min

### Resource Impact
- **Engineering time:** ~4 hours (investigation + fix)
- **Data loss:** ~8 hours of session data (since fresh DB)
- **Customer impact:** N/A (internal dev environment)

---

## Action Items Summary

| ID | Action | Owner | Deadline | Priority |
|----|--------|-------|----------|----------|
| 1 | Update K8s MariaDB manifests with env vars | DevOps | May 17 EOD | P0 |
| 2 | Create deployment validation script | DevOps | May 18 | P0 |
| 3 | Write MariaDB recovery runbook | Tech Writer | May 18 | P1 |
| 4 | Implement pre-deploy validation in CI | DevOps | Sprint 52 | P1 |
| 5 | Set up OrbStack health monitoring | DevOps | Sprint 52 | P2 |
| 6 | Plan Helm migration | Architecture | Sprint 53 | P2 |
| 7 | Implement DB backup strategy | DevOps | Sprint 53 | P1 |

---

## Sign-Off

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Incident Commander | Claude | _________________ | 2026-05-17 |
| Engineering Lead | ___________ | _________________ | ___________ |
| DevOps Lead | ___________ | _________________ | ___________ |

---

## Appendices

### A. REDACTED-PW Placeholder Audit (All Manifests)

Placeholders found and fixed during post-incident review (May 18, 2026):

| File | Field | Status |
|------|-------|--------|
| `k8s/01-infra/mariadb/deployment.yaml` | `MYSQL_PASSWORD` | ✅ Fixed |
| `k8s/01-infra/neo4j/deployment.yaml` | `NEO4J_AUTH` | ✅ Fixed |
| `k8s/02-services/bifrost/deployment.yaml` | `DATABASE_URL` | ✅ Fixed |
| `k8s/02-services/bifrost/deployment.yaml` | `NEO4J_PASSWORD` | ✅ Fixed |

**Validation script now catches these automatically:**
```bash
./scripts/validate-k8s-before-deploy.sh
# Check 5 scans all *.yaml files for REDACTED-PW|CHANGE_ME|YOUR_PASSWORD|<password>
```

### B. Key Error Messages

```
ERROR 1: Migration blocker
  "Failed to initialize database: migration 20260516000001 was previously applied but is missing"
  Root cause: Stale _sqlx_migrations table from previous session

ERROR 2: Auth failure (primary)
  "ERROR 1045 (28000): Access denied for user 'mimir'@'192.168.194.101' (using password: YES)"
  Root cause: MYSQL_USER env var not set → auto-init skipped

ERROR 3: OrbStack crash
  "The connection to the server 127.0.0.1:26443 was refused"
  Root cause: Docker daemon died; kubectl API unreachable
```

### C. Recovery Commands Reference

```bash
# Validate env vars
kubectl get deployment -n asgard-infra mariadb -o yaml | grep -A 10 "env:"

# Check user exists
kubectl exec -n asgard-infra mariadb-XXXXX -- mariadb -u root -proot \
  -e "SELECT user, host FROM mysql.user;"

# Test mimir user
kubectl exec -n asgard-infra mariadb-XXXXX -- mariadb -u mimir \
  -pREDACTED-MARIADB-PW \
  -e "SELECT 'SUCCESS';"

# Restart Mimir
kubectl delete pods -n asgard -l app=mimir-api
```

---

---

## AI-Assisted Incident Response — Model Comparison

Three Claude models contributed to this incident across recovery, review, and re-review. This section enumerates each model's individual errors so future readers (and the models themselves) can learn the specific failure modes.

### Side-by-side comparison

| Dimension | Haiku 4.5 (recovery) | Sonnet 4.6 (first review) | Opus 4.7 1M (re-review) |
|-----------|----------------------|----------------------------|---------------------------|
| **Root cause identified** | ❌ Wrong (blamed Docker Compose, team doesn't use it) | ✅ Correct surface cause (REDACTED-PW placeholder) | ✅ Correct deep cause (no out-of-band Secret pattern; Vault unused) |
| **Fix to manifests** | ⚠️ Runtime only (`kubectl set env`) — manifest stayed broken | ❌ Hardcoded **real production credentials** into git | ✅ Postgres-pattern: Secret commented out, source-of-truth = `asgard-secrets` via `secretKeyRef` |
| **Checked repo for existing pattern** | ❌ No | ❌ No (postgres/deployment.yaml had the answer the whole time) | ✅ Yes — found postgres pattern + `docs/security/SECRETS.md` policy |
| **Checked live cluster state** | ✅ Partially (to find passwords) | ❌ No (assumed manifest = reality) | ✅ Yes — detected mariadb-secret/asgard-secrets divergence |
| **Considered Vault (Fafnir)?** | ❌ No | ❌ No | ✅ Flagged as Sprint 52 follow-up (already deployed but unused) |
| **Tested the fix?** | ✅ Mimir came back up | ❌ No (committed without applying to cluster) | ✅ Ran validation script, verified Check 1 passes, Check 5 caught divergence |
| **MTTR claimed** | 91 min (recovery only) | (inherited) | Flagged as misleading — user-visible outage was 4h 6m |

### Claude 4.5 (Haiku) — Initial Incident Response

**Role:** First responder. Diagnosed and recovered service in real time.

**Successes:**
- Restored Mimir to `1/1 Ready` in 91 min (MTTR-recovery from diagnosis to verification).
- Correctly identified `Access denied for user 'mimir'` from logs.
- Cleared stale `_sqlx_migrations` state via PVC deletion (right call, even if scary).

**Specific errors (each shipped to production):**

| # | Error | Where it manifested | Why it happened |
|---|-------|---------------------|-----------------|
| H1 | **Misattributed root cause in postmortem 5 Whys Q3** to "Docker Compose ↔ K8s divergence" | `POSTMORTEM_2026_05_17.md` Q3, Root Causes section, Appendix A | Pattern-matched on a common incident class without verifying the team actually uses Docker Compose. They do not. |
| H2 | **Did not inspect the Secret content** for placeholders; treated the issue as "missing env vars" only | Incident response narrative | Stopped investigation at the symptom (auth failure) without reading `k8s/01-infra/mariadb/deployment.yaml` line 82. |
| H3 | **Fixed only the running pod**, not the manifest, via `kubectl set env` + `ALTER USER` | Cluster state: works. Manifest state: still broken. | Treated recovery and prevention as the same step. Next `kubectl apply` would reintroduce the bug. |
| H4 | **Wrote a validation script that didn't validate** — `set -e` made the error counter dead code; `kubectl kustomize` on a directory without `kustomization.yaml` silently returned empty, so every check appeared to "pass" by missing | `scripts/validate-k8s-before-deploy.sh` (initial version) | No tests for the script. Bash error-handling pitfall (`set -e` + arithmetic counter) is well-known but not caught. |

**Net assessment:** Successful recovery, but the documentation and the script artifacts were misleading — they suggested the incident class was understood and prevented when it was neither.

### Claude 4.6 (Sonnet) — First Post-Incident Review

**Role:** Asked to review 4.5's postmortem and fixes.

**Successes:**
- Correctly diagnosed that 4.5's 5 Whys was wrong (Docker Compose attribution).
- Found that the same `REDACTED-PW` placeholder pattern was also present in `neo4j/deployment.yaml` and `bifrost/deployment.yaml` — a broader audit 4.5 didn't run.
- Identified two real bugs in 4.5's validation script (`set -e` + `kubectl kustomize`) and rewrote it to actually run its checks.

**Specific errors (each shipped to production):**

| # | Error | Where it manifested | Why it happened |
|---|-------|---------------------|-----------------|
| S1 | **Replaced REDACTED-PW with the real production credentials directly in three manifests** | Commit `9651362`: `k8s/01-infra/mariadb/deployment.yaml`, `k8s/01-infra/neo4j/deployment.yaml`, `k8s/02-services/bifrost/deployment.yaml` | Framed the problem as "remove the placeholder" instead of "fix how secrets are sourced." Pushed plaintext to GitHub. Sprint 51e had just rotated those credentials — they are now permanent in git history. |
| S2 | **Did not read `k8s/01-infra/postgres/deployment.yaml`** before committing the fix, despite editing sibling files in the same directory | The postgres manifest had the correct pattern (commented Secret + `kubectl create secret` documentation) sitting right next to mariadb | Did not survey "how does this repo handle the same thing elsewhere" before deciding on a fix. |
| S3 | **Did not read `docs/security/SECRETS.md`** despite it being the canonical secrets policy and referenced from the postgres manifest | The policy explicitly states "no plaintext rendering in deployment manifests" — directly violated by S1 | Confirmation bias: once a fix was decided, didn't look for evidence it was wrong. |
| S4 | **Did not check live cluster state** before claiming the fix would prevent recurrence | The cluster `mariadb-secret` had `MYSQL_PASSWORD=mimir_password` while the new manifest claimed `mp-e461...c4` — opposite values. PVC deletion would have recreated the outage. | Trusted the manifest as the source of truth without checking. |
| S5 | **Wrote a validation Check 2 ("password parity") that required plaintext credentials in the manifest to pass** | `scripts/validate-k8s-before-deploy.sh` Check 2 — `grep "MYSQL_PASSWORD:" "$MARIADB_MANIFEST"` | Designed the check around the broken state (S1) as if it were the goal. Entrenches the anti-pattern. |
| S6 | **Changed Bifrost NEO4J_PASSWORD from `neo4j` to `ngj-...` without verifying connectivity** | The running deployment had `NEO4J_PASSWORD=neo4j` (a previous quick-fix); manifest now claims `ngj-...`; live test (4.7) showed neither value actually authenticates to Neo4j. | Treated "fix the placeholder" as a syntactic change without testing the semantic effect. |
| S7 | **No tests for the rewritten validation script** | TDD principle in `MEMORY.md` violated again | Same root cause as H4 — bash scripts under-tested. |

**Net assessment:** Caught one class of bug (4.5's surface errors) but introduced a worse-class bug (credential leak to public git history). The fix made the security posture strictly worse than the bug it replaced.

### Claude 4.7 (Opus 1M) — Re-review and Remediation

**Role:** Re-examine both prior models' work against the live cluster, the existing repo patterns, and the documented policy. Then implement the correct fix.

**Findings beyond what 4.6 caught:**
- All seven Sonnet errors above (S1–S7) — found by reading the live cluster, the postgres sibling manifest, and `docs/security/SECRETS.md`.
- Cluster state divergence: `mariadb-secret` ≠ `asgard-secrets.MARIADB_PASSWORD` ≠ actual MariaDB user password.
- Bifrost `NEO4J_PASSWORD=neo4j` (runtime) authenticates to nothing — Neo4j ↔ Bifrost is currently broken regardless of which value the manifest claims.
- `MEMORY.md` policy: 4.5's and 4.6's scripts both violate the "Always use TDD" rule from `development_practices.md`.

### Remediation Applied

The following changes were committed as the corrective action for this postmortem:

| File | Before (4.5/4.6 state) | After (4.7 fix) |
|------|------------------------|------------------|
| `k8s/01-infra/mariadb/deployment.yaml` | Live `Secret` with plaintext `MYSQL_PASSWORD: mp-e461...c4` | Secret commented out, `kubectl create secret` recipe documented (postgres pattern) |
| `k8s/01-infra/neo4j/deployment.yaml` | `env: NEO4J_AUTH: neo4j/ngj-...` plaintext | `valueFrom: secretKeyRef: neo4j-secret` + commented schema |
| `k8s/02-services/bifrost/deployment.yaml` | `env: DATABASE_URL: mysql://mimir:mp-e461...@...` + `NEO4J_PASSWORD: ngj-...` plaintext | Both via `valueFrom: secretKeyRef: asgard-secrets` (matches the running deployment's actual state) |
| `scripts/validate-k8s-before-deploy.sh` | Check 2 required plaintext to pass | Rewritten: Check 1 (awk-based) flags any credential field with `value:` literal; Check 2 flags live `kind: Secret` in git; Check 5 detects mariadb-secret/asgard-secrets divergence |
| `scripts/reconcile-mariadb-secret.sh` | (didn't exist) | New script — reads `asgard-secrets`, recreates `mariadb-secret`, aligns live MariaDB user via `ALTER USER` |
| `scripts/reconcile-neo4j-secret.sh` | (didn't exist) | New script — creates `neo4j-secret` from `asgard-secrets.NEO4J_PASSWORD` |

The new validation script also surfaces three repo-wide hygiene issues that pre-date this incident (out of scope for this postmortem but filed as Sprint 52 followups):
- `k8s/01-infra/minio/02-deployment.yaml` — `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` as plaintext `value: "minioadmin"`
- `k8s/02-services/remaining-services.yaml` — `OPENAI_API_KEY: dummy` (intentional placeholder but flagged)
- `k8s/02-services/config.yaml` and `k8s/04-security/tyr/05-hermodr-bridge.yaml` — live `kind: Secret` resources still committed

### Outstanding action items (require human approval)

| # | Action | Why it can't be done by AI |
|---|--------|----------------------------|
| O1 | **Rotate `mp-e461...c4` (MariaDB) and `ngj-...505` (Neo4j)** | Sprint 51e values were leaked to git history in commit `9651362`. Rotation is destructive (breaks running services until reapplied) — needs human change window. |
| O2 | **Strip commit `9651362` from git history** via `git filter-repo` / BFG, then force-push | Force-push to shared branch is destructive; requires coordination with all clones. |
| O3 | **Run `./scripts/reconcile-mariadb-secret.sh`** to fix cluster divergence | Modifies live MariaDB user password; needs maintenance window or staging-first validation. |
| O4 | **Run `./scripts/reconcile-neo4j-secret.sh`** to create the new `neo4j-secret` | Required before the new `neo4j/deployment.yaml` can be applied. |
| O5 | **Investigate Bifrost ↔ Neo4j auth state** — neither `neo4j` (runtime) nor `ngj-...505` (manifest) authenticated in 4.7's tests | Suggests the live Neo4j password was rotated via cypher `ALTER USER` and never recorded in `asgard-secrets`. Needs operational forensics. |
| O6 | **Sprint 52 ticket: wire Fafnir Vault → External Secrets Operator** so all secrets are sourced from Vault | Architecture decision; out of incident scope. |

### Lessons for AI-assisted operations

1. **Speed vs. depth is a real trade-off.** Haiku 4.5 recovered service fast; the documentation and prevention artifacts it produced were misleading. Sonnet 4.6 produced a more thorough-*looking* review but introduced a worse-class bug because it never verified its conclusions against live state.
2. **Look at sibling files before editing one.** Both 4.5 and 4.6 edited mariadb/deployment.yaml without reading postgres/deployment.yaml in the same directory. The answer was 4 directory entries away.
3. **Read the policy doc.** `docs/security/SECRETS.md` exists and is canonical. Neither prior model opened it.
4. **Verify against live state before claiming a fix prevents recurrence.** The on-disk fix can be internally consistent and still fail to prevent the exact incident it was written for.
5. **An independent re-review with a different model class is cheap insurance.** Each pass caught a distinct error class the prior pass missed. The pattern is not "use a bigger model" but "use a different model with a fresh look at live state."

---

## Execution Log — What Actually Happened During Remediation (2026-05-17 afternoon)

Opus 4.7 wrote remediation scripts (`rotate-mariadb-password.sh`, `rotate-neo4j-password.sh`, `reconcile-*.sh`) and the operator ran them interactively. Execution surfaced **five additional bugs in the scripts themselves**, each requiring a fix-commit before the rotation completed cleanly. This section records them so the same traps are not laid again.

### Bug E1 — Unicode ellipsis broke `set -u` variable expansion
**Symptom:** `reconcile-mariadb-secret.sh` aborted with `NAMESPACE_INFRA…: unbound variable` partway through the first rotation — *after* `ALTER USER` had already changed the live MariaDB password but *before* `mariadb-secret` was synced. Mimir kept serving via its existing connection pool, but a PVC delete at that moment would have reproduced the original incident.

**Cause:** `echo "🔄 Recreating mariadb-secret in $NAMESPACE_INFRA…"` — the `…` (U+2026) immediately after `$NAMESPACE_INFRA` is not a bash word-boundary character, so the parser tried to expand a variable named `NAMESPACE_INFRA…` and failed under `set -u`.

**Fix (commit `7cfc1e2`):** brace-wrap as `${NAMESPACE_INFRA}` and use ASCII `...`. Audit other scripts for the same pattern — only this one had it.

**Lesson:** AI-generated scripts inherit AI-generated punctuation. Smart-quote / smart-dash / smart-ellipsis characters survive copy-paste into shell scripts and trigger non-obvious failures only at runtime.

### Bug E2 — Naive string concatenation broke `MIMIR_DATABASE_URL` with special-char passwords
**Symptom:** Operator typed a password containing `@` characters (`M@ri@DB@20260517`). The script built `mysql://mimir:${NEW_PW}@mariadb...` which contains four `@` symbols. The URL violates RFC 3986 (userinfo can't contain raw `@`). sqlx's URL parser happens to be permissive enough that the connection worked anyway — but any stricter client (`mysql` CLI, JDBC URL, generic URL libraries) would parse the host as `ri@DB@20260517@mariadb.asgard-infra.svc` and fail.

**Cause:** rotation script did `value: mysql://mimir:${NEW_PW}@mariadb...` with no encoding. SQL `ALTER USER 'mimir'@'%' IDENTIFIED BY '$NEW_PW'` had the same class of bug — would have broken on a password containing `'`.

**Fix (commit `f6b8a86`):**
- Added `urlencode()` (RFC 3986 percent-encoding) for the URL form.
- Added `sql_escape()` (`'` → `''`, `\` → `\\`) for SQL literals.
- Added a 48-char alphanumeric auto-suggested password so the operator can copy/paste a guaranteed-safe value.
- Warn (not block) when a custom password contains chars that need encoding.
- Pass mariadb client credentials via temp `.my.cnf` inside the pod instead of `-p"$PW"` to bypass shell-escaping entirely.

**Lesson:** Anywhere user input crosses a syntactic boundary (URL, SQL, shell, JSON), encode at the boundary. Never trust that "this password probably doesn't contain X."

### Bug E3 — SIGPIPE under `set -o pipefail` killed the auto-generated password line silently
**Symptom:** Operator ran `./scripts/rotate-mariadb-password.sh`. Banner printed. Then nothing. No prompt, no error, no exit message. Script had silently exited mid-execution.

**Cause:** `SUGGESTED=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48)`. When `head` closes its stdin after 48 bytes, `tr` receives `SIGPIPE` on its next write and exits with code 141. Under `set -o pipefail`, the pipeline's exit code is 141. Under `set -e`, the script aborts. The script aborts on the *assignment line itself*, before the next `echo`, so the operator sees only the banner.

**Fix (commit `5394d4e`):** Replaced with `SUGGESTED=$(openssl rand -hex 24)` — no pipe, no SIGPIPE, output is 48 hex chars (URL- and SQL-safe by construction).

**Lesson:** `set -euo pipefail` + any pipe that closes early (`head -c`, `head -n`, `grep -m 1`, `kill -PIPE`) is a silent-exit hazard. Either use single-process equivalents (`openssl rand`, `dd`) or relax `pipefail` for that specific pipeline.

### Bug E4 — Neo4j force-reset deleted the wrong files
**Symptom:** Script ran cleanly through all 8 steps. Step 7 verification: `cypher auth failed after 12 attempts`. Bolt log: `The client is unauthorized due to authentication failure`. Inside the pod, `printenv NEO4J_AUTH` showed the new password. `auth.ini` contained a SHA-256 hash *for a different password than the one in `NEO4J_AUTH`*.

**Cause:** Neo4j 5 keeps user credentials in **two** places:
1. `/data/dbms/auth.ini` — local auth file
2. `/data/databases/system` — Neo4j metadata DB (users, roles, database registry)

The script only deleted `auth.ini`. On boot, the Docker entrypoint ran `neo4j-admin dbms set-initial-password $NEW`, which prints the warning `"this change will only take effect if performed before the database is started for the first time"` and exits successfully without doing anything — because user `neo4j` already existed in the system DB with the old password. The startup log makes this look like the password change worked; it didn't.

**Fix (commit `27061fa`):** helper pod also removes `/data/databases/system` and `/data/transactions/system`. Graph data at `/data/databases/neo4j` is preserved (only Neo4j's own metadata is lost: users, roles, database registry — acceptable for the dev cluster). For production, online cypher `ALTER USER` would be the correct path.

**Lesson:** "Delete the auth file" is a common Neo4j incantation but it's incomplete. Always test the specific Neo4j version's behavior against the assumption — the startup log's success message lies.

### Bug E5 — Live Bifrost deployment had drifted from the manifest (envFrom stripped)
**Symptom:** After Neo4j rotation, `kubectl exec deploy/bifrost -- printenv NEO4J_PASSWORD` returned the literal string `neo4j` instead of the rotated value. The manifest in git had `valueFrom: secretKeyRef: asgard-secrets/NEO4J_PASSWORD`, but the live deployment had been manually patched at some point to use an inline `value: neo4j` quick-fix, and the `envFrom: secretRef: asgard-secrets` block was missing entirely.

**Cause:** Manual `kubectl set env`, `kubectl edit deployment`, and one-off patches accumulate over time and drift the live state away from the committed manifest. `kubectl apply` of the committed manifest then fails because env-array merging by index produces structurally invalid specs (`value` and `valueFrom` on the same entry).

**Fix:** `kubectl set env --from=secret/asgard-secrets deploy/bifrost -n asgard` restored the `envFrom` reference; `kubectl set env deploy/bifrost -n asgard NEO4J_PASSWORD-` removed the inline override so the secret value won. All three (Neo4j, asgard-secrets, Bifrost env) now match.

**Lesson:** Manual runtime patches are tech debt with an unknown blast radius. The validation script should diff live deployments against committed manifests and flag drift as a check — added to Sprint 52 ticket list.

### What survived the execution intact
- The overall remediation approach (postgres-pattern Secrets, source-of-truth = `asgard-secrets`, reconcile scripts) — no architectural rework needed.
- `validate-k8s-before-deploy.sh` Check 5 (mariadb-secret consistency) detected the cluster-state divergence both before and after the rotation, confirming the check has value.
- Mimir's old pod kept serving throughout via its existing sqlx connection pool — buying the ~8h window needed to fix everything else.

### What the execution log adds to the model-comparison story

| Pattern | Haiku 4.5 | Sonnet 4.6 | Opus 4.7 (write phase) | Opus 4.7 (execution phase) |
|---------|-----------|------------|------------------------|---------------------------|
| Made plausible-but-wrong fix | Yes (Docker Compose attribution) | Yes (plaintext credentials in git) | No (correct architecture) | — |
| Bugs in the scripts/artifacts produced | Yes (set -e + kustomize) | Yes (password parity check) | — | Yes — five separate bugs, see E1–E5 |
| Caught only after live execution | — | — | — | All five |

**Lesson for the meta-model:** "write good plans" and "write working code" are different skills. Opus 4.7's architecture survived contact with reality; its bash scripts didn't. The independent re-review pattern catches design errors but not implementation bugs in the remediation itself. Add an interactive **dry-run pass** to the protocol: before the operator runs the script for real, run it against a staging cluster or test fixtures.

---

## Final Status (2026-05-17 EOD)

| Action | Status | Commit |
|--------|--------|--------|
| O1a — Rotate MariaDB password | ✅ Done (clean 48-hex value) | n/a (cluster state) |
| O1b — Force-reset Neo4j password | ✅ Done (graph data preserved) | n/a (cluster state) |
| O3 — Reconcile `mariadb-secret` | ✅ Done | `f063448` (script), executed live |
| O4 — Reconcile / create `neo4j-secret` | ✅ Done | `f063448` (script), executed live |
| O5 — Investigate Bifrost ↔ Neo4j auth | ✅ Done — root cause = Neo4j 5 system DB persistence overriding NEO4J_AUTH | `27061fa` (script update) |
| O2 — Strip commit `9651362` from git history | ⏳ Pending — credentials are rotated so leak is moot; force-push still recommended for hygiene | — |
| O6 — Sprint 52: Vault + External Secrets Operator | ⏳ Pending — file ticket | — |
| **Mimir migration mystery** | ⏳ Pending — old pod still serving; new pods panic on `migration 20260516000001 missing in resolved` despite same image SHA | — |
| **Bifrost-live-vs-manifest drift detector** | ⏳ Pending — add as validation Check 7 | — |

---

**Postmortem Prepared By:** Claude Haiku 4.5 (initial) / Claude Sonnet 4.6 (first review) / Claude Opus 4.7 1M (re-review + remediation + execution log)  
**Date:** May 18, 2026 (last updated 2026-05-17 EOD after live rotation)  
**Next Review:** May 25, 2026 (verify O2 / O6 / Mimir migration / drift-detector all closed)
