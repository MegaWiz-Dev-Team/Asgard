---
name: product-direction
description: "Define or refine product vision, strategic priorities, success metrics, and design principles for Asgard AI Platform."
---

# Product Direction & Vision

> "If everything is a priority, nothing is a priority."

## Purpose

Define a clear product vision and strategic priorities that guide all development decisions. Ensure every feature built creates differentiation vs competitors.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/strategy/platform-review.md` | Current strengths/gaps/roadmap |
| `docs/strategy/competitor-analysis.md` | Market positioning |
| `docs/strategy/gap-mapping.md` | What needs to be built |

---

## Process

### 1️⃣ Vision Definition
- **One-liner**: What Asgard is in one sentence
- **3-year narrative**: Where will Asgard be in 3 years?
- **Design principles**: 3-5 principles that guide every decision
- **Anti-goals**: What Asgard will NOT do (equally important)

### 2️⃣ Strategic Priorities
- List top 3-5 bets for the next 6 months
- For each priority:
  - Which gap from `gap-mapping.md` does it address?
  - How does it differentiate vs Dify/Open WebUI (from `competitor-analysis.md`)?
  - Effort estimate (S/M/L/XL)
  - Dependencies and blockers
- Rank by: `(Impact × Feasibility) / Effort`

### 3️⃣ Success Metrics
- **North Star Metric**: One metric that defines success (e.g., "Monthly Active Self-Hosted Deployments")
- **Leading indicators**: GitHub stars growth, Docker pulls, community PRs
- **Lagging indicators**: Enterprise leads, revenue, NPS

### 4️⃣ Output Document
Write to `docs/strategy/product-direction.md`:
```
# Asgard — Product Direction
## Vision Statement
## Design Principles
## Anti-Goals
## Strategic Priorities (Next 6 Months)
## Success Metrics & KPIs
## Key Decisions Log
```

---

## Validation Checklist
- [ ] Vision is stable (won't change quarterly)
- [ ] Each priority creates customer-visible differentiation
- [ ] Priorities are limited to 3-5 (not a wish list)
- [ ] Each priority ties to a real customer pain point
- [ ] Anti-goals prevent scope creep

## When to Use
At project kickoff, quarterly strategy review, after major market shifts, or before roadmap planning.
