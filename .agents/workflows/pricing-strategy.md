---
description: Define pricing strategy, tiers, and revenue model for Community and Enterprise editions
---

# Pricing & Revenue Strategy

## When to use
- Initial pricing model design
- Adding new pricing tiers
- Responding to competitor price changes
- Before enterprise sales conversations

## Steps

1. **Review competitive pricing** from `docs/strategy/competitor-analysis.md`:
   | Competitor | Free Tier | Cloud Tier | Enterprise |
   |:--|:--|:--|:--|
   | Dify | Self-host free | $59-159/mo | ¥500K/yr |
   | Flowise | Self-host free | $35-65/mo | Custom |
   | LangFlow | Self-host free | — | $2K+/mo |
   | n8n | Self-host free | €20-800/mo | Custom |
   | Open WebUI | Free (MIT) | — | — |

2. **Define Asgard pricing tiers**:
   ```
   Community Edition (AGPL-3.0)
   └── Free forever, self-hosted, full features
       └── Revenue: $0 (community growth)

   Enterprise Edition (Commercial License)
   ├── Starter: $X/mo — SSO, audit, 1 instance
   ├── Professional: $X/mo — HA, advanced RBAC, priority support
   └── Enterprise: Custom — White-label, SLA, dedicated support
   ```

3. **Evaluate pricing models**:
   | Model | Pros | Cons | Fit for Asgard |
   |:--|:--|:--|:--|
   | Per-seat | Predictable | Hard to enforce self-hosted | ⚠️ |
   | Per-instance | Easy to enforce | Doesn't scale with usage | ✅ |
   | Feature-gate | Clear value prop | Must maintain two editions | ✅ |
   | Usage-based | Scales with value | Complex billing | ❌ |
   | Support-only | Simple | Low ARPU | ⚠️ |

4. **Define Enterprise feature gates**:
   - What features are Community-only vs Enterprise-only?
   - Reference `COMMERCIAL.md` for current feature list
   - Ensure Community Edition is genuinely useful (not crippled)

5. **Write pricing doc** in `docs/business/pricing-strategy.md`

## Key principles
- Community Edition must be genuinely useful — not crippled
- Enterprise price should be < cost of building it themselves
- Price based on value delivered, not cost of development
- Start with fewer tiers and expand as you learn
- Self-hosted = harder to enforce licensing, plan accordingly
