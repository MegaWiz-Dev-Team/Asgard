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
| SSO (SAML, OIDC, LDAP) via Yggdrasil | ❌ | ✅ |
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

> *Redacted from public repository. 3-Year revenue forecasts are restricted to NDA data room.*

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
| Item | Spec | Bundle Price |
|:--|:--|:--|
| **Mac Mini M4 Pro** | 12C CPU, 16C GPU, 24GB RAM, 512GB | **$2,500 (฿87,500)** |
| **Pre-installed** | Asgard Community, Heimdall, MLX, Qwen 9B model | |
| **Best for** | Solo developer, prototyping, small RAG chatbot | |

#### 🔵 Tier 2 — Asgard Pro (Production)
| Item | Spec | Bundle Price |
|:--|:--|:--|
| **Mac Mini M4 Pro** | 14C CPU, 20C GPU, 48GB RAM, 1TB | **$3,800 (฿133,000)** |
| **Pre-installed** | Asgard + Enterprise License (1yr), Qwen 35B MoE | |
| **Best for** | SMB production, multi-tenant, 5-10 users | |

#### 🟣 Tier 3 — Asgard Studio (Power User)
| Item | Spec | Bundle Price |
|:--|:--|:--|
| **Mac Studio M4 Max** | 16C CPU, 40C GPU, 128GB RAM, 1TB | **$5,900 (฿206,500)** |
| **Pre-installed** | Asgard Enterprise, Qwen 35B + MedGemma, Neo4j, Vault | |
| **Best for** | Healthcare/legal RAG, large knowledge base, 20+ users | |

#### 🟠 Tier 4 — Asgard Ultra (Enterprise)
| Item | Spec | Bundle Price |
|:--|:--|:--|
| **Mac Studio M4 Ultra** | 32C CPU, 80C GPU, 192GB RAM, 2TB | **$9,500 (฿332,500)** |
| **Pre-installed** | Asgard Enterprise + Custom, multi-agent, full model suite | |
| **Add-ons** | On-site setup, training (2 days), 1-year priority support | |
| **Best for** | Hospital groups, financial institutions, 50+ users | |

#### 🟡 Tier 5 — Asgard Spark (NVIDIA DGX Spark)
| Item | Spec | Bundle Price |
|:--|:--|:--|
| **NVIDIA DGX Spark** | GB10 Blackwell, 128GB unified, 4TB NVMe, 1 PFLOP FP4 | **$7,500 (฿262,500)** |
| **Pre-installed** | Asgard Enterprise, DGX OS (Ubuntu), vLLM, models up to 200B inference | |
| **Best for** | AI-first orgs, fine-tune up to 70B, inference 200B, compact desktop | |

#### 🟡 Tier 6 — Asgard Spark Duo (2x DGX Spark linked)
| Item | Spec | Bundle Price |
|:--|:--|:--|
| **2x DGX Spark** | 256GB unified, 8TB NVMe, 2 PFLOP FP4, 100GbE link | **$14,000 (฿490,000)** |
| **Pre-installed** | Asgard Enterprise Custom, models up to **405B** (Llama 3.1 405B) | |
| **Add-ons** | On-site setup, networking config, 1-year priority support | |
| **Best for** | Research labs, hospitals needing largest models, R&D teams | |

#### 🔴 Tier 7 — Asgard GPU Server (NVIDIA Discrete GPU)
| Item | Spec | Bundle Price |
|:--|:--|:--|
| **NVIDIA GPU Server** | RTX 4090 (24GB) or A6000 (48GB) | **$6K-$15K (฿210K-525K)** |
| **Pre-installed** | Asgard Enterprise, vLLM, CUDA optimized | |
| **Add-ons** | On-site setup, rack mounting, 1-year support | |
| **Best for** | High-throughput inference, training fine-tune, multi-GPU clusters | |

### Pricing Summary

> *Redacted from public repository. Detailed price structuring and margins are available under NDA.*

### Hardware Bundle Strategy
1. **Apple ARM = primary** — Thailand has Apple reseller network; easy to source
2. **DGX Spark = AI-first** — 128GB unified memory, Blackwell GPU, compact desktop form factor
3. **NVIDIA discrete GPU = on-demand** — For customers needing multi-GPU training/fine-tuning
4. **Margin target** — 35-50% gross margin on hardware bundles
5. **Upsell path** — Mini → Pro → Studio/Spark → Ultra/Spark Duo as customer grows
6. **Service add-ons** — On-site setup ($500/฿17,500), Training ($1,000/day / ฿35,000/day), Annual maintenance ($1,200/yr / ฿42,000/yr)

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
