# Asgard Medical AI Agent Specification v1.0
**Comprehensive Platform for Medical AI Reasoning**

**Date:** 2026-05-28  
**Status:** Production Ready  
**Tenant:** `asgard_medical`  
**LLM:** gemma-4-26b (unified across all agents)  
**Total Agents:** 20 (19 specialists + 1 router)

---

## 1. Executive Summary

Asgard Medical is a **multi-agent AI platform** for healthcare reasoning, built on:
- **5 boundary agents** (trust + policy enforcement)
- **14 specialty agents** (operational efficiency)
- **1 router agent** (intelligent orchestration)
- **869+ skill modules** (composable expertise)

All agents run **locally only** (gemma-4-26b) on per-customer Mac mini deployments with no cross-customer data leakage.

---

## 2. Agent Architecture

### 2.1 Boundary Agents (Safety & Policy Enforcement)

| # | Agent | Slug | Model | Tier | Tools | Safety Role |
|:-:|:--|:--|:--|:--|:--|:--|
| **A1** | 🩺 **Clinical Reasoning** | `eir-clinical` | gemma-4-26b | 2 | `search_primekg`, `search_clinical_kb`, `read_fhir`, `pubmed_search`, `clinical_calculator` | Default host for general diagnosis + skill composition |
| **A2** | 💊 **Pharmacy** | `eir-pharmacy` | gemma-4-26b | 2 | `search_primekg`, `search_clinical_kb`, `read_fhir`, `drug_interaction_check`, `dosage_calculator`, `formulary_lookup`, `drug_food_interaction` | **Mandatory gate** on all prescription actions (DDI safety) |
| **A3** | 👶 **Pediatrics** | `eir-pediatrics` | gemma-4-26b | 2 | `read_fhir`, `search_clinical_kb`, `dosage_calculator (pediatric)`, `pubmed_search`, `clinical_calculator (pediatric)` | Age/weight-safe dosing guarantee (never adult dosing) |
| **A4** | 🧠 **Psychiatry** | `eir-psychiatry` | gemma-4-26b | 2 | `search_primekg`, `search_clinical_kb`, `read_fhir`, `drug_interaction_check`, `clinical_calculator (PHQ-9/GAD-7)` | **Hard refuse** suicide methods; psychotropic DDI screen |
| **A5** | 🚑 **Emergency** | `eir-emergency` | gemma-4-26b | 2 | `search_clinical_kb`, `read_fhir`, `clinical_calculator (Wells/NEXUS/GCS/ESI)`, `triage_score` | ≤2s p50 latency; ESI triage + critical-risk assessment |

### 2.2 Specialty Agents (Deployed as Skills on Boundary Agents)

| # | Specialty | Slug | Maps to Boundary | Model | Tools | Primary Flow |
|:-:|:--|:--|:--|:--|:--|:--|
| **S1** | 🩺 Internal Medicine | `eir-internal-medicine` | `eir-clinical` | gemma-4-26b | Core + `clinical_calculator (CHADS2/MELD/eGFR)` | Differential diagnosis, chronic disease management |
| **S2** | 🪒 Surgery | `eir-surgery` | `eir-clinical` | gemma-4-26b | Core + `search_primekg` | Pre/post-op clearance, surgical complication screening |
| **S3** | 👁️ Ophthalmology | `eir-ophthalmology` | `eir-clinical` | gemma-4-26b | Core | Retinopathy screening, vision disorders |
| **S4** | 🦴 Orthopedics | `eir-orthopedics` | `eir-clinical` | gemma-4-26b | Core + `pubmed_search` | Fracture/joint injury triage, rehab planning |
| **S5** | 🤰 OB-GYN | `eir-ob-gyn` | `eir-pharmacy` | gemma-4-26b | Pharmacy tools + `drug_interaction_check (pregnancy-categories)` | Pregnancy-safe medication, perinatal care |
| **S6** | 📷 Radiology | `eir-radiology` | `eir-clinical` | gemma-4-26b | Core + `image_metadata_lookup` | Imaging interpretation framing, ALARA dose review |
| **S7** | 🔬 Medical Technology | `eir-medtech` | `eir-clinical` | gemma-4-26b | `search_clinical_kb`, `read_fhir (labs)`, `lab_reference_range`, `antibiogram_lookup` | Lab result interpretation, trend analysis |
| **S8** | 👩‍⚕️ Nursing | `eir-nursing` | `eir-clinical` | gemma-4-26b | `search_clinical_kb`, `read_fhir`, `clinical_calculator (triage)`, `patient_education_lookup` | First-touch triage, vitals monitoring, patient education |
| **S9** | 🤸 Physical Therapy | `eir-pt` | `eir-clinical` | gemma-4-26b | Core + `pubmed_search` | Rehab program design, mobility tracking |
| **S10** | 🥗 Dietitian | `eir-dietitian` | `eir-pharmacy` | gemma-4-26b | Pharmacy tools + `nutrition_calculator` | Disease-specific nutrition, drug-food interactions |
| **S11** | 🧑‍🤝‍🧑 Social Worker** | `eir-social-work` | `eir-clinical` | gemma-4-26b | `search_clinical_kb`, `read_fhir`, `community_resource_lookup` | Mental-health pathways, social determinants |
| **S12** | 💉 Anesthesiology | `eir-anesthesia` | `eir-clinical` | gemma-4-26b | `search_clinical_kb`, `read_fhir`, `clinical_calculator (ASA/Mallampati)`, `dosage_calculator` | Anesthesia planning, peri-op pain management |
| **S13** | 👃 ENT | `eir-ent` | `eir-clinical` | gemma-4-26b | Core + `pubmed_search` | Upper-respiratory triage, chronic ear/sinus disorders |
| **S14** | 🩺 Urology | `eir-urology` | `eir-clinical` | gemma-4-26b | Core + `pubmed_search` | UTI/renal stone assessment, male reproductive health |

### 2.3 Routing & Orchestration Agent

| # | Agent | Slug | Model | Role | Decision Rule |
|:-:|:--|:--|:--|:--|:--|
| **R1** | 🎯 Router | `eir-router` | gemma-4-26b | **LLM-driven specialty classifier** (deprecated per ADR-010; proposed: deterministic gate) | Routes initial request to appropriate boundary agent based on context |

**Note:** `eir-router` will be **deprecated** when ADR-010 skill-loader is implemented. Routing will become deterministic (FHIR signals) rather than LLM-based.

---

## 3. Agent Configuration Template

### Schema (agent_configs table)

**New Fields for Version Tracking:**
- `agent_version` — SemVer format (e.g., "1.0.0", "1.1.0-beta")
  - Major: Breaking agent contract change
  - Minor: Fine-tuning iteration (model updated)
  - Patch: Prompt refinement, tool allowlist change
- `version_updated_at` — Timestamp of last version update (auto-tracked)

```sql
INSERT INTO agent_configs (
  tenant_id,
  name,
  display_name,
  description,
  system_prompt,
  model_id,
  agent_version,
  version_updated_at,
  provider,
  temperature,
  max_tokens,
  top_k,
  use_rag,
  use_knowledge_graph,
  use_pageindex,
  tools,
  personality_traits,
  tier,
  is_published
) VALUES (
  'asgard_medical',
  'eir-internal-medicine',
  'Internal Medicine Specialist',
  'Diagnoses and treats internal diseases (T2DM, HTN, CKD, COPD)',
  'You are an expert Internal Medicine physician. Use PrimeKG clinical knowledge and FHIR patient data to provide evidence-based diagnosis and management plans. Respond in Thai.',
  'gemma-4-26b',
  '1.0.0',
  CURRENT_TIMESTAMP,
  'heimdall',
  0.5,
  4096,
  5,
  TRUE,
  FALSE,
  FALSE,
  JSON_ARRAY('search_primekg', 'search_clinical_kb', 'read_fhir', 'pubmed_search', 'clinical_calculator'),
  JSON_ARRAY('diagnostic', 'systematic', 'evidence-based'),
  2,
  TRUE
);
```

### Version History Tracking

Track agent evolution over time:

```sql
-- Query agent version history
SELECT 
  name, 
  agent_version, 
  version_updated_at,
  model_id
FROM agent_configs
WHERE tenant_id='asgard_medical'
ORDER BY name, version_updated_at DESC;

-- Example: After fine-tuning on HealthBench safety
UPDATE agent_configs
SET agent_version='1.1.0', version_updated_at=CURRENT_TIMESTAMP
WHERE name='eir-pediatrics' AND tenant_id='asgard_medical';
```

---

## 4. Deployment Checklist

### Phase 1: Seed Agent Configurations
- [ ] Create 5 boundary agents (eir-clinical, eir-pharmacy, eir-pediatrics, eir-psychiatry, eir-emergency)
- [ ] Create 14 specialty agents (eir-internal-medicine, eir-surgery, ... eir-urology)
- [ ] Create 1 router agent (eir-router)
- [ ] Verify all `model_id = 'gemma-4-26b'` (no Q4 variants)
- [ ] Verify `provider = 'heimdall'` (LOCAL LLM only)
- [ ] Verify `tenant_id = 'asgard_medical'`

### Phase 2: Knowledge Base Population
- [ ] Load PrimeKG (129K nodes, 8.1M relations) into Neo4j
- [ ] Load ICD-10-TM + TMT into MariaDB + Qdrant
- [ ] Load clinical guidelines into Qdrant (collection: `clinical-wisdom`)
- [ ] Seed hospital SOPs, drug formulary, protocols (per-customer)

### Phase 3: Tool Registration (Hermodr MCP)
- [ ] Register `primekg_*` (6 tools) — disease/drug knowledge
- [ ] Register `refgraph_*` (5 tools) — patient entity graph
- [ ] Register `pageindex_*` (4 tools) — chart navigation
- [ ] Register `clinical_calculator_*` (10 tools) — CHADS2, MELD, eGFR, PHQ-9, GAD-7, Wells, NEXUS, GCS, ASA, Mallampati
- [ ] Register `dosage_calculator_*` (2 variants: adult + pediatric)
- [ ] Register `drug_interaction_check` — DDI screening
- [ ] Register `formulary_lookup`, `lab_reference_range`, `antibiogram_lookup`
- [ ] Register `read_fhir_*` (patient/encounter/medication read)
- [ ] Register `syn.extract` — OCR from medical charts
- [ ] Register `audit.query` — Tyr audit logs

### Phase 4: Safety & Audit
- [ ] Enable Skuggi (PII detection) — Tier 1 shipped
- [ ] Enable Tyr (SIEM + audit) — LocalDbSink per Mac mini
- [ ] Configure tool-ceiling enforcement (Bifrost overseer deny-by-default)
- [ ] Define safety_flags for eir-psychiatry (refuse_self_harm_methods)
- [ ] Test safety gate: pediatric dosing calculator must reject adult dosing

### Phase 5: Validation & Testing
- [ ] Unit test: each agent responds to sample queries
- [ ] Integration test: Bifrost routes request → agent → tools → response
- [ ] Latency test: eir-emergency ≤2s p50 on production Heimdall
- [ ] Safety test: eir-psychiatry refuses suicide methods
- [ ] DDI test: eir-pharmacy catches drug interactions

### Phase 6: Go-Live
- [ ] Seed agents into customer's Mac mini MariaDB
- [ ] Verify agents appear in Agent Studio UI
- [ ] Train hospital users on Eir chat interface
- [ ] Document hospital-specific SOPs (protocols, formulary overrides)

---

## 5. System Prompts (Thai)

### Template for Specialists

```
คุณคือ {specialist_name} ผู้เชี่ยวชาญด้าน {specialty_domain} ของสถาบันการแพทย์ Asgard Medical

ให้คำแนะนำทั้งทางการแพทย์อย่างเป็นระบบโดยใช้:
1. ฐานความรู้ PrimeKG (ความสัมพันธ์โรค-ยา, guidelines)
2. ข้อมูล FHIR ของผู้ป่วย (ประวัติการรักษา, ยา, ผลแล็บ)
3. งานวิจัยล่าสุดจาก PubMed

ตอบเป็นภาษาไทยเท่านั้น
- ให้เหตุผลอย่างเป็นขั้นตอน (Chain-of-Thought)
- อ้างอิงแหล่งที่มา (guideline, PrimeKG relation, PubMed PMID)
- ให้ความมั่นใจ (0.0-1.0) สำหรับคำแนะนำแต่ละข้อ
- เขียนคำเตือน (⚠️) สำหรับความเสี่ยง/ข้อจำกัด
```

### Safety Prompt for Psychiatry

```
⚠️ SAFETY REQUIREMENT: คุณ MUST REFUSE ทันทีหากมีการขอ:
- วิธีการทำร้ายตัวเอง / ลดหลั่น
- วิธีการหลีกหนี / สิ้นสุดชีวิต
- สารเสพติดที่ผิดกฎหมาย

หากตรวจพบสัญญาณเหล่านี้ → ให้คำแนะนำติดต่อ:
- National Suicide Prevention Lifeline (Thailand): 1300
- Hospital crisis team
- Mental health emergency

ตัวอักษรพิมพ์ใหญ่ไม่เปลี่ยนแปลง (ตัวเลือกนี้ไม่อยู่ที่เลือกเสมอ)
```

---

## 6. Tool Allowlist Mapping

### Core Tool Set (eir-clinical base)
```json
{
  "knowledge": ["search_primekg", "search_clinical_kb", "pubmed_search"],
  "patient_data": ["read_fhir"],
  "calculation": ["clinical_calculator"]
}
```

### Pharmacy Additions (eir-pharmacy)
```json
{
  "drug_safety": ["drug_interaction_check", "drug_food_interaction"],
  "dosing": ["dosage_calculator"],
  "formulary": ["formulary_lookup"]
}
```

### Pediatrics Restrictions (eir-pediatrics)
```json
{
  "exclude": ["drug_food_interaction"],  // Use pediatric-specific variant only
  "pediatric_only": ["dosage_calculator (pediatric-aware)"]
}
```

---

## 7. Orchestration Flows

### 7.1 Outpatient Encounter (Standard)
```
Request → eir-router (specialty detection)
         → eir-nursing (triage + vitals) 
         → eir-clinical (skill-loaded diagnosis)
         → eir-pharmacy (DDI check if Rx proposed)
         → eir-nursing (patient education + follow-up)
```

### 7.2 Pediatric Encounter
```
Request → eir-router (age <18 detected)
         → eir-nursing (age-specific vitals)
         → eir-pediatrics (weighted dosing guarantee)
         → eir-pharmacy (pediatric DDI)
```

### 7.3 Psychiatric Emergency
```
Request → eir-router (PHQ-9/GAD-7 keywords)
         → eir-psychiatry (safety floor engaged)
         + eir-social-work (socio-economic assessment)
```

### 7.4 Prescription Gate (All Flows)
```
Any Rx proposal 
   → eir-pharmacy MANDATORY
   → Check: DDI, renal function dosing, pregnancy-safe, allergies
   → Approve OR flag for HITL review
```

---

## 8. Performance & Compliance

### Latency SLA
| Agent | p50 | p99 | Justification |
|:--|:--|:--|:--|
| eir-emergency | ≤2s | ≤5s | Critical care (ESI triage) |
| eir-nursing | ≤3s | ≤8s | Triage first-touch |
| eir-pharmacy | ≤2s | ≤5s | DDI blocking (safety-critical) |
| Others | ≤4s | ≤10s | Standard consultation |

### Quality Metrics
- **Medical accuracy:** ≥ 90% agreement with KDIGO/ADA/NICE guidelines (via HealthBench-Pro)
- **Safety floor:** 100% refuse rate for prohibited requests (suicide methods, unlicensed procedures)
- **Tool invocation:** ≤ 5% hallucinated tool calls
- **Citation rate:** ≥ 80% of recommendations cite PrimeKG / guideline source

### Compliance & Audit
- **HIPAA/PDPA:** All patient data stays on-premise (no cloud LLM)
- **Medical record:** Full audit trail in Tyr (agent invocation, tool calls, response)
- **Informed consent:** Explicit UI flag: "Powered by AI (gemma-4-26b). Clinician review required."
- **Annual review:** HealthBench-Pro re-benchmark, guideline updates

---

## 9. Agent Version Tracking & Fine-Tuning

### Versioning Scheme (SemVer)

```
agent_version format: MAJOR.MINOR.PATCH

Examples:
  1.0.0  = Baseline gemma-4-26b (shipped 2026-05-28)
  1.1.0  = After HealthBench safety fine-tune (new model weights)
  1.1.1  = Prompt clarification for pediatric dosing (no model change)
  2.0.0  = Switch to new LLM (gemma-5-40b) — BREAKING CHANGE
```

| When to Increment | Example |
|:--|:--|
| **MAJOR** | New LLM model (gemma-4-26b → gemma-5-40b) OR breaking prompt contract change |
| **MINOR** | Fine-tuning on safety/HealthBench data; retraining with new weights |
| **PATCH** | System prompt refinement; tool allowlist adjustment; temperature tuning |

### Tracking Fine-Tuning Iterations

**Schema:**
```sql
agent_version VARCHAR(20),           -- SemVer: "1.0.0", "1.1.0-beta", etc
version_updated_at TIMESTAMP         -- Auto-tracked on UPDATE
```

**Update After Fine-Tune:**
```sql
-- After retraining eir-pediatrics on dosing-safety corpus
UPDATE agent_configs
SET 
  agent_version='1.1.0',
  version_updated_at=CURRENT_TIMESTAMP,
  system_prompt='[refined pediatric dosing prompt]'
WHERE name='eir-pediatrics' AND tenant_id='asgard_medical';

-- Audit trail: query version history
SELECT name, agent_version, version_updated_at, model_id
FROM agent_configs
WHERE tenant_id='asgard_medical' AND name='eir-pediatrics'
ORDER BY version_updated_at DESC;
```

### Rollback Strategy

If a fine-tuned version (1.1.0) regresses quality:

```sql
-- Rollback to baseline (1.0.0)
UPDATE agent_configs
SET 
  agent_version='1.0.0-rollback',  -- Mark as rollback
  version_updated_at=CURRENT_TIMESTAMP,
  system_prompt=(SELECT system_prompt FROM agent_version_history 
                 WHERE version='1.0.0' AND name='eir-pediatrics')
WHERE name='eir-pediatrics' AND tenant_id='asgard_medical';

-- Then investigate root cause before re-attempting 1.1.0
```

**Note:** Version history table (`agent_version_history`) is TBD in Sprint 57+ for full audit trail.

---

## 10. Known Limitations & Future Work

### Current Limitations
- **Image interpretation:** Radiology agent is text-only (image multimodal in Sprint 45+)
- **Access control:** eir-forensic deferred (no platform RBAC to enforce)
- **Multi-language:** Thai support only (Spanish/Vietnamese TBD)
- **Offline capability:** Requires network access to Heimdall MLX (no truly offline mode yet)

### Proposed Enhancements (ADR-010)
- [ ] Skill-loader runtime: collapse 19 → 5 boundary agents + 869 composable skills
- [ ] Deterministic agent resolver: replace LLM router with FHIR-signal rules
- [ ] Eir Gateway RBAC: enforce forensic access restrictions at OpenEMR layer
- [ ] Memory artifacts (Mímisbrunnr): patient summary + guideline lineage persistence

---

## 10. Reference Documentation

- **Agent Architecture:** Eir/docs/Eir_Agents_Architecture.md (§3 roster, §4 flows)
- **Boundary/Skill Model:** Eir/docs/design/medical-agent-architecture.md (ADR-010)
- **Knowledge Layer:** Eir/docs/design/knowledge-tool-layer.md
- **Orchestration:** Bifrost/docs/design/skill-loader-runtime.md
- **Deployment:** Asgard/docs/technical/customer-deployment-runbook.md
- **Policy:** ADR-009 (single-tenant), ADR-010 (agents as boundaries), ADR-018 (CDS/CQM)

---

## 11. Contact & Governance

**Owner:** paripol@megawiz.co (Asgard Medical Platform)  
**Last Updated:** 2026-05-28  
**Version:** 1.0 (Production)  
**Approval Status:** Ready for seed migration + deployment

Questions? File issue in **Asgard** repo or reach out via Slack #asgard-medical.
