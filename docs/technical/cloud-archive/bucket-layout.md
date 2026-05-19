# GCS Bucket Layout

Single bucket `gs://asgard-archive` in GCP project `asgard-489513`. Per-tenant isolation via prefix + IAM Conditions, not per-bucket.

## Top-level structure

```
gs://asgard-archive/
├── _platform/                   Megawiz internal; no per-tenant data
│   ├── models/                   custom fine-tunes (when produced)
│   │   └── <model-name>/<semver>/
│   │       ├── weights.safetensors
│   │       ├── tokenizer.json
│   │       ├── training-config.toml
│   │       ├── eval-report.md
│   │       └── MANIFEST.json
│   ├── eval-baselines/           reproducibility snapshots
│   │   └── <YYYY-MM-DD>-<bench-name>/
│   │       ├── scoreboard.json
│   │       ├── traces.jsonl.zst
│   │       └── MANIFEST.json
│   ├── platform-metrics/         asgard_platform tenant aggregate (hash-only, no PHI)
│   │   └── <YYYY>/<MM>/<DD>/
│   └── code-snapshots/           umbrella repo bundles (replaces T7 7.6 GB style)
│       └── <YYYY-MM-DD>-<tag>/
│           ├── repos.tar.zst
│           ├── k8s-manifests.tar.zst
│           ├── helm-releases.yaml
│           └── MANIFEST.json
│
├── tenants/
│   ├── <tenant_id>/              one prefix per customer Mac mini
│   │   ├── tyr/                  SIEM
│   │   │   ├── alerts/<YYYY>/<MM>/<DD>/alerts-<YYYY-MM-DD>.jsonl.zst
│   │   │   ├── audit/<YYYY>/<MM>/<DD>/audit-<YYYY-MM-DD>.jsonl.zst
│   │   │   └── fim/<YYYY>/<MM>/<DD>/fim-<YYYY-MM-DD>.jsonl.zst
│   │   ├── bifrost/              agent decision frames (clinical accountability)
│   │   │   └── frames/<YYYY>/<MM>/<DD>/
│   │   │       └── <session-id>.mv2
│   │   ├── eir/                  OpenEMR clinical data (PHI, CMEK required)
│   │   │   └── db-dumps/<YYYY>/<MM>/<DD>/openemr-<YYYY-MM-DD>.sql.zst
│   │   ├── mimir/                RAG state
│   │   │   ├── mariadb/<YYYY>/<MM>/<DD>/mimir-<YYYY-MM-DD>.sql.zst
│   │   │   ├── qdrant/<YYYY>/<MM>/<DD>/<collection>.snapshot
│   │   │   ├── neo4j/<YYYY>/<MM>/<DD>/primekg-dump.cypher.zst
│   │   │   └── rustfs/<YYYY>/<MM>/<DD>/blobs.tar.zst
│   │   ├── syn/                  OCR redaction audit (NO raw images)
│   │   │   └── redactions/<YYYY>/<MM>/<DD>/
│   │   │       ├── audit.jsonl.zst
│   │   │       └── extracted-text.jsonl.zst
│   │   ├── heimdall/             LLM call audit (hash-only by default)
│   │   │   └── calls/<YYYY>/<MM>/<DD>/calls-<YYYY-MM-DD>.jsonl.zst
│   │   └── _meta/
│   │       ├── catalog.json      this tenant's data-catalog manifest
│   │       └── retention.toml    tenant-specific retention overrides
│   └── ...
│
└── _manifests/                   global indexes (read-only by ops)
    ├── catalog-index.json         lists all tenants + last upload timestamp
    └── lifecycle-policy.json      retention rules per data class
```

## Naming conventions

| Token | Format | Example |
|---|---|---|
| `<tenant_id>` | snake_case, matches tenant in MariaDB `tenant_configs` | `asgard_medical`, `asgard_insurance`, `megacare` |
| `<YYYY>/<MM>/<DD>` | zero-padded date path, UTC | `2026/05/19` |
| Object filename date | `<YYYY-MM-DD>` (ISO-ish) | `alerts-2026-05-19.jsonl.zst` |
| Compression suffix | `.zst` (zstd lvl 19) for cold data | `audit.jsonl.zst` |
| Multi-collection per service | named subkey | `qdrant/<YYYY>/<MM>/<DD>/icd10-th.snapshot` |

**Why UTC dates everywhere:** archive runs at the tenant's local 02:00 but objects key on UTC date to keep cross-tenant analytics consistent.

## IAM model

Three principal classes, three permission shapes:

| Principal | Resource scope | Permissions |
|---|---|---|
| `tyr-archive-uploader@asgard-489513.iam.gserviceaccount.com` (per-tenant SA) | `tenants/<tenant_id>/*` | `storage.objects.create` only — NO read, NO delete, NO list across tenants |
| `archive-ops@asgard-489513` (Megawiz operations) | `gs://asgard-archive/*` | `storage.objects.list` + `storage.objects.get` (decrypt fails without customer KMS access for PHI objects) |
| `restore-<tenant_id>@asgard-489513` (issued on demand for restore) | `tenants/<tenant_id>/*` | `storage.objects.get` for 24h + IAM Condition `resource.name.startsWith(...)` |

**IAM Condition example for uploader:**
```yaml
- role: roles/storage.objectCreator
  members:
    - serviceAccount:tyr-archive-uploader-asgard-medical@asgard-489513.iam.gserviceaccount.com
  condition:
    title: write_only_own_tenant
    description: Can only write under tenants/asgard_medical/
    expression: resource.name.startsWith("projects/_/buckets/asgard-archive/objects/tenants/asgard_medical/")
```

This prevents a compromised Mac mini from reading other tenants' archives or its own past uploads.

## Encryption

| Data class | Encryption | Key custody |
|---|---|---|
| `_platform/*` (Megawiz internal) | Google-managed (default) | Google |
| `tenants/<id>/tyr/*` (SIEM audit, no PHI) | Google-managed | Google |
| `tenants/<id>/eir/*` (OpenEMR PHI) | CMEK | Customer's KMS keyring |
| `tenants/<id>/bifrost/*` (decision frames may reference patient) | CMEK | Customer's KMS keyring |
| `tenants/<id>/mimir/*` (depends on tenant — medical = PHI, insurance = PII) | CMEK | Customer's KMS keyring |
| `tenants/<id>/syn/*` (redacted text + audit only) | CMEK | Customer's KMS keyring |
| `tenants/<id>/heimdall/*` (hash-only) | Google-managed | Google |

**CMEK key naming**: `projects/asgard-489513/locations/asia-southeast1/keyRings/<tenant_id>/cryptoKeys/asgard-archive`

## Object Lock + Versioning

**Bucket Lock is bucket-level, not prefix-level.** A single retention period applies to the entire bucket — you cannot mix "7 yr on tyr/ and 10 yr on eir/" via Bucket Lock alone. We combine three mechanisms to get per-prefix retention with WORM guarantees:

| Mechanism | Scope | Purpose |
|---|---|---|
| **Bucket Lock retention policy** | bucket-level | Floor — minimum guaranteed retention for every object. We set this to **365 days** (matches Archive tier minimum). |
| **Object Lifecycle Delete rules** | per-prefix age match | Upper bound — deletes objects when their retention window ends (7 yr Tyr, 10 yr Eir, 1 yr Heimdall, etc.). |
| **Object Hold** (event-based or temporary) | per-object | Override — locks specific objects (e.g., under active litigation) past the lifecycle delete date. Manual op. |

Bucket Lock retention can **only be increased**, never decreased, once locked. We deliberately keep it at 365 days (not 7-10 yr) so that:
- We retain the option to early-delete a customer's data on contract termination after their data's individual lifecycle expires (vs being forced to hold for 10 yr).
- Per-prefix retention can be tuned via lifecycle rules without immutability constraints.
- A bug-introduced "wrong age" lifecycle rule can't accidentally pre-delete data inside the 365d floor.

Bucket settings table (applied at creation, some immutable after):

| Setting | Value | Immutable? |
|---|---|---|
| Location | `asia-southeast1` (Singapore — closest to TH customers, PDPA-compatible) | ✅ |
| Storage class (default) | Archive | per-object overridable |
| Versioning | Enabled | ✅ |
| Bucket Lock retention | 365 days | can INCREASE only |
| Public access prevention | Enforced | ✅ |
| Uniform bucket-level access | Enabled (no per-object ACLs) | ✅ |

To prove WORM on a specific PHI object (e.g., a discharge summary), apply a temporary Object Hold programmatically at upload, releasable only by a 4-eye process. Logged via Cloud Audit Logs → Tyr.

## Lifecycle rules

Applied as bucket-level JSON policy (managed via Terraform once built):

```json
{
  "lifecycle": {
    "rule": [
      { "action": {"type": "Delete"},
        "condition": {"age": 3650, "matchesPrefix": ["tenants/*/eir/"]} },
      { "action": {"type": "Delete"},
        "condition": {"age": 2555, "matchesPrefix": ["tenants/*/tyr/","tenants/*/bifrost/","tenants/*/mimir/","tenants/*/syn/"]} },
      { "action": {"type": "Delete"},
        "condition": {"age": 365, "matchesPrefix": ["tenants/*/heimdall/"]} },
      { "action": {"type": "Delete"},
        "condition": {"age": 1825, "matchesPrefix": ["_platform/"]} },
      { "action": {"type": "Delete"},
        "condition": {"daysSinceNoncurrentTime": 30, "isLive": false} }
    ]
  }
}
```

Days expressed in age (object creation → now). `daysSinceNoncurrentTime` cleans old versions 30 days after they're superseded.

## Cost model

### Storage — per customer per year

| Slice | Volume/yr (est.) | Storage cost/yr | Notes |
|---|---|---|---|
| Tyr (alerts+audit+fim) | ~20 GB | $0.29 | Google-managed encryption |
| Bifrost frames | ~5 GB | $0.07 | CMEK |
| Eir OpenEMR DB | ~30 GB | $0.43 | CMEK |
| Mimir (mariadb + qdrant + neo4j) | ~20 GB | $0.29 | CMEK on PHI tenants |
| Syn redaction audit | ~5 GB | $0.07 | CMEK |
| Heimdall call audit | ~5 GB | $0.07 | Google-managed |
| **Storage subtotal** | **~85 GB** | **$1.22/yr** | |

### KMS — per customer per year (CMEK only)

| Item | Calculation | Cost/yr |
|---|---|---|
| Active key versions (1 yr rotation, 7 yr retention → steady state ~7 versions) | 7 × $0.06/mo × 12 | $5.04/yr |
| KMS operations | ~912 ops/mo, under 10,000/mo free tier | $0 |
| **KMS subtotal** | | **$5.04/yr** |

### Operations + egress (rare)

| Item | Calculation | Cost/yr |
|---|---|---|
| GCS Class A ops (PUTs) | ~900/mo × $0.05/10K × 12 | $0.05/yr |
| Restore egress (1× full year @ 85 GB) | $0.05/GB × 85 | $4.25 per restore |

### Total per customer

| Scenario | Annual cost | Notes |
|---|---|---|
| **Standard** (Tyr + Bifrost + Heimdall, no CMEK / no PHI) | **$0.44/yr** | bare minimum, all Google-managed |
| **Pro** (Tier-1 + Tier-2 with CMEK for PHI/PII) | **~$6.36/yr** | recommended for asgard_medical / asgard_insurance |
| **Enterprise** (Pro + HSM CMEK + multi-region) | **~$60-80/yr** | HSM is ~20x software KMS cost |

### Platform (Megawiz internal, no per-tenant breakdown)

| Slice | Volume/yr | Cost/yr |
|---|---|---|
| Code snapshots + eval baselines + platform metrics | ~50 GB | $0.72/yr |
| Custom fine-tune model weights (when produced) | ~100 GB (per model) | $1.44/yr/model |

### Restore cost reference

- Restore 1 tenant's full year (~85 GB) = $4.25 + first-byte ms (Archive ≠ Glacier; reads are immediate, just expensive).
- Forensic Tyr-only retrieval for 1 day (~50 MB) = ~$0.003.
- Bifrost session frame restore for 1 patient (~5 MB) = ~$0.0003.

### Pricing → customer

| Plan | Customer price | Megawiz cost | Margin |
|---|---|---|---|
| Standard | $10/mo = $120/yr | $0.44/yr | 99.6% / $119/yr |
| Pro | $25/mo = $300/yr | $6.36/yr | 97.9% / $294/yr |
| Enterprise | $80/mo = $960/yr | ~$80/yr | 91.7% / $880/yr |

Pro tier is the default for asgard_medical / asgard_insurance customers (CMEK is non-negotiable for PHI).
