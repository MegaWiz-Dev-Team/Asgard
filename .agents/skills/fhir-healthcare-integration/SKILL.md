---
name: fhir-healthcare-integration
description: How to work with FHIR R4 resources, OpenEMR, and healthcare data in the Asgard platform (Eir gateway)
---

# FHIR R4 Healthcare Integration — Asgard Platform

## Overview
This skill covers FHIR R4 resource handling, OpenEMR integration via Eir Gateway, and healthcare data patterns used in Asgard.

## Eir Gateway Endpoints (Rust/Axum :8300)
| Endpoint | Method | Purpose |
|:--|:--|:--|
| `/v1/patients/search` | GET | Search patients by name/dob/identifier |
| `/v1/fhir/query` | POST | Natural language → FHIR search |
| `/v1/clinical/summary` | POST | Aggregate clinical data for patient |
| `/v1/webhooks/mimir` | POST | Knowledge sync from Mimir |
| `/a2a/tasks/send` | POST | A2A task delegation |
| `/*` | ANY | Reverse proxy → OpenEMR |

## FHIR R4 Key Resources
- **Patient** — Demographics, identifiers (MRN)
- **Condition** — Active diagnoses (ICD-10 codes)
- **MedicationRequest** — Current medications
- **AllergyIntolerance** — Drug/food allergies
- **Observation** — Lab results, vitals
- **Appointment** — Scheduled visits
- **DocumentReference** — CCD/CDA documents (`$docref`)
- **Encounter** — Visit records

## Calling Eir from Python
```python
import httpx

async def search_patient(name: str) -> dict:
    async with httpx.AsyncClient() as client:
        r = await client.get(
            "http://eir:8300/v1/patients/search",
            params={"name": name},
            headers={"X-Gateway": "asgard-service"}
        )
        return r.json()

async def clinical_summary(patient_id: str) -> dict:
    async with httpx.AsyncClient() as client:
        r = await client.post(
            "http://eir:8300/v1/clinical/summary",
            json={"patient_id": patient_id, "include": ["Patient", "Condition", "MedicationRequest"]}
        )
        return r.json()
```

## Calling Eir from Rust
```rust
let client = reqwest::Client::new();
let resp = client
    .get("http://eir:8300/v1/patients/search")
    .query(&[("name", &name)])
    .header("Accept", "application/fhir+json")
    .send()
    .await?;
```

## FHIR OpenEMR URL Patterns
```
/apis/default/fhir/Patient/{id}
/apis/default/fhir/Condition?patient={id}
/apis/default/fhir/MedicationRequest?patient={id}
/apis/default/fhir/Observation?patient={id}&category=vital-signs
/apis/default/fhir/DocumentReference/$docref?patient={id}
```

## US Core 8.0 Compliance
OpenEMR is certified for US Core IG v8.0.0 with:
- SMART on FHIR v2.2.0
- Bulk Data Export
- OAuth2 + OIDC

## Key Points
- Always use `Accept: application/fhir+json` header
- Eir adds `X-Gateway: eir-gateway` and `X-Agent-Request: bifrost` headers
- Moka cache (TTL: 60s) caches FHIR responses
- Governor rate limit: 100 RPS default
