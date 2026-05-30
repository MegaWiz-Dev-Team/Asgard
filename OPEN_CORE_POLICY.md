# 🏰 Asgard Open-Core Policy

**Status:** Active
**Owner:** paripol@megawiz.co
**Last updated:** 2026-05-30
**Canonical source of truth** for which Asgard components are open, copyleft, or closed.
See also: [ADR-023](docs/decisions/ADR-023-open-core-ip-boundary.md), [COMMERCIAL.md](COMMERCIAL.md), [LICENSE](LICENSE).

---

## Why this document exists

Asgard's open/closed split had been happening **ad hoc** — security scanners (Huginn/Muninn)
were made private for one reason, crates were published for another. Without a written
boundary, each new component gets classified inconsistently, which erodes **both** the moat
*and* community trust over time.

This policy makes the boundary explicit and the rule for new components mechanical.

## The principle (one rule)

> **Open the platform, close the defenses and the tuned domain IP.**
>
> A component is **AGPL-public** by default. It moves to **private/commercial** only if it is
> (a) a *security/identity* control where exposing the implementation weakens the protection,
> or (b) *tuned domain IP* that a competitor could lift to skip months of work.
> Interface/protocol/client glue that helps integration but is not a moat is **permissive-open**.

The AGPL license *is* the moat for the open tier — copyleft already prevents a competitor from
taking the platform closed and reselling it as a hosted service. We do **not** need to close a
component just to protect it from SaaS competitors; AGPL does that for free. We close only when
AGPL is insufficient (the two cases above).

> ❗ Never relicense Asgard's own open code as MIT/Apache — that removes the copyleft moat.
> External dependencies keep their own upstream terms.

---

## The three tiers

### 🔒 Tier C — Private / Commercial (closed source)

Security, identity, and tuned-defense IP. Sold/licensed; not in public repos.

| Component | Repo | Why closed |
|-----------|------|------------|
| **Syn** | `MegaWiz-Dev-Team/Syn` (private) | OCR engine + tuned detectors; also carries internal real-data coupling |
| **Tyr** | `MegaWiz-Dev-Team/Tyr` (private) | SIEM / threat detection — exposing rules tells attackers how to evade |
| **Huginn** | `MegaWiz-Dev-Team/Huginn` (private) | Security scanner (cyber-security commercial split) |
| **Muninn** | `MegaWiz-Dev-Team/Muninn` (private) | Auto-fix / security remediation (commercial split) |
| **Yggdrasil** | `MegaWiz-Dev-Team/Yggdrasil` (private) | Identity / auth service — attack surface, keep implementation closed |
| **Skuggi** | _to be extracted → `MegaWiz-Dev-Team/Skuggi` (private)_ | PII guardrail — the tuned detector rules are a defense; exposing them tells an adversary exactly what slips through. **See migration note below.** |

### 🌐 Tier B — AGPL-3.0 (public, copyleft)

The medical/insurance platform. Public for auditability and clinician/regulator trust;
AGPL stops competitors from closing it.

| Component | Repo | Role |
|-----------|------|------|
| **Bifrost** | `MegaWiz-Dev-Team/Bifrost` (public) | Orchestrator |
| **Heimdall** | `MegaWiz-Dev-Team/Heimdall` (public) | LLM Gateway |
| **Mimir** | `MegaWiz-Dev-Team/Mimir` (public) | RAG + Agent Builder |
| **Eir** | `MegaWiz-Dev-Team/Eir` (public) | Clinical agent gateway |
| **refgraph** | `MegaWiz-Dev-Team/refgraph` (public) | Reference-graph engine |
| **Odin** | `MegaWiz-Dev-Team/Odin` (public) | (public utility) |

> **Agent configs are not in this tier — they are not code.** The 19 Eir specialty agents,
> tool allowlists, and medical reasoning preambles live as **rows in `agent_configs`** (DB),
> shipped per-box. The public Eir/Bifrost code can orchestrate agents but does not contain the
> tuned medical configuration. That data is effectively Tier C by storage, not by repo.

### 📦 Tier A — Permissive (public, integration glue)

Commodity interfaces that help partners/SIs integrate. Not a moat → permissive license OK.

| Artifact | Where | Note |
|----------|-------|------|
| **`syn-client-types`** | crates.io `v0.1.x` | OCR request/response DTOs; codenames already sanitized before publish |
| **FHIR types** | mimir-fhir crate | R5 canonical types; standards-based, no moat |
| **Protocol / SDK glue** | per-repo | client stubs, wire types |

---

## Rule for any NEW component

1. **Default = Tier B (AGPL).**
2. Move to **Tier C** only if it answers *yes* to: *"Does publishing the implementation make
   our security/identity weaker, or hand a competitor our tuned domain IP?"*
3. Move to **Tier A** only if it is pure interface/protocol with no moat value.
4. Record the classification in this table in the same PR that creates the component.
5. Tuned data (agent configs, detector rulesets, weights) is shipped per-box / privately even
   when the surrounding engine is Tier B.

---

## Current state vs target (gap log)

As of 2026-05-30, actual GitHub visibility matches this policy **except** Skuggi.

| Item | Target | Actual | Action |
|------|--------|--------|--------|
| Syn, Tyr, Huginn, Muninn, Yggdrasil | private | private | ✅ none |
| Bifrost, Heimdall, Mimir, Eir, refgraph, Odin | AGPL public | public | ✅ none |
| **Skuggi (`skuggi-core`)** | private | **public** (lives in Mimir + consumed by Heimdall) | ⏳ extract — see below |

### Skuggi extraction migration note

`skuggi-core` (the Tier-1 PII regex + scoring crate, ~311 LOC) currently lives at
`Mimir/ro-ai-bridge/skuggi-core` and is consumed via **path dependency by two public repos**:
Mimir (leak-detection) and Heimdall (`gateway/src/skuggi.rs` redaction glue).

⚠️ **Naively making `skuggi-core` a private code dependency breaks the public builds of both
Mimir and Heimdall** — they could no longer compile without private-repo access, which
contradicts the Tier-B "auditable, community-buildable" promise.

The extraction must therefore split **engine (public) from rules (private)**, not just move the
crate. Recommended pattern, to execute when the proprietary detectors (Skuggi W2–W4 / NER) land:

- Keep a public `skuggi-core` engine + a basic default ruleset so Tier-B repos build & run.
- Ship the **tuned detector ruleset + weights** as private data / a feature-gated private crate,
  loaded at runtime on commercial/on-prem builds.

Until then the exposed surface is standard PII regexes (Thai national-ID, phone, email), which
carries low IP risk. The migration is tracked here rather than rushed in a way that breaks
public builds.

➡️ **Detailed migration plan:** [docs/technical/skuggi-extraction-migration.md](docs/technical/skuggi-extraction-migration.md)
(engine stays public in `skuggi-core`; tuned rules ship as a private data file from a new private
`MegaWiz-Dev-Team/Skuggi` repo via `SKUGGI_RULES_PATH` — no public repo is flipped private).

---

## Maintenance

- This file is canonical. `COMMERCIAL.md` and any per-repo README must not contradict it.
- `COMMERCIAL.md` currently links some Tier-C repos (e.g. Yggdrasil) as if public — reconcile.
- Review on every new component and at each release.
