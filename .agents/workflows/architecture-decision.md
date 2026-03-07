---
description: Make and document architectural decisions using ADR (Architecture Decision Records) format
---

# Architecture Decision Record (ADR)

## When to use
- Making a significant technical decision (e.g., choosing a database, framework, protocol)
- Evaluating build vs buy vs integrate options
- Changing an existing architectural pattern
- Any decision that would be hard to reverse

## Steps

1. **Identify the decision**:
   - What is the specific question we need to answer?
   - What are the constraints?
   - Who is affected?

2. **Research options** (minimum 3):
   - For each option, evaluate:
     - Pros and cons
     - Effort to implement
     - Maintenance burden
     - Community/ecosystem support
     - License compatibility (must be AGPL-3.0 compatible)

3. **Write the ADR** in `docs/technical/adr-NNN-title.md`:
   ```
   # ADR-NNN: [Title]

   ## Status
   Proposed | Accepted | Deprecated | Superseded by ADR-XXX

   ## Context
   What is the problem or question?

   ## Options Considered
   ### Option A: ...
   ### Option B: ...
   ### Option C: ...

   ## Decision
   We chose Option X because...

   ## Consequences
   - What changes as a result?
   - What do we gain?
   - What do we lose or accept as trade-offs?

   ## References
   - Links to relevant docs, issues, discussions
   ```

4. **Update related docs**:
   - Update gap-mapping.md if the decision resolves a gap
   - Update architecture.md if it changes system design
   - Update README.md if it affects the component table

## Existing ADRs (for reference)
- `docs/technical/yggdrasil-auth-selection.md` — Auth platform → Zitadel
- `docs/technical/adk-rust-evaluation.md` — ADK-Rust evaluation → Cherry-pick + ReactFlow

## Key principles
- Document WHY, not just WHAT
- Include rejected options — future readers need to know what was considered
- Keep ADRs immutable — supersede, don't edit old decisions
- Link ADRs to each other when related
