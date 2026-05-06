# 🇹🇭 ICD-10 Coding (with Thai Modification)

**Skill ID:** `icd10-coding`
**Owner:** Asgard / Hermodr
**Sprint:** 48 (Thai Clinical Coding Foundation)
**Status:** 📋 Spec only — not yet implemented
**License:** AGPL-3.0 (Asgard handler) + ICD-10-TM data per MoPH terms

---

## Purpose

Single-source-of-truth ICD-10 code lookup for all Eir Agents — supporting:

- **WHO ICD-10** (international, English) for cross-border interoperability
- **ICD-10-TM 2017** (Thai Modification) for Thai hospital encounters
- **DRG mapping** (สปสช. v6) for reimbursement-ready output
- **Bilingual semantic search** — Thai ↔ English ↔ code

---

## Why this exists

International cloud AI tools (GPT, Gemini) translate Thai → English → Thai
in a lossy way when handling ICD-10. Asgard handles ICD-10-TM **natively**:

- Thai medical terminology preserved end-to-end
- Local-first (no cross-border PHI flow)
- DRG mapping = billing-ready Eir output
- Multi-tenant audit trail per request

This is **Asgard's first explicitly Thailand-first feature**.

---

## API surface

### Tool name
`icd10_lookup`

### Signature
```rust
fn icd10_lookup(
    query: String,                    // Free-form: code, term (en/th), or phrase
    mode: LookupMode,                 // exact | prefix | semantic | auto
    locale: Locale,                   // en | th | both (default: both)
    include_drg: bool,                // include DRG group in response
    limit: usize,                     // default 10, max 50
) -> Result<Vec<IcdMatch>, IcdError>;

enum LookupMode {
    Exact,        // exact code or label match
    Prefix,       // code prefix or label substring
    Semantic,     // Qdrant BGE-M3 fuzzy/synonym (default for natural language)
    Auto,         // try exact → prefix → semantic in cascade
}

enum Locale { En, Th, Both }

struct IcdMatch {
    code: String,                     // e.g. "I63.9"
    en_label: String,                 // "Cerebral infarction, unspecified"
    th_label: Option<String>,         // "หลอดเลือดสมองตีบ ไม่ระบุรายละเอียด"
    chapter: String,                  // "IX. Diseases of the circulatory system"
    block: String,                    // "I60-I69 Cerebrovascular diseases"
    billable: bool,                   // can be primary diagnosis on a claim
    drg: Option<DrgInfo>,             // if include_drg = true
    relevance: f32,                   // 0.0-1.0
    source_version: String,           // "ICD-10-TM 2017"
}

struct DrgInfo {
    group_id: String,                 // e.g. "DRG-014"
    group_name_th: String,
    group_name_en: String,
    relative_weight: Option<f32>,     // for cost calculation
}
```

### Example calls

```
# Code lookup
icd10_lookup("I63.9", mode=Exact, locale=Both)
→ [{code: "I63.9", en: "Cerebral infarction...", th: "หลอดเลือดสมอง..."}]

# Thai natural-language
icd10_lookup("หลอดเลือดสมองตีบ", mode=Semantic, locale=Th)
→ [{code: "I63.9", relevance: 0.94, ...}, {code: "I63.5", relevance: 0.82, ...}]

# English natural-language with DRG
icd10_lookup("acute myocardial infarction", mode=Semantic, locale=En, include_drg=true)
→ [{code: "I21.0", drg: DrgInfo {group_id: "DRG-001", relative_weight: 1.85}, ...}]

# Code prefix browsing
icd10_lookup("I63", mode=Prefix, locale=Both, limit=20)
→ all I63.x codes with both en/th labels
```

---

## Storage layer

### MariaDB — `icd10_codes`

```sql
CREATE TABLE icd10_codes (
    code            VARCHAR(8) PRIMARY KEY,
    en_label        TEXT NOT NULL,
    th_label        TEXT,                          -- NULL for codes not yet TM-localized
    chapter         VARCHAR(255) NOT NULL,
    block           VARCHAR(255) NOT NULL,
    billable_flag   BOOLEAN DEFAULT TRUE,
    drg_id          VARCHAR(16),                   -- FK to drg_groups
    locale_metadata JSON,                          -- e.g. {"th_local_extension": true, "tropical_disease": false}
    source_version  VARCHAR(32) NOT NULL,          -- "ICD-10-TM 2017" | "WHO ICD-10 2019"
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_chapter (chapter),
    INDEX idx_block (block),
    INDEX idx_drg (drg_id),
    FULLTEXT idx_labels (en_label, th_label)
);
```

### MariaDB — `drg_groups`

```sql
CREATE TABLE drg_groups (
    group_id          VARCHAR(16) PRIMARY KEY,
    group_name_th     TEXT NOT NULL,
    group_name_en     TEXT NOT NULL,
    relative_weight   DECIMAL(8,4),
    average_los_days  INT,                         -- Length of stay
    sps_drg_version   VARCHAR(16) NOT NULL,        -- e.g. "v6"
    icd10_combo_rules JSON                         -- mapping logic
);
```

### Qdrant — collection `icd10-th`

```
collection: icd10-th
vector size: 1024 (BGE-M3)
points: ~107K (one per ICD-10-TM code)
payload: {
    code: "I63.9",
    th_label: "...",
    en_label: "...",
    chapter: "...",
    drg_id: "..."
}
```

---

## License & sourcing

| Source | License | Status |
|---|---|---|
| WHO ICD-10 (international) | Public domain post-1990 | ✅ |
| ICD-10-TM 2017 (กระทรวงสาธารณสุข) | Thai gov public document; formal license recommended | 🟡 B-48a — pending |
| สปสช. DRG v6 | Published; commercial review needed | 🟡 confirm |
| Asgard handler code | AGPL-3.0 (per Asgard open-core) | ✅ |

**B-48a action:** email Bureau of Health Information / กองยุทธศาสตร์และแผนงาน,
MoPH, with formal request for ICD-10-TM 2017 + DRG dataset license. 1-2 wk
turnaround expected.

---

## Eir Agent allowlist (Sprint 48 B-48i)

| Agent | Allowlisted? | Why |
|---|:---:|---|
| Internal Medicine | ✅ | Primary user — encounter dx coding |
| Surgery | ✅ | Procedure dx coding |
| Pediatrics | ✅ | Pediatric dx coding |
| OB-GYN | ✅ | Obstetric dx coding |
| Emergency | ✅ | ESI triage + initial dx |
| Psychiatry | ✅ | Mental health F-codes |
| MedTech | ✅ | Lab interpretation → suggested dx |
| Pharmacy | ✅ | Indication coding for Rx |
| Nursing | ✅ | Triage + handoff coding |
| Ophthalmology | ❌ | Out of v0 scope — Sprint 49+ |
| Orthopedics | ❌ | Out of v0 scope — Sprint 49+ |
| Anesthesia | ❌ | Procedure-specific, defer |
| ENT | ❌ | Sprint 49+ |
| Urology | ❌ | Sprint 49+ |
| Forensic | ❌ | Cause-of-death uses different vocabulary |
| Radiology | ❌ | Imaging procedure codes (CPT) — Sprint 51+ |
| PT | ❌ | Functional dx — defer |
| Dietitian | ❌ | Out of scope |
| Social Work | ❌ | Z-codes specifically — Sprint 50+ |

---

## Test set (B-48j)

50 anonymized Thai discharge summaries from MegaCare partner hospitals
(ethics-approved). Per case:

- Free-text discharge summary (Thai)
- Clinician-validated gold ICD-10-TM code(s)
- Expected DRG group

**Acceptance:** 45/50 (90%) gold codes are top-3 in `icd10_lookup` results.

---

## Failure modes to test

| Mode | Example | Expected behavior |
|---|---|---|
| Typo (Thai) | "หลอดเลีอดสมอง" (typo'd ลิ → ลี) | Semantic search recovers I63.x |
| Abbreviation | "MI" | Returns I21.x with relevance |
| Mixed lang | "stroke ตีบ" | Both lang search merged |
| Ambiguous | "hypertension" | Returns I10/I11/I15 ranked, requires disambig |
| Out of vocabulary | "covid-19" (post-2020) | Returns U07.1 (newer addition) — verify dataset version |
| Code that doesn't exist | "Z99.99" (not assigned) | Returns "not found" with suggestion |

---

## Future scope (out of Sprint 48)

- ❌ ICD-11 (still beta in Thailand 2026)
- ❌ SNOMED-CT integration
- ❌ LOINC (lab codes)
- ❌ CPT (US procedure codes)
- ❌ Auto-coding from free-text discharge (NLP extraction) — Sprint 52+
- ❌ Claims integration (สปสช. e-claim format) — Sprint 50+ ops integration

---

## Cross-references

- Sprint plan: [`Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md` Sprint 48](../../../Mimir/docs/03_implementation_plans/03_14_Local_LLM_Optimization_Sprints.md)
- Eir Agents: [`Eir/docs/Eir_Agents_Architecture.md`](../../../Eir/docs/Eir_Agents_Architecture.md)
- Hermodr architecture (TBD): when Hermodr repo reaches doc parity
- WHO ICD-10: https://www.who.int/standards/classifications/classification-of-diseases
- MoPH ICD-10-TM (Thai): TBD — public link after license confirmation
