---
description: Define or refine product vision, direction, and strategic priorities
---

# Product Direction & Vision

## When to use
- Defining initial product vision
- Quarterly product strategy review
- After major market shifts or competitor moves
- Before roadmap planning sessions

## Steps

1. **Review current state**:
   - Read `docs/strategy/platform-review.md` for current strengths/gaps
   - Read `docs/strategy/competitor-analysis.md` for market positioning
   - Check sprint progress in Mimir/Heimdall/Bifrost repos

2. **Define product vision** (if not yet defined):
   - One-line vision statement
   - 3-year product vision narrative
   - Core values / design principles
   - What Asgard will NOT do (anti-goals)

3. **Identify strategic priorities**:
   - List top 3-5 strategic bets for next 6 months
   - Map each priority to a specific gap from gap-mapping.md
   - Rank by: (Impact × Feasibility) / Effort
   - Consider dependencies between priorities

4. **Define success metrics**:
   - North Star Metric (e.g., "Monthly Active Self-Hosted Deployments")
   - Leading indicators (GitHub stars, Docker pulls, community PRs)
   - Lagging indicators (Enterprise leads, revenue)

5. **Write the product direction doc** in `docs/strategy/product-direction.md`:
   ```
   # Asgard — Product Direction
   ## Vision
   ## Design Principles
   ## Anti-Goals
   ## Strategic Priorities (Next 6 Months)
   ## Success Metrics
   ## Key Decisions Log
   ```

6. **Validate against competitors**:
   - Ensure each priority creates differentiation vs Dify/Open WebUI/AnythingLLM
   - Check for emerging competitors or threats

## Key principles
- Vision should be stable (years), priorities should be reviewed quarterly
- Always tie priorities back to customer pain points
- "If everything is a priority, nothing is a priority" — limit to 3-5
