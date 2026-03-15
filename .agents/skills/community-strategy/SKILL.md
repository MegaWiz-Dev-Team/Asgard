---
name: community-strategy
description: "Plan and manage open source community growth, governance, contribution guidelines, and developer relations."
---

# Community & Open Source Strategy

> "Community first, product second — healthy community = sustainable project."

## Purpose

Build and nurture an open source community around Asgard. Define governance, contribution guidelines, and growth strategies.

---

## Process

### 1️⃣ Repo Readiness Checklist
Before going public, every repo needs:
- [ ] Professional README.md with badges
- [ ] CONTRIBUTING.md — how to contribute
- [ ] CODE_OF_CONDUCT.md — community standards
- [ ] LICENSE — AGPL-3.0
- [ ] CLA.md — Contributor License Agreement
- [ ] Issue templates (bug report, feature request)
- [ ] PR template (description, testing, screenshots)
- [ ] .github/FUNDING.yml — sponsorship links

### 2️⃣ Community Channels
| Channel | Purpose |
|---------|---------|
| GitHub Discussions | Primary async communication |
| Discord | Real-time chat, support |
| Twitter/X @AsgardAIDev | Announcements, engagement |
| Blog (asgardai.dev) | Tutorials, releases, case studies |

### 3️⃣ Governance Model
```
BDFL (Benevolent Dictator For Life)
├── Core Team — Commit access, PR reviews
├── Contributors — PRs, issues, docs
└── Community — Users, feedback, bug reports
```

### 4️⃣ Content Calendar (Monthly)
| Week | Content Type |
|------|-------------|
| 1 | Release notes / changelog |
| 2 | Technical deep-dive blog |
| 3 | Community spotlight / showcase |
| 4 | Tutorial / how-to guide |

### 5️⃣ Health Metrics
| Metric | Target |
|--------|--------|
| Issue response time | < 48 hours |
| PR merge time | < 1 week |
| GitHub stars growth | Track monthly |
| Docker Hub pulls | Track monthly |
| Active contributors | Track monthly |

### 6️⃣ Developer Relations (DevRel)

| Activity | Frequency | Goal |
|----------|-----------|------|
| Write tutorials | 2x/month | Reduce time-to-value |
| Answer community questions | Daily | Build trust |
| Create demo videos | 2x/month | Visual learning |
| Attend/speak at meetups | Monthly | Awareness |
| Monitor Reddit/HN/Twitter | Daily | Sentiment tracking |

**DevRel success metrics:**
- Tutorial completion rate
- Time from first visit → first `docker compose up`
- Community question response time
- Social media engagement rate

### 7️⃣ Developer Advocacy / Ambassador Program

```markdown
## Ambassador Tiers
1. **Contributor** — 1+ merged PRs → Listed in CONTRIBUTORS.md
2. **Advocate** — 3+ contributions + 1 blog/talk → Asgard swag
3. **Champion** — Ongoing contributions + community leadership → Early access + advisory role

## Ambassador Benefits
- Early access to new features
- Direct communication with core team
- Co-branding opportunities
- Referral commission (Enterprise leads)
```

### 8️⃣ Documentation-as-Marketing

Great docs drive organic traffic and reduce support burden:

| Doc Type | SEO Target | Example |
|----------|-----------|---------|
| Quick Start | "self-hosted AI setup" | 15-minute guide |
| Architecture | "local LLM gateway design" | System overview |
| Comparison | "Dify vs self-hosted AI" | Feature matrix |
| FAQ | Long-tail keywords | Common questions |

Link to `content-marketing` skill for full content framework.

### 9️⃣ Output
Write to `docs/business/community-strategy.md`

---

## Key Principles
- Respond to every issue and PR — even just to acknowledge
- Make first contribution easy — "good first issue" labels
- Celebrate contributors — shoutouts, CONTRIBUTORS.md
- Be transparent about decisions (ADRs)
- Documentation IS marketing for developer tools

## When to Use
Before public launch, setting up community infra, quarterly community review, or planning events.
