---
name: go-to-market
description: "Plan go-to-market strategy including launch timeline, community building, developer adoption funnel, and enterprise sales process."
---

# Go-to-Market Strategy

> "The best product doesn't win. The best-distributed product wins."

## Purpose

Plan how Asgard reaches its target customers — from open source community launch to enterprise sales pipeline.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/strategy/competitor-analysis.md` | Target segments and positioning |
| `docs/strategy/platform-review.md` | Roadmap phases |
| `COMMERCIAL.md` | Enterprise vs Community features |

---

## Process

### 1️⃣ Define Launch Phases
```
Phase 1: Stealth → Build core product (CURRENT)
Phase 2: Developer Preview → GitHub + docs + early adopters
Phase 3: Community Launch → v1.0, Product Hunt, HackerNews
Phase 4: Enterprise Pilot → Design partners in target segments
Phase 5: Enterprise GA → Sales team, pricing, support
```

### 2️⃣ Developer Adoption Funnel
```
Discover → Try → Use → Love → Advocate → Pay
   ↓        ↓     ↓      ↓       ↓         ↓
  HN/PH   Docker  Daily  Contrib  Blog    Enterprise
```
For each stage, define:
- Actions to drive conversion
- Content needed
- Metrics to track

### 3️⃣ Community Building
- GitHub: README quality, CONTRIBUTING.md, issue templates
- Documentation site at asgardai.dev
- Content: blog posts, tutorials, comparison guides, videos
- Social: Twitter/X, LinkedIn, Reddit, HackerNews
- Events: meetups, conference talks

### 4️⃣ Enterprise Sales
- Identify design partners in Tier 1 segments
- Define sales process: Free → POC → Enterprise License
- Build case studies from design partners
- Partner channel strategy

### 5️⃣ GTM Metrics Dashboard

Track these metrics weekly/monthly:

| Category | Metric | Target |
|----------|--------|--------|
| **Awareness** | GitHub stars growth | +200/month |
| **Awareness** | Docker Hub pulls | +500/month |
| **Acquisition** | Website → GitHub click rate | > 15% |
| **Activation** | docker compose up success rate | > 90% |
| **Retention** | Monthly active deployments | Track |
| **Revenue** | MRR (Enterprise) | Track |
| **Revenue** | CAC (Customer Acquisition Cost) | < $500 |
| **Revenue** | LTV/CAC ratio | > 3x |

### 6️⃣ Solo/Small-Team GTM Playbook

Weekly cadence for resource-constrained teams:

| Day | Activity | Time |
|-----|----------|------|
| Mon | Write 1 technical blog post | 2h |
| Tue | Engage on Reddit/HN/Twitter | 1h |
| Wed | Respond to issues + community | 1h |
| Thu | Record demo or tutorial | 2h |
| Fri | Outreach to 3 potential design partners | 1h |

**Budget-constrained approach:**
- $0: Open source + content + community
- GitHub Sponsors for sustainable funding
- Design partners for enterprise validation (free tier)

### 7️⃣ Content-Led Growth

Link content to pipeline stages:
```
Blog post → GitHub star → docker compose up → Active user → Enterprise lead
    ↑            ↑              ↑                  ↑             ↑
  SEO/Social   README        Quick Start        Features      Case study
```

See `content-marketing` skill for detailed content creation workflows.

### 8️⃣ Output
Write to `docs/business/go-to-market.md`:
```
# Go-to-Market Strategy
## 1. Launch Timeline & Phases
## 2. Developer Adoption Funnel
## 3. Community Building Plan
## 4. Enterprise Sales Process
## 5. GTM Metrics Dashboard
## 6. Solo/Small-Team Playbook
## 7. Content-Led Growth
## 8. Budget Allocation
```

---

## Key Principles
- Community-led growth first, enterprise sales second
- Great docs = best marketing for developer tools
- "Make it easy to start, hard to leave"
- SEA market first, then expand globally
- Measure everything — what you can't measure, you can't improve

## When to Use
Before Community Edition launch, when planning enterprise launch, entering a new market, or quarterly GTM review.
