# ADR-010: Medical Agents as Boundaries, Skills as Expertise

**Status:** Proposed
**Date:** 2026-05-22
**Deciders:** paripol@megawiz.co
**Scope:** Eir medical agents (Bifrost orchestration, Mimir `agent_configs` + skill
registry, MedOpenClaw skills, Hermodr tools). Does not change the deployment
model (see [ADR-009](ADR-009-single-tenant-mac-mini-deployment.md)) or the
LOCAL-LLM-only rule.
**Supersedes:** the "one cloned agent per medical specialty (19 → 28)" stance in
`Eir/docs/Eir_Agents_Architecture.md` §3/§4.5 and the agent-per-specialty
assumption in `Asgard/docs/roadmap/MultiAgent_Architecture_Plan.md`.

## Context

The Eir design grew a roster of **19 specialty agents** (13 medical specialists +
6 allied health), each a clone of a base Eir agent + a specialty preamble +
a tool allowlist, selected at request time by an LLM **specialty router**
(`eir-router`). A 28-specialty expansion was planned.

Three facts from our own implementation undercut that direction:

1. **Persona-routing gave ~0pp lift.** The Sprint 38f A/B test (router vs
   monolithic) measured **Δ = +0.0pp HBp** on the general question mix; ROI
   appeared only on specialty-tagged subsets. The 28-specialty expansion was
   already aborted on this evidence.
2. **Most agents are tool-identical.** ~13 of the 19 carry the *same* tool
   allowlist (`search_primekg, search_clinical_kb, read_fhir, pubmed_search`)
   and differ only in preamble — they are skills wearing agent costumes, each
   still paying ~1,500–1,750 prompt tokens and a clone to maintain.
3. **Routing costs latency and broke a policy.** The LLM router adds
   ~150–400ms/request, and the Sprint 38 PoC ran sleep/ENT/peds on **cloud
   Gemini**, violating the Eir local-only rule.

Meanwhile we already hold **869 MedOpenClaw skills** (cataloged + embedded,
B-49b) with no runtime that loads them — a parallel investment going unused.
869 specialties cannot be 869 `agent_configs` rows behind an 869-class
classifier; they *can* be retrieved skills.

## Decision

**An Agent is a trust & policy boundary — few, stable, enforceable. A Skill is
an expertise module — many, composable, retrieved at request time. A medical
specialty maps to a *skill* by default, and to an *agent* only when it needs a
distinct enforceable boundary.**

**Decision rule (per specialty):**

> Does this specialization change *what the agent may touch / which model / who
> may access / what it must refuse*?
> **Yes → Agent boundary. No → Skill.**

Concretely:

- **5 boundary agents** for `asgard_medical` replace the 19-agent roster:
  `eir-clinical` (general, default host), `eir-pharmacy` (DDI/formulary +
  mandatory prescription gate), `eir-pediatrics` (safety: dosing), `eir-psychiatry`
  (safety floor), `eir-emergency` (latency class). Each justified by an *enforced*
  boundary, not a clinical label. **`eir-forensic` is deferred** — its only
  justification is access restriction, which ADR-009 (no platform RBAC) cannot
  enforce on-box; it returns once access control exists at the Eir Gateway layer.
- The other **~13 persona-only specialties become skills** on `eir-clinical`.
- **Skill selection is retrieval, not an LLM router** — cosine match over skill
  `description` embeddings (reuses the BGE-M3 + Qdrant infra behind
  `/knowledge/search`). The LLM `eir-router` is **deprecated**.
- **Agent selection becomes a deterministic rule gate** (not an LLM) — the
  safety-relevant subset of the old routing rules, evaluated on structured
  signals (FHIR age, order intent). This is now safety-critical (mis-routing a
  pediatric case is a safety failure) and must never silently downgrade. See
  `medical-agent-architecture.md` §4b.
- **Skills only NARROW, never EXPAND:** a skill may subset the host agent's tool
  ceiling, add safety constraints, and pin a *safer/local* model — it can never
  grant a tool the agent lacks, weaken a safety floor, or escalate to cloud.
- **Tool ceiling is enforced server-side** (deny-by-default at the
  overseer→Hermodr boundary, audited to Tyr) — closing today's warn-only gap.
- **LOCAL-LLM-only and single-tenant-per-box remain unchanged** (ADR-009).
  Collapsing the cloud-Gemini PoC agents into skills on a local host *fixes* the
  current policy violation.

## Alternatives Considered

### 1. Keep / expand per-specialty agents (rejected — was the prior plan)
19 → 28 cloned agents + LLM router.
**Why rejected:** 0pp measured lift on general mix; tool-identical clones are
maintenance burden + token bloat; router adds latency and a local-only
violation; does not scale to the 869-skill long tail.

### 2. One mega-agent + 869 soft skills, no boundary agents (rejected)
A single Eir agent dynamically loading any of 869 skills.
**Why rejected:** loses *enforceable* separation. We must be able to *guarantee*
a pediatric query cannot reach an adult-dosing tool, that psychiatry hard-refuses
self-harm methods, that forensic data is access-restricted. Soft prompt-level
skills cannot guarantee this; safety/compliance needs hard agent boundaries.

### 3. Layered: few boundary agents + many retrieved skills (accepted)
Combines enforceable boundaries with long-tail scalability and removes the
router. Matches the convergent industry pattern (boundary agents + composable
skills) and reuses the already-built skill catalog + embeddings.

## Consequences

**Positive:** less duplication; scales to the long tail; removes the ~150–400ms
router hop; fixes the local-only PoC violation; uses the dormant 869-skill
investment; enforceable safety boundaries.

**Negative / cost:** requires building a **skill-loader runtime** in the Bifrost
overseer (the one net-new component) + a skill registry + tool-ceiling
enforcement; requires migrating the 19-agent roster (collapse + port personas to
skills). A parity test must confirm ≥ current quality on the specialty-tagged HBp
subset before retiring the per-specialty agents.

## Implementation references

- `Eir/docs/design/medical-agent-architecture.md` — the full architecture (roster,
  skill schema, knowledge scoping, safety, migration).
- `Bifrost/docs/design/skill-loader-runtime.md` — the runtime that implements
  selection / composition / tool intersection.
- `Bifrost/docs/design/agent-memory-evolution.md` — shared context budgeting
  (progressive disclosure of skill bodies).

## Open questions

- Final boundary-agent roster (is `eir-nursing` a latency-class agent or a skill
  + latency hint?).
- Parity-test thresholds and skill-selection tuning (top_k, score floor, MMR).
- Skill versioning / curator approval (ties to the Mimir curator track).