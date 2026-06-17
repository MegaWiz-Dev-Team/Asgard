# Loki - Authorized Internal Penetration Testing Service

**Status**: ⚠️ **INTERNAL AUTHORIZED TESTING ONLY**

Loki is a dedicated Kali Linux-based penetration testing container for validating Asgard's security defenses (Tyr SIEM, Muninn auto-remediation, authentication, data protection).

## ⚠️ SECURITY WARNING

- **DO NOT** deploy to production clusters without explicit authorization
- **DO NOT** use against systems outside authorized scope (Asgard defenses)
- **DO NOT** exfiltrate real patient/medical data during testing
- All traffic is marked with `X-Loki-Test: true` and `X-Tenant-Id: asgard_platform` headers
- Tyr SIEM automatically **isolates** and **tags** Loki's traffic for analysis
- Tests are recorded in `asgard_platform` tenant (separate from `asgard_medical` / `asgard_insurance`)

## Architecture

```
Loki Pod (Kali Linux)
├─ Test Scripts (ConfigMap)
│  ├─ api-injection-test.sh       → Bifrost (SQL, parameter tampering, JWT)
│  ├─ prompt-injection-test.sh    → Heimdall (jailbreak, reasoning bypass)
│  ├─ data-exfiltration-test.sh   → Mimir/Syn/MariaDB (unauthorized access)
│  └─ tyr-detection-test.sh       → Verify Tyr correctly detects threats
├─ Test Payloads (ConfigMap)
│  ├─ sql-injection-payloads.txt
│  ├─ prompt-injection-payloads.txt
│  └─ jwt-manipulation.txt
└─ Security Controls
   ├─ ServiceAccount + RBAC (read-only configmaps, pods)
   ├─ NetworkPolicy (egress to Bifrost/Heimdall/Mimir/Syn/Qdrant/MariaDB only)
   └─ Tyr Annotations (pod labeled as authorized test)
```

## Deployment

### Prerequisites

1. Asgard K8s cluster running (OrbStack / local dev)
2. Tyr SIEM deployed
3. Docker image built locally

### Build Image

```bash
cd Asgard/k8s/04-security/loki
docker build -t asgard-loki:latest .
```

### Deploy to K8s

```bash
# Build image first
docker build -t asgard-loki:latest Asgard/k8s/04-security/loki/

# Apply all K8s manifests
kubectl apply -f Asgard/k8s/04-security/loki/01-rbac.yaml
kubectl apply -f Asgard/k8s/04-security/loki/02-deployment.yaml
kubectl apply -f Asgard/k8s/04-security/loki/03-network-policy.yaml
kubectl apply -f Asgard/k8s/04-security/loki/04-configmaps.yaml

# Verify deployment
kubectl -n asgard get pod -l app=loki
kubectl -n asgard logs loki
```

### Port Mapping (Local Dev)

```bash
# Interactive shell access (if using local K3s)
kubectl -n asgard exec -it loki -- /bin/bash
```

## Test Suites

### 1. API Injection Testing

**Target**: Bifrost orchestrator API

```bash
kubectl -n asgard exec -it loki -- bash
cd /opt/loki/scripts
./api-injection-test.sh
```

**Tests**:
- SQL injection in `/knowledge/search`
- Parameter tampering in `/agents/query`
- JWT token manipulation (expired, invalid signature)
- Authorization bypass attempts

**Expected Results**:
- Bifrost rejects malformed SQL (prepared statements)
- JWT validation fails on tampered tokens
- Tyr logs all attempts with `[INJECTION_ATTEMPT]` tag

### 2. Prompt Injection Testing

**Target**: Heimdall LLM gateway

```bash
./prompt-injection-test.sh
```

**Tests**:
- Direct system prompt override
- Indirect injection via RAG context
- Role elevation ("You are an admin")
- Safety filter bypass

**Expected Results**:
- Heimdall's Skuggi middleware blocks tier-1 text injection
- CloudML requests rejected if confidence < threshold
- Tyr detects patterns and scores risk

### 3. Data Exfiltration Testing

**Target**: Mimir API, Syn OCR, Vector DB, MariaDB

```bash
./data-exfiltration-test.sh
```

**Tests**:
- Direct MariaDB login (should fail - no root password)
- Knowledge base enumeration (expect 403 without auth)
- Qdrant collection listing
- PII extraction via OCR

**Expected Results**:
- Database access denied (authentication required)
- API returns 401 for unauthenticated requests
- OCR returns redacted output if PII detected

### 4. Tyr Detection Validation

**Verify** Tyr SIEM correctly detects and logs test traffic:

```bash
./tyr-detection-test.sh

# Check Tyr Dashboard
open https://wazuh.asgard.internal/
# Login as admin
# Search for pod IP: $LOKI_POD_IP
# Filter for X-Loki-Test: true header
```

## Traffic Markers

**All Loki requests include these headers automatically**:

```http
X-Loki-Test: true              # Identifies test traffic
X-Tenant-Id: asgard_platform   # Isolated evaluation tenant
X-Forwarded-For: <pod-ip>      # Source identification
Authorization: Bearer <test-jwt> # Test credentials (if applicable)
```

**Bifrost annotations**:

```yaml
tyr.asgard.io/security-test: "true"
tyr.asgard.io/test-authorized: "authorized-internal-testing"
```

Tyr SIEM automatically suppresses false-positive alerts for traffic matching these markers.

## Compliance & Audit

### What Gets Logged

- ✅ All API requests to Bifrost/Heimdall/Mimir (Tyr)
- ✅ Injection attempt signatures (SQL, prompt, header)
- ✅ Pod IP, namespace, service account
- ✅ Timestamp, request body, response code

### What Does NOT Get Logged

- ❌ Real patient data (asgard_medical / asgard_insurance tenants)
- ❌ Production credentials
- ❌ Actual exploits (test payloads only)

### Audit Trail

Check Mimir evaluation runs for Loki test results:

```bash
curl -X GET \
  -H "X-Tenant-Id: asgard_platform" \
  "http://mimir-api.asgard.svc.cluster.local:8090/api/v1/evaluations" \
  | jq '.[] | select(.source == "loki-security-test")'
```

## Troubleshooting

### Pod stuck in CrashLoopBackOff

```bash
kubectl -n asgard logs loki
# Check: Kali image pulls correctly
# Check: ConfigMap mounted successfully
```

### Cannot reach Bifrost

```bash
kubectl -n asgard exec -it loki -- \
  curl -v http://bifrost.asgard.svc.cluster.local:8000/health
```

### Tests blocked by NetworkPolicy

```bash
# Verify NetworkPolicy allows egress to targets
kubectl -n asgard describe networkpolicy loki

# Temporarily disable (development only)
kubectl -n asgard delete networkpolicy loki loki-deny-untrusted
```

### Tyr not detecting traffic

1. Verify pod annotations:
   ```bash
   kubectl -n asgard get pod loki -o yaml | grep -A2 tyr
   ```
2. Check Tyr is running:
   ```bash
   kubectl -n asgard get pod -l app=wazuh-manager
   ```
3. Add test-marker to requests manually:
   ```bash
   curl -H "X-Loki-Test: true" http://bifrost:8000/health
   ```

## Cleanup

### Remove Loki from cluster

```bash
kubectl delete ns asgard -l app=loki  # or
kubectl -n asgard delete deployment loki
kubectl -n asgard delete service loki
kubectl -n asgard delete sa loki
kubectl -n asgard delete role,rolebinding -l app=loki
kubectl -n asgard delete networkpolicy -l app=loki
kubectl -n asgard delete configmap loki-test-scripts loki-test-payloads
```

### Remove Docker image

```bash
docker rmi asgard-loki:latest
```

## Related Services

- **Tyr**: SIEM detection of security tests
- **Muninn**: Auto-remediation (quarantine malicious requests during tests)
- **Wazuh**: Underlying SIEM agent
- **Bifrost**: API orchestrator (primary target)
- **Heimdall**: LLM gateway (prompt injection target)

## Next Steps (Future Enhancements)

- [ ] Integration with MetaSploit for advanced exploit generation
- [ ] Continuous security regression suite (runs daily)
- [ ] Fuzzing harness for API parameter space
- [ ] Load-based testing (validate Tyr doesn't drop alerts under load)
- [ ] Purple team exercises (red vs blue simulation)

---

**Questions?** Contact: security-team@asgard.internal
**Last Updated**: 2026-05-28
**Maintained By**: Asgard Security Team
