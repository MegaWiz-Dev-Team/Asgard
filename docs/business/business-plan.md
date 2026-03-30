# 🏰 Asgard AI Platform — Business Plan

> Version 1.0 · March 2026

---

## 1. Executive Summary

**Asgard** is a self-hosted AI platform that gives organizations complete control over their AI stack — from LLM inference to RAG pipelines to autonomous agents — running on their own hardware with zero cloud dependency.

**What's built:** 23 sprints delivered across 5 components, 37 features, 255+ tests. Mimir (core platform) is production-ready with multi-tenant IAM, Agent Studio, Knowledge Graph, and Coverage Analytics.

**Market opportunity:** The AI platform market is $28B (2025) growing to $147B by 2030. Self-hosted solutions for regulated industries (healthcare, legal, finance) represent a $4.2B segment with 35% CAGR.

**Revenue model:** Open-core (AGPL-3.0 Community + Commercial Enterprise License). Enterprise pricing starts at $5,000/year per instance.

**Ask:** Bootstrapped initially. Seeking $500K seed round for Year 2 expansion.

---

## 2. Problem Statement

| Pain Point | Who Feels It | Current Solutions |
|:--|:--|:--|
| **Data sovereignty** | Healthcare, legal, finance | Cloud AI = data sent externally |
| **Vendor lock-in** | All enterprises | OpenAI/Azure proprietary APIs |
| **Cost at scale** | High-volume users | $0.01/token adds up fast |
| **Compliance (HIPAA/PDPA)** | Regulated industries | Build from scratch or accept risk |
| **Integration complexity** | Engineering teams | Glue together 5-10 tools |

---

## 3. Solution

Asgard is a **complete, modular, self-hosted AI platform**:

| Component | What it Does | Unique Value |
|:--|:--|:--|
| 🛡️ Heimdall | LLM Gateway | MLX native on Apple Silicon, vLLM on NVIDIA |
| 🧠 Mimir | RAG + Agent Builder | Full pipeline: ingest → chunk → embed → retrieve → generate |
| ⚡ Bifrost | Agent Runtime | ReAct loop, MCP tools, A2A protocol |
| 🐺 Fenrir | Computer Use | Browser/shell automation for agents |
| 🌳 Yggdrasil | Auth | Centralized SSO (Yggdrasil) |

**Key differentiator:** Only platform that natively supports Apple Silicon (MLX) AND NVIDIA (vLLM) for local inference, with a complete RAG + Agent pipeline built in Rust for performance.

---

## 4. Market Analysis

### TAM → SAM → SOM

| Level | Market | Size (2026) | Source |
|:--|:--|:--|:--|
| **TAM** | Global AI Platform Market | $28B | Gartner, MarketsandMarkets |
| **SAM** | Self-hosted AI for regulated industries | $4.2B | 15% of TAM, healthcare+legal+finance |
| **SOM** | SEA market, SMB-mid enterprises | $42M | 1% of SAM, Thailand+Singapore+Vietnam |

### Target Segments (Priority Order)

| Segment | Why | Willingness to Pay |
|:--|:--|:--|
| 🏥 **Healthcare (Thailand)** | PDPA compliance, medical data sensitivity | High ($2K-5K/mo) |
| 🎮 **Game Studios (SEA)** | NPC AI, content generation, local inference | Medium ($500-2K/mo) |
| ⚖️ **Legal Firms** | Document analysis, confidentiality requirements | High ($2K-5K/mo) |
| 🏦 **Financial Services** | Risk analysis, regulatory compliance | Very High ($5K+/mo) |

---

## 5. Business Model & Revenue Streams

| Stream | Type | Timing | Margin |
|:--|:--|:--|:--|
| **Enterprise License** | Recurring (annual) | Year 2+ | ~95% |
| **Hardware Bundles** | One-time + support | Year 1+ | 40-50% |
| **Support & SLA** | Recurring (annual) | Year 2+ | ~90% |
| **Consulting** | One-time | Year 1+ | ~80% |
| **Training & Workshops** | One-time | Year 2+ | ~85% |

> See [pricing-strategy.md](../business/pricing-strategy.md) for hardware bundle tiers: Mini ($2.5K), Pro ($3.8K), Studio ($5.9K), Ultra ($9.5K), GPU ($6-15K)

### Pricing Tiers

| Tier | Annual Price | Target |
|:--|:--|:--|
| Community | Free (AGPL-3.0) | Developers, startups |
| Starter Enterprise | $5,000/yr | Small teams |
| Professional Enterprise | $20,000/yr | Mid-size orgs |
| Custom Enterprise | $50K-200K/yr | Large enterprises |

> See [pricing-strategy.md](../business/pricing-strategy.md) for full details.

---

## 6. Go-to-Market Strategy

> See [go-to-market.md](../business/go-to-market.md) for full details.

| Phase | Timeline | Goal |
|:--|:--|:--|
| **Stealth** | Now - Q2 2026 | Build core, recruit design partners |
| **Developer Preview** | Q3 2026 | GitHub launch, early adopter feedback |
| **Community Launch** | Q4 2026 | v1.0, Product Hunt, HackerNews |
| **Enterprise Pilot** | Q1 2027 | 3-5 paying design partners |
| **Enterprise GA** | Q3 2027 | Sales team, channel partners |

---

## 7. Financial Projections (3-Year)

> *Redacted from public repository. Detailed financial models and cap tables are restricted to NDA data room.*

---

## 8. Team & Resources

> *Redacted from public repository. Hiring plans and compensation budgets are restricted to NDA data room.*

---

## 9. Milestones & Timeline

```mermaid
gantt
    title Asgard Business Milestones
    dateFormat YYYY-MM
    axisFormat %b %Y

    section Product
    v0.5 Foundation        :done,    p1, 2026-04, 2026-06
    v0.8 Growth            :active,  p2, 2026-07, 2026-09
    v1.0 Community Launch  :         p3, 2026-10, 2026-12

    section Business
    Design Partners        :active,  b1, 2026-04, 2026-09
    Developer Preview      :         b2, 2026-07, 2026-09
    Community Launch       :         b3, 2026-10, 2026-12
    Enterprise Pilot       :         b4, 2027-01, 2027-06
    Enterprise GA          :         b5, 2027-07, 2027-12

    section Revenue
    First Consulting       :         r1, 2026-07, 2026-09
    First Enterprise Deal  :         r2, 2027-03, 2027-06
    $100K ARR              :         r3, 2027-09, 2027-12
```

---

## 10. Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|:--|:--|:--|:--|
| **Dify/competitor catches up** | Medium | High | Move fast; MLX native is hard to replicate |
| **Apple Silicon niche too small** | Low | Medium | vLLM support covers NVIDIA; dual-platform |
| **Solo founder bottleneck** | High | High | Hire first engineer at $100K ARR |
| **Enterprise sales cycle too long** | Medium | Medium | Start with design partners (free); reduce friction |
| **AGPL compliance monitoring** | Low | Low | License key enforcement; AGPL copyleft protects |
| **Open source fork** | Low | Medium | Stay ahead; Enterprise features create value gap |

---

## 11. Funding & Use of Proceeds

### Bootstrap Phase (Current)
- Self-funded by founder
- Revenue from consulting covers infrastructure costs
- Focus: ship v1.0, recruit design partners

### Seed Round (Target: Q2 2027)
> *Redacted from public repository.*-

*📅 Created: March 2026 · Contact: paripol@megawiz.co*
