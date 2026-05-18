# ADR-009: Single-Tenant Per Mac Mini Deployment Model

**Status:** Accepted
**Date:** 2026-05-17
**Deciders:** paripol@megawiz.co
**Scope:** Platform-wide (affects Bifrost, Heimdall, Mimir, Underwriter, all future components)
**Supersedes:** any earlier assumption of SaaS multi-tenant architecture

## Context

Asgard had been planned and discussed in some earlier docs as a multi-tenant SaaS platform — with `tenant_id` as a runtime isolation primitive, per-tenant ACLs, RBAC, cross-tenant routing, etc.

The actual go-to-market model is different and needs to be documented explicitly so future architecture decisions don't drift back toward SaaS assumptions.

**Reality:**
- Each customer (hospital or insurance company) receives **one dedicated Mac mini** running Asgard on-premise
- The Mac mini sits in the customer's facility, behind their VPN/Tailscale
- No data leaves the box unless the customer explicitly configures it (e.g., cloud LLM fallback through Skuggi gate)
- The customer is the ONLY user-organization on that box

This is on-prem appliance distribution, not SaaS.

## Decision

**Asgard deploys as 1 Mac mini per customer.** Each box runs a single-org installation.

- Technical `tenant_id` is a deployment configuration constant, valued from a fixed enum: `asgard_medical` or `asgard_insurance`
- Display name follows dual-name convention (like Laminar/Sága): "Asgard Medical" / "Asgard Insurance" in UI, docs, marketing; snake_case in DB/JWT/config
- **No RBAC** — single org per box means no role separation between users at the platform layer
- **No multi-tenant routing** — request scoping happens at the box level (physical separation), not in code
- JWT (Yggdrasil) is for service-to-service auth (e.g., Cloud Run portal → on-prem Mac mini) and proof of box access, not for tenant extraction
- Per-component audit (Tyr) is local to the box

**The "multi-insurer" pattern within `asgard_insurance` is NOT multi-tenancy.** It means: ONE insurance company customer loads competing product catalogs (Prudential + ThaiLife + Thai Health) onto their own box for product comparison analysis. The `insurer_id` field identifies which insurer issued a product record, not which insurer is logged in.

## Alternatives Considered

### 1. SaaS multi-tenant (rejected, was the implicit prior plan)

- Single Asgard cluster, many customer orgs, RBAC + ACL isolation, cross-tenant search prevented by query-time filtering

**Why rejected:**
- Healthcare and insurance customers in Thailand strongly prefer on-prem (data sovereignty, PDPA comfort)
- Cross-org leak risk in SaaS is non-trivial to defend against to clinicians/CISOs
- Per-customer compute (LLM inference) is hardware-bound; can't time-share GPU across tenants efficiently for clinical-grade latency
- The Mac mini hardware story is already part of the Asgard pitch
- Implementation complexity of robust multi-tenant isolation is high; on-prem sidesteps that entirely

### 2. Multi-tenant in a single private cluster (one per customer) (rejected)

- Customer hosts a cluster, Asgard runs as multi-tenant inside it

**Why rejected:**
- Hospitals don't have the K8s ops capability for this
- Hardware appliance Mac mini is a simpler sales story
- The "multi-tenant" code complexity remains without solving any real problem

### 3. Hybrid — appliance + optional SaaS later (deferred, not rejected)

- Same model as #1 but with a future SaaS edition for smaller customers

**Status:** not addressed now. If a SaaS edition is ever pursued, ADR-009 will be revisited. Until then, all design assumes appliance.

## Consequences

### Positive

- **Zero cross-org leak risk by physical separation** — far stronger isolation than any code-level multi-tenant design
- **PDPA / HIPAA story is simple** — patient data never leaves the box
- **No RBAC implementation needed** — saves weeks of work and ongoing complexity
- **Simpler JWT** — proof of access, not tenant routing
- **Local-only audit** — Tyr instances run per-box, no central SIEM concern (until/unless customer-fleet management becomes a thing)
- **Predictable performance** — no noisy-neighbor effects; LLM/embedding/OCR resources dedicated to one org

### Negative

- **Operational overhead per customer** — every Mac mini is a separate install, separate update, separate backup story
- **Update rollout** — N customers = N rollouts; need good CI + runbook discipline
- **No cross-customer aggregate features** — can't show industry-wide benchmarks (could be added later via opt-in telemetry)
- **Sales motion** — appliance sales cycle is longer than SaaS signup

### Risks

- **Update drift across customer fleet** — different Mac minis running different Asgard versions. Mitigation: SemVer + customer-managed upgrade window, version-aware rollback runbook.
- **Customer mismanagement of their box** — patient data on physical hardware in clinic. Mitigation: encrypted disk, automated backups, audit-friendly logs, OS hardening checklist (see Tyr/Muninn workstreams).

## Implications for Active Workstreams

| Workstream | Implication |
|---|---|
| Asgard-Underwriter v3 | No RBAC code needed; JWT validates service access; `tenant_id` is a config constant; per-deployment DB |
| PrimeKG ingestion | Each box has its own PrimeKG copy in its own Mimir Neo4j + Qdrant; refresh propagates via update runbook |
| Skuggi | Local-first by default already aligns with this model |
| Tyr | Local box only; no cross-deployment SIEM in v1 |
| Mega Care portal bridge | Cloud Run portal → that customer's specific Mac mini via Tailscale; not a multi-tenant router |
| FHIR REST API (planned) | Single-tenant FHIR server per box |

## What This Does NOT Change

- `tenant_id` field still exists in DB rows and audit events — for query convenience, schema portability, and possible future evolution
- `tenant_id` ∈ {`asgard_medical`, `asgard_insurance`} stays as the controlled vocabulary
- Within-tenant fields (`hospital_id`, `insurer_id`, ...) exist for product/reference data identification, NOT user/org login routing

## Validation

This decision is validated when:

- [ ] No new code adds per-tenant ACL middleware, RBAC tables, or cross-tenant routing
- [ ] JWT validation logic remains "is this caller authorized to use this box" (not "which tenant is this caller")
- [ ] Underwriter v3 Phase A.3 (JWT/Yggdrasil) implements service-auth not tenant extraction
- [ ] Documentation across the codebase uses "1 box per customer" language consistently

## References

- [feedback_tenant_is_domain_not_org memory](memory)
- [asgard_insurance_tenant memory](memory)
- [s2_multi_insurer_architecture memory](memory) — explains the `insurer_id` field for product comparison
- [MegaCare hosting topology memory](memory) — Cloud Run portal + VPN Case B for box reach
