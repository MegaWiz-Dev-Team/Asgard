---
name: business-plan
description: "Create or update a comprehensive business plan for Asgard AI Platform. Revenue model, financial projections, market sizing, team planning."
---

# Business Plan Generator

> "A plan without numbers is just a wish."

## Purpose

Generate a structured, investor-ready business plan for Asgard AI Platform by synthesizing existing strategy docs, market research, and financial modeling.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/strategy/platform-review.md` | Current platform strengths and gaps |
| `docs/strategy/competitor-analysis.md` | Market landscape and pricing |
| `docs/strategy/gap-mapping.md` | Implementation priorities |
| `COMMERCIAL.md` | Enterprise licensing model |

---

## Process

### 1️⃣ Context Gathering (Mandatory)
- Read all prerequisite docs above
- Identify what already exists vs what needs to be created
- Ask the user about: team size, funding stage, timeline, geography

### 2️⃣ Market Sizing (TAM → SAM → SOM)
- **TAM**: Global AI platform market (cite real market research)
- **SAM**: Self-hosted AI for regulated industries (Healthcare, Legal, Financial, Game)
- **SOM**: Target geography × target segments × realistic penetration rate
- Use bottom-up calculation, not top-down

### 3️⃣ Revenue Model
- Define tiers from `COMMERCIAL.md`
- Model pricing against competitors in `competitor-analysis.md`
- Project customer acquisition: Year 1 (design partners) → Year 2 (community growth) → Year 3 (enterprise sales)

### 4️⃣ Financial Projections
- 3-year P&L forecast
- Cost structure: engineering, infrastructure, marketing, support
- Key assumptions documented explicitly
- Break-even analysis
- Runway calculation based on funding ask

### 5️⃣ Output Document
Write to `docs/business/business-plan.md`:
```
# Asgard AI Platform — Business Plan
## 1. Executive Summary
## 2. Problem Statement
## 3. Solution
## 4. Market Analysis (TAM/SAM/SOM)
## 5. Business Model & Revenue Streams
## 6. Go-to-Market Strategy
## 7. Financial Projections (3-year)
## 8. Team & Resources
## 9. Milestones & Timeline
## 10. Risks & Mitigation
## 11. Funding Ask & Use of Proceeds
```

---

## Key Principles
- Reference existing docs — don't duplicate content
- Every number needs a stated assumption
- Be conservative in revenue, generous in costs
- Show what's ALREADY BUILT (8 sprints) — it de-risks the plan

## When to Use
Before investor meetings, accelerator applications, annual planning, or when pivoting strategy.
