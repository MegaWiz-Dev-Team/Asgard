---
description: Create an investor pitch deck outline and supporting materials
---

# Investor Pitch Deck

## When to use
- Preparing for investor meetings
- Applying to accelerators
- Creating fundraising materials
- Annual pitch refresh

## Steps

1. **Gather all materials**:
   - `docs/README.md` — Docs index and overview
   - `docs/strategy/platform-review.md` — Platform strengths
   - `docs/strategy/competitor-analysis.md` — Market landscape
   - `docs/strategy/gap-mapping.md` — Execution plan
   - `COMMERCIAL.md` — Enterprise licensing model

2. **Create pitch deck outline** in `docs/business/pitch-deck.md`:
   ```
   # Asgard AI Platform — Investor Deck

   ## Slide 1: Title
   "Asgard — Self-Hosted AI Platform for Enterprises"
   asgardai.dev | paripol@megawiz.co

   ## Slide 2: Problem
   - Enterprise data cannot go to cloud (PDPA/HIPAA/compliance)
   - Existing AI platforms require cloud APIs
   - No full-stack self-hosted solution exists

   ## Slide 3: Solution
   - Full-stack self-hosted AI: Gateway + RAG + Agent + Computer Use
   - Native Apple Silicon + NVIDIA GPU support
   - 100% on-premise — data never leaves

   ## Slide 4: Product (Demo/Screenshots)
   - Dashboard, RAG Pipeline, Agent Builder, Playground

   ## Slide 5: Market Size (TAM/SAM/SOM)
   - TAM: Global AI platform market
   - SAM: Self-hosted AI for regulated industries
   - SOM: Healthcare + Legal + Financial + Game SMEs in SEA

   ## Slide 6: Traction
   - 8 sprints completed, production-ready components
   - GitHub stars, community metrics
   - Early design partners

   ## Slide 7: Competition
   - Reference competitor-analysis.md positioning chart
   - Clear differentiation: only self-hosted + local inference + full-stack

   ## Slide 8: Business Model
   - Community (AGPL-3.0) → Enterprise License → Support/SLA
   - Reference COMMERCIAL.md pricing tiers

   ## Slide 9: Go-to-Market
   - Open source community → design partners → enterprise sales
   - Target: Healthcare, Legal, Financial, Game Studio in SEA

   ## Slide 10: Team
   - Founders, key engineers, advisors

   ## Slide 11: Roadmap
   - Phase 1 (Done) → Phase 2 (In Progress) → Phase 3 (Enterprise)

   ## Slide 12: Ask
   - Funding amount, use of proceeds, milestones
   ```

3. **Generate supporting visuals**:
   - Use mermaid diagrams from architecture.md
   - Create market positioning chart from competitor-analysis.md
   - Generate product screenshots if available

4. **Review and refine** — Present to user for feedback.

## Key principles
- Keep slides minimal — 1 idea per slide
- Lead with the problem, not the technology
- Show traction and momentum (sprints done, production components)
- Be specific about market size with bottom-up calculations
- The "Ask" slide should have clear milestones tied to funding
