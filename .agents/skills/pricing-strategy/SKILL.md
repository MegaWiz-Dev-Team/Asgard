---
name: pricing-strategy
description: "Define pricing strategy, tiers, feature gates, and revenue model for Community and Enterprise editions."
---

# Pricing & Revenue Strategy

> "Price based on value delivered, not cost of development."

## Purpose

Design a pricing model that maximizes revenue while keeping the Community Edition genuinely useful and the Enterprise Edition compelling.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/strategy/competitor-analysis.md` | Competitor pricing data |
| `COMMERCIAL.md` | Current Enterprise feature list |

---

## Process

### 1️⃣ Competitive Pricing Benchmark
| Competitor | Free | Cloud | Enterprise |
|-----------|------|-------|-----------|
| Dify | Self-host free | $59-159/mo | ¥500K/yr |
| Flowise | Self-host free | $35-65/mo | Custom |
| LangFlow | Self-host free | — | $2K+/mo |
| n8n | Self-host free | €20-800/mo | Custom |

### 2️⃣ Define Pricing Model
Evaluate which model fits self-hosted AI:

| Model | Fit | Rationale |
|-------|-----|-----------|
| Per-seat | ⚠️ | Hard to enforce self-hosted |
| Per-instance | ✅ | Easy to track, clear value |
| Feature-gate | ✅ | Clear Community vs Enterprise |
| Usage-based | ❌ | Complex billing for self-hosted |
| Support-only | ⚠️ | Low ARPU |

### 3️⃣ Define Enterprise Feature Gates
Draw clear line between Community and Enterprise:
- Community must be genuinely useful (not crippled)
- Enterprise features should be "nice to have" for small teams, "must have" for enterprises
- Reference `COMMERCIAL.md` and update if needed

### 4️⃣ Ideal Customer Profile (ICP)

Define who pays for Asgard Enterprise:

```markdown
## ICP Definition
- **Industry**: Healthcare, Legal, Financial, Government
- **Company Size**: 50-500 employees
- **Budget Authority**: CTO / VP Engineering / CISO
- **Pain Point**: Data sovereignty, HIPAA/PDPA compliance
- **Current Solution**: Cloud AI (concerned about data leaks)
- **Decision Trigger**: Compliance audit or data breach fear
```

### 5️⃣ Positioning Statement

```
For [ICP — regulated organizations with sensitive data]
Who need [AI capabilities without cloud data exposure]
Asgard is [a self-hosted AI platform]
That [runs entirely on-premises with zero cloud dependency]
Unlike [Dify, Open WebUI, cloud AI providers]
Our product [provides full-stack AI with local LLM inference, RAG, agents, and computer use]
```

### 6️⃣ Value Metric Identification

| Candidate Metric | Pros | Cons |
|-----------------|------|------|
| Per-instance | Simple, predictable | Doesn't scale with value |
| Per-active-user | Aligns with usage | Hard to enforce self-hosted |
| Per-pipeline-run | Aligns with value | Complex metering |
| **Feature-gate** ✅ | Clear, enforceable | Must choose right gate |

**Recommended:** Feature-gate + per-instance

### 7️⃣ Revenue Projection
- Year 1: Design partners (free/discounted)
- Year 2: First enterprise customers
- Year 3: Scaled enterprise sales
- Model: # customers × ARPU × growth rate

### 8️⃣ Pricing Experiments

- A/B test pricing page with different tier names
- Test annual vs monthly billing preference
- Survey design partners on willingness-to-pay
- Track conversion at each price point
- Adjust quarterly based on data

### 9️⃣ Output
Write to `docs/business/pricing-strategy.md`

---

## Key Principles
- Community Edition must be genuinely useful
- Enterprise price < cost of building it themselves
- Start with fewer tiers, expand as you learn
- Self-hosted = harder to enforce licensing, plan accordingly
- Know your customer (ICP) before you price the product

## When to Use
Initial pricing design, responding to competitor changes, before enterprise sales, or quarterly pricing review.
