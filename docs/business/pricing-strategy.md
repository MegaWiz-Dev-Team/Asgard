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
| **Price** | $500/mo (฿17,500/mo) per instance |
| **Annual** | $5,000/yr (฿175,000/yr) — 2 months free |
| **Includes** | All Enterprise features, email support (48h SLA) |
| **Best for** | Small teams, startups, single-server deployments |

### Professional Enterprise
| Item | Details |
|:--|:--|
| **Price** | $2,000/mo (฿70,000/mo) per instance |
| **Annual** | $20,000/yr (฿700,000/yr) — 2 months free |
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
- Year 1: 3-5 design partners (discounted/free), 2-3 hardware sales
- Year 2: 10-20 paying customers (mix of Starter + Professional), 8-12 hardware
- Year 3: 30-50 customers, 2-3 Custom deals, 15-25 hardware
- SEA market first, then global expansion

| Year | Software Customers | Software ARR | Hardware Units | Hardware Revenue | **Total Revenue** |
|:--|:--|:--|:--|:--|:--|
| **Year 1 (2026)** | 3 design partners | $0 | 3 | $15K | **$15K** |
| **Year 2 (2027)** | 15 paid | $180K | 10 | $80K | **$260K** |
| **Year 3 (2028)** | 40 paid + 3 Custom | $774K | 20 | $200K | **$974K** |

---

## 🖥️ Hardware Bundles — "Asgard-Ready Appliance"

> **Concept:** ขาย hardware (Apple Silicon / NVIDIA) pre-configured กับ Asgard พร้อมใช้งาน — เปิดกล่อง, เสียบปลั๊ก, ใช้ AI ได้เลย

### Value Proposition
- **Zero-config**: Asgard + Docker + LLM models pre-installed
- **Optimized**: OS tuning, MLX/vLLM configured for hardware
- **Warranty**: Hardware + Software bundle support
- **On-site**: จัดส่ง + setup + training included in premium tiers

### Hardware Tiers

#### 🟢 Tier 1 — Asgard Mini (Entry-Level)
| Item | Spec | Hardware Cost | Bundle Price | Margin |
|:--|:--|:--|:--|:--|
| **Mac Mini M4 Pro** | 12C CPU, 16C GPU, 24GB RAM, 512GB | ~$1,400 (฿49,000) | **$2,500 (฿87,500)** | $1,100 (44%) |
| **Pre-installed** | Asgard Community, Heimdall, MLX, Qwen 9B model | | | |
| **Best for** | Solo developer, prototyping, small RAG chatbot | | | |

#### 🔵 Tier 2 — Asgard Pro (Production)
| Item | Spec | Hardware Cost | Bundle Price | Margin |
|:--|:--|:--|:--|:--|
| **Mac Mini M4 Pro** | 14C CPU, 20C GPU, 48GB RAM, 1TB | ~$2,200 (฿77,000) | **$3,800 (฿133,000)** | $1,600 (42%) |
| **Pre-installed** | Asgard + Enterprise License (1yr), Qwen 35B MoE | | | |
| **Best for** | SMB production, multi-tenant, 5-10 users | | | |

#### 🟣 Tier 3 — Asgard Studio (Power User)
| Item | Spec | Hardware Cost | Bundle Price | Margin |
|:--|:--|:--|:--|:--|
| **Mac Studio M4 Max** | 16C CPU, 40C GPU, 128GB RAM, 1TB | ~$3,500 (฿122,500) | **$5,900 (฿206,500)** | $2,400 (41%) |
| **Pre-installed** | Asgard Enterprise, Qwen 35B + MedGemma, Neo4j, Vault | | | |
| **Best for** | Healthcare/legal RAG, large knowledge base, 20+ users | | | |

#### 🟠 Tier 4 — Asgard Ultra (Enterprise)
| Item | Spec | Hardware Cost | Bundle Price | Margin |
|:--|:--|:--|:--|:--|
| **Mac Studio M4 Ultra** | 32C CPU, 80C GPU, 192GB RAM, 2TB | ~$5,500 (฿192,500) | **$9,500 (฿332,500)** | $4,000 (42%) |
| **Pre-installed** | Asgard Enterprise + Custom, multi-agent, full model suite | | | |
| **Add-ons** | On-site setup, training (2 days), 1-year priority support | | | |
| **Best for** | Hospital groups, financial institutions, 50+ users | | | |

#### 🔴 Tier 5 — Asgard GPU Server (NVIDIA)
| Item | Spec | Hardware Cost | Bundle Price | Margin |
|:--|:--|:--|:--|:--|
| **NVIDIA GPU Server** | RTX 4090 (24GB) or A6000 (48GB) | ~$3K-$8K (฿105K-280K) | **$6K-$15K (฿210K-525K)** | $3K-$7K (50%) |
| **Pre-installed** | Asgard Enterprise, vLLM, CUDA optimized | | | |
| **Add-ons** | On-site setup, rack mounting, 1-year support | | | |
| **Best for** | High-throughput inference, training fine-tune, GPU clusters | | | |

### Pricing Summary

| Tier | Hardware | Bundle Price (USD) | Bundle Price (THB) | Includes |
|:--|:--|:--|:--|:--|
| 🟢 **Mini** | Mac Mini M4 Pro 24GB | **$2,500** | **฿87,500** | Community + MLX + 9B model |
| 🔵 **Pro** | Mac Mini M4 Pro 48GB | **$3,800** | **฿133,000** | Enterprise 1yr + 35B model |
| 🟣 **Studio** | Mac Studio M4 Max 128GB | **$5,900** | **฿206,500** | Enterprise + Neo4j + Vault |
| 🟠 **Ultra** | Mac Studio M4 Ultra 192GB | **$9,500** | **฿332,500** | Enterprise Custom + on-site |
| 🔴 **GPU** | NVIDIA RTX/A6000 Server | **$6K-$15K** | **฿210K-525K** | Enterprise + vLLM + CUDA |

### Hardware Bundle Strategy
1. **Apple ARM = primary** — Thailand has Apple reseller network; easy to source
2. **NVIDIA = on-demand** — For customers needing GPU training/fine-tuning
3. **Margin target** — 40-50% gross margin on hardware bundles
4. **Upsell path** — Mini → Pro → Studio as customer grows
5. **Service add-ons** — On-site setup ($500/฿17,500), Training ($1,000/day / ฿35,000/day), Annual maintenance ($1,200/yr / ฿42,000/yr)

> *อัตราแลกเปลี่ยนอ้างอิง: 1 USD ≈ 35 THB (ปรับตามอัตราจริง ณ วันขาย)*

---

## Feature Gate Enforcement

Since Asgard is self-hosted (AGPL-3.0), enforcement relies on:

1. **License key check** — Enterprise binary checks valid license key on startup
2. **Feature flags** — Enterprise features disabled without valid key
3. **AGPL copyleft** — Modifications must be open-sourced (encourages Enterprise license)
4. **Audit trail** — Enterprise features log license status

---

*📅 Created: March 2026 · Updated: March 2026 (added hardware bundles)*
