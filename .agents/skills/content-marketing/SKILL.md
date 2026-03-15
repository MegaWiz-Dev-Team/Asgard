---
name: content-marketing
description: "Create developer-focused content: blog posts, tutorials, comparison guides, launch announcements, and SEO-optimized documentation for Asgard."
---

# Content Marketing

> "Great documentation is the best marketing for developer tools."

## Purpose

Create and distribute developer-focused content that drives awareness, adoption, and community growth for Asgard AI Platform.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/strategy/competitor-analysis.md` | Positioning and differentiators |
| `docs/strategy/platform-review.md` | Feature highlights |
| `README.md` | Current messaging |

---

## Process

### 1️⃣ Content Types & Templates

| Type | Frequency | Goal |
|------|-----------|------|
| **Technical Blog** | 2x/month | Thought leadership, SEO |
| **Tutorial** | 2x/month | Adoption, reduce time-to-value |
| **Comparison Guide** | Quarterly | SEO, positioning |
| **Release Notes** | Per release | Retention, community trust |
| **Case Study** | When available | Enterprise credibility |
| **Launch Post** | Major releases | Awareness, virality |

### 2️⃣ Blog Post Framework

```markdown
# [Title — What the reader will learn]

**Hook** (2-3 sentences)
- Start with a problem or surprising fact
- Make the reader care

**Context** (1-2 paragraphs)
- Why this matters now
- What alternatives exist

**Solution** (main content)
- Step-by-step with code examples
- Screenshots or diagrams
- Copy-pasteable commands

**Results**
- What you achieved
- Benchmarks or metrics

**Call to Action**
- Try it: `docker compose up`
- Star on GitHub
- Join community
```

### 3️⃣ Tutorial Template

```markdown
# How to [Do Something] with Asgard

**Prerequisites:**
- [ ] Docker installed
- [ ] 16GB+ RAM (Apple Silicon or NVIDIA GPU)

**Time:** ~15 minutes

## Step 1: Setup
[Exact commands]

## Step 2: Configure
[With .env examples]

## Step 3: Run
[Expected output shown]

## Step 4: Verify
[How to confirm it works]

## Troubleshooting
[Common issues and fixes]

## Next Steps
[Link to related tutorials]
```

### 4️⃣ Comparison Guide Structure

```markdown
# Asgard vs [Competitor] — Honest Comparison

## TL;DR
[2-sentence summary of when to use each]

## Feature Comparison
| Feature | Asgard | [Competitor] |
|---------|--------|-------------|
| Self-hosted | ✅ Full | ⚠️ Partial |
| Local LLM | ✅ Native | ❌ Cloud only |
| ... | ... | ... |

## When to Choose Asgard
## When to Choose [Competitor]
## Migration Guide (if applicable)
```

### 5️⃣ Launch Content Checklist

For Product Hunt / HackerNews launches:

```markdown
## Pre-Launch (1 week before)
- [ ] Landing page at asgardai.dev
- [ ] Demo video (2 minutes max)
- [ ] README polished with badges
- [ ] Quick start tested on fresh machine

## Launch Day
- [ ] Product Hunt listing with 5 screenshots
- [ ] HackerNews "Show HN" post
- [ ] Twitter/X thread (6-8 tweets)
- [ ] LinkedIn post
- [ ] Reddit post (r/selfhosted, r/MachineLearning)

## Post-Launch (48 hours)
- [ ] Respond to every comment
- [ ] Thank early users
- [ ] Collect and address feedback
- [ ] Write "lessons learned" post
```

### 6️⃣ SEO for Developer Tools

**Target keywords:**
- "self-hosted AI platform"
- "local LLM gateway"
- "RAG pipeline docker"
- "AI agent framework self-hosted"
- "Apple Silicon LLM"
- "HIPAA compliant AI"

**On-page SEO:**
- Title tag: `[Primary Keyword] — Asgard AI Platform`
- Meta description: 150-160 chars with value proposition
- H1: One per page, include primary keyword
- Internal links to related docs and tutorials

### 7️⃣ Distribution Channels

| Channel | Content Type | Frequency |
|---------|-------------|-----------|
| Blog (asgardai.dev) | All content | 4x/month |
| GitHub README | Updates, badges | Per release |
| Twitter/X | Threads, tips | 3x/week |
| Reddit | Tutorials, launches | 2x/month |
| HackerNews | Deep dives, launches | Monthly |
| Dev.to | Cross-post blogs | 2x/month |
| YouTube | Demos, tutorials | 2x/month |

### 8️⃣ Output

Write content plan to `docs/business/content-plan.md`

---

## Key Principles
- Show, don't tell — always include working code
- Be honest about limitations — developers respect transparency
- Every piece of content should have ONE clear takeaway
- Write for the developer who Googles at midnight

## When to Use
Before launches, monthly content planning, when writing comparison guides, or when establishing thought leadership.
