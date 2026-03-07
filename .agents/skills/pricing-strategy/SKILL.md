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

### 4️⃣ Revenue Projection
- Year 1: Design partners (free/discounted)
- Year 2: First enterprise customers
- Year 3: Scaled enterprise sales
- Model: # customers × ARPU × growth rate

### 5️⃣ Output
Write to `docs/business/pricing-strategy.md`

---

## Key Principles
- Community Edition must be genuinely useful
- Enterprise price < cost of building it themselves
- Start with fewer tiers, expand as you learn
- Self-hosted = harder to enforce licensing, plan accordingly

## When to Use
Initial pricing design, responding to competitor changes, before enterprise sales, or quarterly pricing review.
