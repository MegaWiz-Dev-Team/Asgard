# Customer Deployment Runbook — Fresh Mac mini Bootstrap

**Audience:** Operator deploying Asgard to a new customer's Mac mini.
**Outcome:** Working stack with all shared knowledge bases populated.
**Time:** ~4 hours unattended + ~30 min hands-on. Heavy on first-run waits
(model downloads, PrimeKG import, optional LOINC).

Per ADR-009 (single-tenant per Mac mini), every customer gets their own
isolated box. This document is the recipe for that box.

---

## Phase 0 — Hardware + OS prerequisites

| Requirement | Detail |
|---|---|
| Mac mini M-series (M2 Pro or higher) | Required for MLX inference (Heimdall) |
| RAM ≥ 32GB | 64GB recommended for parallel gemma-26b + medgemma-27b loads |
| Disk ≥ 500GB SSD | OS + models (~100GB) + Neo4j PrimeKG (~5GB) + Qdrant (~10GB) + per-tenant docs |
| macOS 15.0+ | OrbStack + K3s + launchd compatibility |
| Static LAN IP | For clinic intranet access (no port forward, no public internet ingress) |

---

## Phase 1 — Bootstrap the infrastructure (~1h)

### 1.1 Install host tooling

```bash
# Homebrew, OrbStack, kubectl, jq
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install --cask orbstack
brew install kubectl jq
```

OrbStack ships its own K3s — start it from the OrbStack app and create a
single-node cluster named `orbstack`.

### 1.2 Clone the Asgard meta-repo

```bash
mkdir -p ~/Developer && cd ~/Developer
git clone https://github.com/MegaWiz-Dev-Team/Asgard.git
cd Asgard
```

### 1.3 Run the one-command stack deploy

Per `asgard_complete_deploy_script` memory: this is the canonical bootstrap.

```bash
./scripts/deploy-all.sh
```

What it does (15 services, ~5-15 min):
- K3s namespaces: `asgard`, `asgard-infra`, `asgard-public`
- Infra pods: **MariaDB**, **Qdrant**, **Neo4j**, MinIO, Redis, Postgres
- App pods: Bifrost, Mimir, Eir, Hermodr, Syn, Tyr, Muninn, Skuggi…
- **Heimdall** native via launchd (`scripts/quick-setup.sh` — NOT in K8s)

Verify everything is Running:

```bash
kubectl get pods -A | grep -vE "Running|Completed"   # should be empty
launchctl list | grep com.asgard.heimdall            # 5 services up
```

### 1.4 First-run model download (~30 min unattended)

Heimdall pre-downloads MLX models on first start. Watch:

```bash
tail -f ~/Library/Logs/com.asgard.heimdall.*.log
```

Expect: `mlx-community/gemma-4-26b-a4b-it-4bit` (~16GB),
`mlx-community/medgemma-27b-text-it-4bit` (~14GB),
`MegawizCo/typhoon-ocr-3b-mlx-q4`, `BAAI/bge-m3` (~2GB).
Done when `curl localhost:8080/v1/models` returns the full list.

---

## Phase 2 — Shared knowledge bases (~2h)

These are universal reference data (`tenant_id=NULL`) — every tenant on the
box uses them. **Required before any clinical use.**

### 2.1 ICD-10-TM (Thai diagnoses, ~5 min)

Download the anamai PDF once, parse, ingest:

```bash
cd ~/Developer/Mimir

# Apply migration (sqlx::migrate! doesn't pick up sprint-prefixed files
# automatically — see s1_e2e_manual_2026_05_18 memory)
kubectl port-forward svc/mariadb 33306:3306 -n asgard-infra &
mysql -h 127.0.0.1 -P 33306 -u root -proot mimir \
  < ro-ai-bridge/migrations/sprint48_icd10_codes.sql

# Download PDF (anamai is free public; URL stable since 2010)
curl -o /tmp/icd10tm_anamai.pdf \
  https://backenddc.anamai.moph.go.th/coverpage/d1579eb1c80b878ab62513c060681290.pdf

# Ingest
python scripts/icd10_tm_anamai_ingest.py \
  --pdf /tmp/icd10tm_anamai.pdf \
  --source-version anamai-moph-2010
```

Expected: 15,376 rows in `icd10_codes`.

ICD-10-TM Qdrant collection `icd10-th` is populated by Mimir's admin route
(same pattern as PrimeKG below — see 2.3).

### 2.2 PrimeKG → Neo4j (~10 min)

```bash
cd ~/Developer/Mimir

# Download kg.csv from Harvard Dataverse (free, public, ~936MB)
mkdir -p data/PrimeKG
curl -L -o data/PrimeKG/kg.csv \
  "https://dataverse.harvard.edu/api/access/datafile/$(...)"   # see PRIMEKG_DATA_REPORT.md for exact file id

# Run the import (idempotent; uses APOC LOAD CSV)
export NEO4J_PASS="$(kubectl -n asgard-infra get secret neo4j-secret \
  -o jsonpath='{.data.NEO4J_PASSWORD}' | base64 -d)"
bash scripts/primekg_import.sh ./data/PrimeKG/kg.csv
```

Expected: 129,375 nodes + 8.1M edges. Real-world time on M2 Pro 2026-05-18:
**6m36s** (vs the 2-6h budget in the original sprint plan).

### 2.3 PrimeKG → Qdrant embed (~5 min)

Mimir embeds PrimeKG node names via Heimdall BGE-M3 and upserts into the
`primekg-entities` Qdrant collection (1024-dim).

```bash
# Generate an HS256 JWT for the admin endpoint (iss MUST be "mimir-auth")
# Production deployments use Yggdrasil RS256 instead — this is for the
# bootstrap operator only.
JWT=$(python3 -c "
import jwt, time
print(jwt.encode({
    'iss': 'mimir-auth',
    'sub': 'bootstrap',
    'tenant_id': 'asgard_medical',
    'role': 'admin',
    'exp': int(time.time()) + 3600,
}, '<JWT_SECRET from asgard-secrets>', algorithm='HS256'))
")

# Trigger embed (non-blocking)
curl -X POST http://mimir.asgard.internal/api/v1/admin/knowledge/primekg/embed \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"batch_size":500,"dry_run":false}'

# Poll status
while true; do
  curl -s http://mimir.asgard.internal/api/v1/admin/knowledge/primekg/embed/status \
    -H "Authorization: Bearer $JWT" | jq .
  sleep 10
done
```

Expected: 129,374 points in `primekg-entities` (1 below Neo4j due to a
duplicate `entity_index` in the upstream CSV — not a defect).

### 2.4 LOINC (optional, ~10 min, requires manual download)

Powers FHIR `Observation.code` binding for labs/vitals. Free under LOINC
license but requires a one-time account at https://loinc.org/join-loinc/.

```bash
# After registering, download LOINC_<ver>_Source.zip, unzip
mysql -h 127.0.0.1 -P 33306 -u root -proot mimir \
  < ro-ai-bridge/migrations/sprint49_loinc_codes.sql

python scripts/loinc_ingest.py \
  --csv /path/to/Loinc.csv \
  --source-version loinc-2.78
```

Expected: ~98K rows.

If skipped: FHIR `Observation.code` validation degrades to "code present"
without confirming the system. Eir agents still work.

### 2.5 TMT / TPC — license-blocked, skip

Thai Medicines Terminology and Thai Procedural Classification are
license-blocked at MoPH. Per 2026-05-18 direction, fallback is:
`MedicationRequest.medicationCodeableConcept` and `Procedure.code` accept
any CodeableConcept until data exists.

### 2.6 Verify shared catalog

```bash
curl http://mimir.asgard.internal/api/v1/knowledge/shared \
  -H "Authorization: Bearer $JWT" | jq '.items[] | {id, status, counts}'
```

Expected (after 2.1–2.3, before 2.4):

```json
{ "id": "icd10-tm", "status": "active",       "counts": {"mariadb_codes": 15376, "qdrant_points": 15376} }
{ "id": "primekg",  "status": "active",       "counts": {"neo4j_nodes": 129375, "neo4j_edges": 8100128, "qdrant_points": 129374} }
{ "id": "loinc",    "status": "pending_data", "counts": {"mariadb_codes": 0} }
{ "id": "tmt",      "status": "pending_data", "counts": {} }
{ "id": "tpc",      "status": "pending_data", "counts": {} }
```

Or, easier: open https://mimir.asgard.internal/knowledge/shared in a
browser. All 5 KBs visible with status badges.

---

## Phase 3 — Customer tenant + agents (~30 min)

### 3.1 Tenant recovery script

Per `asgard_tenant_recovery` memory:

```bash
kubectl exec -n asgard-infra deploy/mariadb -- \
  mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" \
  < ~/Developer/Mimir/scripts/recover-asgard-tenant.sql
```

This creates the `asgard_medical` tenant + 6 Eir agents (router + cardio +
sleep + ent + peds + base) wired to `gemma-4-26b` local model.

For an `asgard_insurance` deployment, use the insurance variant
(`scripts/recover-asgard-insurance-tenant.sql` — TBD; for current pre-S2
deployments this is `asgard_medical` only).

### 3.2 Bounce Bifrost

```bash
kubectl rollout restart deploy/bifrost -n asgard
```

### 3.3 Smoke-test the chat surface

Open https://bifrost.asgard.internal in a browser → login (Yggdrasil OIDC
or static-key dev mode) → start a chat with Eir → ask:

- "ICD-10 ของเบาหวาน" → should return E11
- "ผลข้างเคียงของ aspirin" → PrimeKG-backed answer

---

## Phase 4 — Per-customer data ingest (ongoing)

Beyond shared KBs, the customer's own documents go in via:

| Path | Use case |
|---|---|
| `/sources` UI → "Add Source" | Manual PDF/URL upload (clinic protocols, formularies) |
| `/api/v1/tenants/{tenant_id}/ingest` | Programmatic bulk upload |
| **NOT** shared knowledge route | Per-tenant data must keep `tenant_id=<slug>` so it stays isolated |

Per `asgard_shared_knowledge_surface` feedback memory: never put
customer-specific data into the shared catalog. The `tenant_id IS NULL`
filter is the boundary.

---

## Phase 5 — Cutover checklist

Hand-off to the customer's IT / clinical lead:

- [ ] `https://mimir.asgard.internal/knowledge/shared` shows ≥3 active KBs (ICD-10, PrimeKG, + optionally LOINC)
- [ ] `https://bifrost.asgard.internal` Eir agents respond to medical queries
- [ ] Yggdrasil RS256 JWT issuing for production users (`asgard_jwt_auth_pattern` memory)
- [ ] Tyr SIEM monitoring active (`asgard_tyr_siem` memory)
- [ ] Backup cron scheduled (`scripts/backup.sh` daily)
- [ ] No external internet ingress (clinic intranet only)
- [ ] Asgard logo + customer tenant name visible in Bifrost UI

---

## Troubleshooting cheatsheet

| Symptom | Root cause | Fix |
|---|---|---|
| `/api/v1/icd10/lookup` returns "mimir_test.icd10_codes doesn't exist" | dotenv `.env` has stale `DATABASE_URL` | Edit `Mimir/ro-ai-bridge/.env` to point to actual mariadb URL. Both `DATABASE_URL` AND `MARIADB_URL` must be set. |
| PrimeKG embed returns `{"error":"No PrimeKG nodes found"}` despite Neo4j populated | `NEO4J_PASSWORD` env not set in Mimir process | Restart Mimir API with `NEO4J_PASSWORD` exported from `asgard-secrets`. Process retries silently and returns 0. |
| JWT returns 401 `InvalidIssuer` | HS256 JWT must have `iss=mimir-auth` (legacy) or RS256 from Yggdrasil | Use the exact issuer string `mimir-auth` for HS256 ops tokens. Production = Yggdrasil. |
| Heimdall returns "model not loaded" | MLX model still downloading | `tail -f ~/Library/Logs/com.asgard.heimdall.*.log`; wait. |
| `primekg-entities` Qdrant collection at 0 points | Either Neo4j empty (rotation reaped PVC), or Mimir Ollama leak in `routes/icd10.rs` (fixed in PR #306) | Verify `MATCH (n:PrimeKG) RETURN count(n)` in Neo4j > 0 first. Then re-trigger embed. |

---

## See also

- [ADR-009 Single-tenant per Mac mini](../decisions/ADR-009-single-tenant-mac-mini-deployment.md)
- [asgard_heimdall_deployment memory](~/.claude/projects/-Users-mimir-Developer/memory/asgard_heimdall_deployment.md)
- [asgard_complete_deploy_script memory](~/.claude/projects/-Users-mimir-Developer/memory/asgard_complete_deploy_script.md)
- [s1_e2e_manual_2026_05_18 memory](~/.claude/projects/-Users-mimir-Developer/memory/s1_e2e_manual_2026_05_18.md) — local dev pitfalls
- Mimir PR #307 (LOINC scaffolding), #308 (Shared Knowledge UI)
