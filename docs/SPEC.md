# Asgard — Platform Specification

> **Spec status:** Living · **Version:** 0.1 · **Last updated:** 2026-05-30
> **Scope:** the Asgard umbrella platform (this repo). For component-level specs see
> [asgard-underwriter](../../asgard-underwriter/docs/SPEC.md) ·
> [asgard-iris](../../asgard-iris/docs/SPEC.md) ·
> [mimir-fhir](../../Mimir/ro-ai-bridge/mimir-fhir/SPEC.md)

This document is the shared mental model for the platform. It is intentionally
high-level; authoritative detail lives in `docs/architecture/` and `docs/decisions/`
(ADRs). Where this doc and an ADR disagree, **the ADR wins** — open a PR to fix this doc.

---

## 1. Identity

| | |
|---|---|
| **What** | Self-hosted, on-premises AI agent platform (agentic RAG + computer-use + medical/insurance AI specialization) |
| **Tagline** | "AI services that run entirely on local hardware — zero cloud dependency" (README) |
| **Repo role** | Umbrella: K3s/compose deployment orchestration, cross-cutting docs, ADRs, strategy, `Odin` supervisor |
| **License** | Open-core: **AGPL-3.0** (community) + proprietary **Commercial** edition. Never relicense Asgard's own code to MIT/Apache. |

## 2. Purpose & boundaries

**Asgard IS:**
- An **agent orchestration + knowledge platform** (ReAct, MCP tools, Skills, memory, RAG)
- **Domain-specialized** for medical and insurance workflows
- **On-prem, single-tenant per hardware appliance** (one Mac mini / K3s cluster per customer)

**Asgard IS NOT:**
- An EHR — it is a **FHIR-native data plane + modular clinic tools that run *inside* the hospital's existing EHR** (HOSxP / Trakcare / OpenEMR) via SMART-on-FHIR + MCP (ADR-012).
- A cloud SaaS — no multi-tenant cloud; provisioning is per-box.

## 3. Position in the stack (layers)

```
User           Dashboard (Next.js) · Chat UI · REST
Edge & Auth    Eir Gateway · Yggdrasil (Zitadel OIDC + RS256 JWT)
Agent runtime  Bifrost (ReAct + MCP client + orchestration)
Tools          Heimdall (LLM) · Mimir (RAG/FHIR) · Syn (OCR) · Fenrir (computer-use)
               · Hermodr (MCP bridge) · Ratatoskr (browser)
Data & memory  MariaDB · Qdrant · Neo4j · Redis · mimir-well (memory artifacts)
Inference      MLX (Apple Silicon) · vLLM (NVIDIA) · fastembed (ONNX)
Ops & sec      Odin · Vardr · Tyr (SIEM) · Huginn/Muninn · Fafnir (Vault) · heimdall-trace
```

Two integration protocols: **MCP** for tool calls (sync), **A2A** for agent-to-agent task delegation (async).

## 4. Component inventory (Norse families)

> Naming rule (ADR/feedback): **do not add new top-level Norse names** — extend an existing
> family as `<parent>-<submodule>` with a plain-English submodule name.

| Component | Role | Stack | Status |
|---|---|---|---|
| **Bifrost** (+ `-agent`, `-jobs`) | Multi-agent orchestrator | Rust (Axum, rig.rs) | ✅ |
| **Heimdall** (+ `-trace`, `-horn`) | LLM gateway (multi-backend) | Rust + MLX + fastembed | ✅ |
| **Skuggi** | PII/DLP guardrail (in-process in Heimdall) | Rust | 🚧 W1 shipped |
| **Mimir** (+ `-well`, `-curator`) | RAG pipeline, FHIR data plane, dashboard | Rust + Next.js + MariaDB + Qdrant + Neo4j | ✅ |
| **Syn** (+ `-eval-ingest`, `-dicom`) | Document OCR + PII redaction | Rust + Python (MLX VLM) | ✅ |
| **Eir** | API gateway + OpenEMR + FHIR R4 surface | Rust + PHP | ✅ |
| **Yggdrasil** (+ `-mail`) | Auth (Zitadel OIDC + JWT) | Zitadel (Go) + Python | ✅ |
| **Fenrir** | Computer-use agent | Rust + Python | ✅ |
| **Hermodr** | Universal MCP sidecar (REST→JSON-RPC) | Rust | ✅ |
| **Ratatoskr** | Headless browser REST | Rust | ✅ |
| **Tyr** (+ `-archive`) | SIEM/XDR (Wazuh) + ISO-27001 cloud archive | Wazuh + Rust | ✅ |
| **Huginn / Muninn** | Security scanner + auto-fixer | Rust | ✅ (private repos) |
| **Odin / Vardr / Fafnir** | Supervisor / monitoring / Vault | Rust + HCL | ✅ |
| **Forseti / Mjolnir** | E2E testing / load testing | Python / Rust | ✅ |
| **Saga / Bragi** | STT / TTS | (whisper.cpp / TBD) | 📋 planned |

> Insurance/medical **products** (Iris, Underwriter) are separate repos, not Norse infra components — see §6.

## 5. Deployment & tenancy

- **Hardware:** Mac mini M4 (16–64 GB) or Mac Studio; NVIDIA DGX for larger. Heimdall runs **native** (GPU), most else in **K3s/OrbStack**.
- **One box = one customer = one tenant.** "Multi-insurer" means *one* customer comparing competitor products, not org-sharing.
- **Named tenants** (technical id / display): `asgard_medical` ("Asgard Medical") · `asgard_insurance` ("Asgard Insurance") · `asgard_platform` (cross-cutting PII-free benchmark metrics) · `asgard_wellness` (planned).
- Eir agents on `asgard_medical` are **local-LLM only** (no cloud LLM, even for low-latency). `asgard_insurance` is gemma-local-by-default; cloud is **Skuggi-gated**.

## 6. Products built on the platform

| Product | Persona | What it does | Repo |
|---|---|---|---|
| **Iris** | Hospital billing/admin staff | Upload clinical docs → OCR/extract → generate NHSO XML + สปสช EDI claim files | `asgard-iris` |
| **Underwriter** | Insurance underwriter | Patient medical history → 12-agent specialist assessment → risk decision | `asgard-underwriter` |

Both consume platform services (Heimdall, Mimir, Syn). Both are **on the insurance/medical side** and target the `asgard_insurance` / hospital-claims domain.

## 7. Status (Q2 2026, ~Sprint 38)

Shipped: Heimdall ONNX+MLX, Bifrost ReAct+MCP, Mimir agentic RAG, Skuggi W1, S1 RefGraph retrieval (Hit Rate@3 93.3%), tyr-archive v1.
In flight: Mimir Well memory artifacts (S56), Syn OCR foundation, FHIR R5 data plane (mimir-fhir Sprint 2), Insurance launch (S52–54).

## 8. Key reference docs

ADR-009 (single-tenant Mac mini) · ADR-012 (no-EHR data plane) · ADR-013 (FHIR R5 canonical) · ADR-014 (Mimir owns Layer 1) · ADR-015/016 (Composition + Asgard profile family) · ADR-017 (R4↔R5 translation) · ADR-020 (43Files HOSxP adapter) · ADR-022 (SMART-on-FHIR). Full list in `docs/decisions/`.

## 9. Open alignment points

- **FHIR is the integration backbone but `mimir-fhir` is still datatypes-only** (v0.0.1). Iris/Underwriter FHIR work is gated on its Sprint 2+ (see mimir-fhir SPEC §"Status").
- ICD-10-TM code-system URI: ✅ standardized in `mimir_fhir::terminology::ICD10_TM` (2026-05-30) = `https://terminology.fhir.moph.go.th/CodeSystem/icd-10-tm`. Iris still to migrate from `http://hl7.org/fhir/sid/icd-10-tm`. Tracked in [SYSTEM_CONTEXT](./SYSTEM_CONTEXT.md) point #1.
