---
description: Plan, create, or update the development roadmap with milestones and timelines
---

# Roadmap Planning

## When to use
- Quarterly roadmap refresh
- After completing a major milestone
- When priorities shift based on user/market feedback
- Before investor meetings (to show execution plan)

## Steps

1. **Assess current progress**:
   - Read `docs/strategy/platform-review.md` Phase 1/2/3 status
   - Read `docs/strategy/gap-mapping.md` for pending gaps
   - Check actual sprint status in each repo (Mimir, Heimdall, Bifrost, Fenrir)

2. **Categorize items by horizon**:
   - **Now (0-3 months)**: What's actively being built
   - **Next (3-6 months)**: Committed but not started
   - **Later (6-12 months)**: Planned but flexible
   - **Future (12+ months)**: Vision items

3. **Define milestones with clear criteria**:
   ```
   Milestone: "Community v1.0 Launch"
   - [ ] All critical gaps resolved
   - [ ] Docker one-command install works
   - [ ] Documentation site live at asgardai.dev
   - [ ] 10+ beta users testing
   ```

4. **Estimate effort for each item**:
   - T-shirt sizing: S (1-2 days), M (1 week), L (2-3 weeks), XL (1+ month)
   - Identify blockers and dependencies
   - Flag items that need external input (e.g., Zitadel integration)

5. **Create visual roadmap** in `docs/strategy/roadmap.md`:
   - Use Mermaid Gantt chart for timeline view
   - Include dependency arrows between milestones
   - Separate tracks: Platform, Enterprise, Community, DevRel

6. **Update all related docs**:
   - Sync with `README.md` roadmap section
   - Sync with `docs/strategy/platform-review.md` phases
   - Update Mimir/Bifrost/Fenrir sprint plans if affected

## Key principles
- Roadmap is a communication tool, not a contract
- Always show what's DONE alongside what's PLANNED (builds credibility)
- Over-communicate dependencies — they are the #1 schedule risk
- Each milestone should deliver user-visible value
