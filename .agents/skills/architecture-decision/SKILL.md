---
name: architecture-decision
description: "Make and document architectural decisions using ADR (Architecture Decision Records) format. Structured trade-off analysis and option evaluation."
---

# Architecture Decision Record (ADR)

> "Document WHY, not just WHAT."

## Purpose

Make significant technical decisions through structured analysis and document them as ADRs for future reference. Prevents undocumented decisions and tribal knowledge.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/architecture.md` | Current system architecture |
| `docs/strategy/gap-mapping.md` | Pending gaps and decisions |

### Existing ADRs
| ADR | Decision |
|-----|----------|
| `docs/technical/yggdrasil-auth-selection.md` | Auth → Zitadel |
| `docs/technical/adk-rust-evaluation.md` | ADK-Rust → Cherry-pick, ReactFlow, A2A |

---

## Process

### 1️⃣ Frame the Decision
- What specific question needs to be answered?
- What are the constraints? (budget, team skills, timeline, license)
- Who is affected? Which components?

### 2️⃣ Research Options (minimum 3)
For each option evaluate:
- Technical fit (does it work with Rust/Python/Next.js stack?)
- Community health (stars, activity, maintainers)
- License compatibility (must work with AGPL-3.0)
- Effort to implement
- Long-term maintenance burden

### 3️⃣ Trade-off Analysis
Create a comparison matrix:
| Criterion | Weight | Option A | Option B | Option C |
|-----------|--------|----------|----------|----------|
| Performance | High | ✅ | ⚠️ | ✅ |
| Ease of use | Medium | ⚠️ | ✅ | ❌ |
| Community | High | ✅ | ✅ | ⚠️ |

### 4️⃣ Write the ADR
Save to `docs/technical/adr-NNN-title.md`:
```
# ADR-NNN: [Title]
## Status: Proposed | Accepted | Deprecated | Superseded
## Context
## Options Considered
## Decision
## Consequences
## References
```

### 5️⃣ Update Related Docs
- `docs/strategy/gap-mapping.md` if decision resolves a gap
- `docs/architecture.md` if it changes system design
- `README.md` if it affects component table

---

## Key Principles
- Include rejected options — future readers need context
- ADRs are immutable — supersede, don't edit
- Every significant decision deserves an ADR
- "Significant" = hard to reverse or affects multiple components

## When to Use
When choosing a database, framework, protocol, or any decision that would be hard to reverse.
