# ADR-023: Open-Core IP Boundary (which components are open, copyleft, or closed)

**Status:** Accepted
**Date:** 2026-05-30
**Deciders:** paripol@megawiz.co
**Scope:** Platform-wide (all current and future Asgard components)
**Related:** [OPEN_CORE_POLICY.md](../../OPEN_CORE_POLICY.md), [COMMERCIAL.md](../../COMMERCIAL.md), ADR-007 (Skuggi), ADR-009 (single-tenant deployment)

## Context

The question "should we stop open-sourcing Asgard?" came up. Investigation showed the open/closed
split had been evolving **ad hoc**: security scanners (Huginn/Muninn) and identity (Yggdrasil) went
private for commercial/security reasons, several crates were published, and the medical platform
stayed public — but there was **no written rule**. Without one, each new component risks
inconsistent classification, which erodes both the moat and community trust.

Actual GitHub visibility at decision time:

- **Public:** Asgard, Bifrost, Heimdall, Mimir, Eir, refgraph, Odin
- **Private:** Syn, Tyr, Huginn, Muninn, Yggdrasil

A proposal to *additionally* close Bifrost + refgraph and extract Skuggi was considered. But
Bifrost and refgraph are already public, and refgraph's core is **already published to crates.io**
(cannot be unpublished). Closing them would be high-cost and low-reversibility for little gain,
and would contradict a boundary the team had effectively already chosen.

## Decision

Adopt a **three-tier open-core model** with one governing principle:

> **Open the platform; close the defenses and the tuned domain IP. AGPL is the moat for the open tier.**

- **Tier C — Private/Commercial:** Syn, Tyr, Huginn, Muninn, Yggdrasil, and **Skuggi** (security,
  identity, tuned-defense IP).
- **Tier B — AGPL-3.0 public:** Bifrost, Heimdall, Mimir, Eir, refgraph, Odin (the medical/insurance
  platform — public for audit/trust; AGPL prevents closed resale).
- **Tier A — Permissive public:** `syn-client-types`, FHIR types, protocol/SDK glue (commodity
  interfaces, no moat).

New components default to **Tier B**, moving to Tier C only if publishing weakens security/identity
or hands over tuned IP, and to Tier A only if pure interface. Tuned **data** (agent configs, detector
rulesets, weights) ships privately/per-box even when its engine is Tier B. Full classification table
and the rule live in [OPEN_CORE_POLICY.md](../../OPEN_CORE_POLICY.md).

**Do not** blanket-close the platform: it would forfeit the moat AGPL already provides and the
clinician/regulator trust that open auditability buys, in exchange for IP protection AGPL + per-box
private data already deliver.

### Skuggi (the one open item)

Skuggi belongs in Tier C, but its `skuggi-core` crate (~311 LOC of Tier-1 PII regex + scoring)
currently lives in public Mimir and is consumed by public Heimdall via path dependency. Making it a
private code dependency would break both public builds. Therefore the extraction is **deferred and
must split engine (public) from rules (private)** — see the migration note in the policy doc. The
currently exposed surface is standard PII regexes (low IP risk), so this is tracked, not rushed.

## Alternatives Considered

1. **Blanket close-source everything (rejected).** Forfeits AGPL's free moat and the trust/audit
   value of an open medical platform; irreversible damage to brand and partner relations.
2. **Stay fully MIT/Apache open (rejected).** Removes copyleft protection — a competitor could take
   the platform closed and resell it. Contradicts existing licensing memory.
3. **Execute the earlier "also close Bifrost + refgraph" proposal (rejected).** Bifrost/refgraph are
   already public and refgraph is published to crates.io (un-publish impossible); high cost, low
   reversibility, minimal added protection over AGPL.
4. **Three-tier open-core, extract Skuggi only (accepted).** Codifies the boundary the team had
   effectively chosen, adds the one missing closure (Skuggi) in a non-build-breaking way.

## Consequences

- A mechanical rule now governs new-component classification; reduces drift.
- `COMMERCIAL.md` must be reconciled — it links some Tier-C repos (e.g. Yggdrasil) as if public.
- Skuggi extraction becomes a tracked engineering task gated on the proprietary detectors (W2–W4)
  existing, implemented as engine/rules split.
- No public repo is flipped private as a result of this ADR (avoids breaking links/forks/crates).
