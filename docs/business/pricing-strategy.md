# 💰 Asgard — Pricing Strategy

> Last updated: March 2026

---

## Competitive Benchmark

| Platform | Self-Host | Cloud | Enterprise |
|:--|:--|:--|:--|
| **Dify** | Free (Apache 2.0) | $59-159/mo | Custom (~¥500K/yr) |
| **Flowise** | Free (Apache 2.0) | $35-65/mo | Custom |
| **LangFlow** | Free (MIT) | — | $2K+/mo |
| **n8n** | Free (modified) | €20-800/mo | Custom |
| **Asgard** | **Free (AGPL-3.0)** | **N/A** | **See below** |

**Key insight:** Self-hosted is always free. Enterprise value comes from features, not access.

---

## Pricing Model: Feature-Gate + Support

| Model | Fit | Why |
|:--|:--|:--|
| Per-seat | ⚠️ | Hard to enforce self-hosted |
| **Per-instance** | **✅** | Easy to track, clear value |
| **Feature-gate** | **✅** | Clear Community vs Enterprise |
| Usage-based | ❌ | Complex billing for self-hosted |

**Decision:** Feature-gated tiers + per-instance licensing + optional support add-on.

---

## Tier Comparison

| Feature | Community (Free) | Enterprise |
|:--|:--|:--|
| **Core Platform** | | |
| RAG Pipeline + Agent Builder | ✅ | ✅ |
| Visual Workflow Builder | ✅ | ✅ |
| Multi-backend LLM Gateway | ✅ | ✅ |
| Knowledge Graph (Neo4j) | ✅ | ✅ |
| Docker Compose deploy | ✅ | ✅ |
| Community support (GitHub) | ✅ | ✅ |
| **Enterprise Features** | | |
| Multi-agent collaboration | ❌ | ✅ |
| SSO (SAML, OIDC, LDAP) via Zitadel | ❌ | ✅ |
| Audit logging (SOC 2, HIPAA) | ❌ | ✅ |
| HA clustering (multi-node) | ❌ | ✅ |
| White-label branding | ❌ | ✅ |
| Usage analytics + cost dashboard | ❌ | ✅ |
| Advanced RBAC (org-level) | ❌ | ✅ |
| Priority support (SLA) | ❌ | ✅ |

---

## Enterprise Pricing

### Starter Enterprise
| Item | Details |
|:--|:--|
| **Price** | $500/month per instance |
| **Annual** | $5,000/year (2 months free) |
| **Includes** | All Enterprise features, email support (48h SLA) |
| **Best for** | Small teams, startups, single-server deployments |

### Professional Enterprise
| Item | Details |
|:--|:--|
| **Price** | $2,000/month per instance |
| **Annual** | $20,000/year (2 months free) |
| **Includes** | HA clustering, priority support (4h SLA), dedicated Slack |
| **Best for** | Mid-size orgs, multi-node, regulated industries |

### Custom Enterprise
| Item | Details |
|:--|:--|
| **Price** | Custom pricing |
| **Includes** | White-label, on-premise consulting, custom integrations |
| **Best for** | Large enterprises, hospital groups, financial institutions |

---

## Revenue Projection (3-Year)

### Assumptions
- Year 1: 3-5 design partners (discounted/free)
- Year 2: 10-20 paying customers (mix of Starter + Professional)
- Year 3: 30-50 customers, 2-3 Custom deals
- SEA market first, then global expansion

| Year | Customers | Avg ARPU | ARR |
|:--|:--|:--|:--|
| **Year 1 (2026)** | 3 design partners | $0 (free) | $0 |
| **Year 2 (2027)** | 15 paid | $12K/yr | $180K |
| **Year 3 (2028)** | 40 paid + 3 Custom | $18K/yr avg | $774K |

---

## Feature Gate Enforcement

Since Asgard is self-hosted (AGPL-3.0), enforcement relies on:

1. **License key check** — Enterprise binary checks valid license key on startup
2. **Feature flags** — Enterprise features disabled without valid key
3. **AGPL copyleft** — Modifications must be open-sourced (encourages Enterprise license)
4. **Audit trail** — Enterprise features log license status

---

*📅 Created: March 2026*
