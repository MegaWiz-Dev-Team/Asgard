---
name: roadmap-planning
description: "Plan, create, or update the development roadmap with milestones, timelines, and dependencies. Gantt charts and Now/Next/Later framework."
---

# Roadmap Planning

> "A roadmap is a communication tool, not a contract."

## Purpose

Create or update a structured development roadmap that communicates progress, priorities, and timeline to team, community, and investors.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/strategy/platform-review.md` | Current Phase 1/2/3 status |
| `docs/strategy/gap-mapping.md` | All pending gaps |
| `docs/technical/adk-rust-evaluation.md` | Recent decisions (ReactFlow, A2A) |

---

## Process

### 1️⃣ Assess Current Progress
- Check actual sprint status in each repo (Mimir, Heimdall, Bifrost, Fenrir)
- Mark completed items vs in-progress vs blocked
- Identify what shipped since last roadmap update

### 2️⃣ Categorize by Horizon
| Horizon | Timeframe | Commitment Level |
|---------|-----------|-----------------|
| **Now** | 0-3 months | Actively building |
| **Next** | 3-6 months | Committed, not started |
| **Later** | 6-12 months | Planned, flexible |
| **Future** | 12+ months | Vision, may change |

### 3️⃣ Define Milestones
Each milestone must have:
- Clear name and goal
- Specific "Done" criteria (checklist)
- Estimated date or sprint
- Dependencies on other milestones
- Which team/component owns it

### 4️⃣ Estimate and Sequence
- T-shirt sizing: S (1-2 days), M (1 week), L (2-3 weeks), XL (1+ month)
- Map dependencies — what must finish before what?
- Identify the critical path
- Build in buffer (multiply estimates by 1.5x)

### 5️⃣ Visualize
- Create Mermaid Gantt chart for timeline view
- Separate tracks: Platform, Enterprise, Community, DevRel
- Color code by status: ✅ Done, 🚧 In Progress, 📋 Planned

### 6️⃣ Output
Write to `docs/strategy/roadmap.md` and sync with:
- `README.md` roadmap section
- `docs/strategy/platform-review.md` phases

---

## Key Principles
- Show what's DONE alongside what's PLANNED (builds credibility)
- Each milestone must deliver user-visible value
- Over-communicate dependencies
- Update quarterly at minimum

## When to Use
Quarterly roadmap refresh, after completing a milestone, before investor meetings, or when priorities shift.
