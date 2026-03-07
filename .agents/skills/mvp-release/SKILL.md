---
name: mvp-release
description: "Define MVP scope, success criteria, MoSCoW prioritization, and launch checklist for a release."
---

# MVP & Release Planning

> "Ship early, iterate fast. Perfect is the enemy of good."

## Purpose

Define clear scope boundaries, success criteria, and launch checklists to ship a release with confidence.

---

## Process

### 1️⃣ Define the Release Goal (one sentence)
Example: "Anyone can `docker compose up` and have a working AI platform with RAG in 15 minutes"

### 2️⃣ Gather Candidates
- Pull from `docs/strategy/gap-mapping.md`
- Pull from `docs/strategy/platform-review.md` roadmap
- Pull from repo issue trackers

### 3️⃣ MoSCoW Prioritization
| Priority | Meaning | Budget |
|----------|---------|--------|
| **Must** | Release is broken without it | Max 40% of effort |
| **Should** | Important but workaround exists | Max 30% |
| **Could** | Nice to have | Max 20% |
| **Won't** | Explicitly out of scope this release | Document why |

### 4️⃣ Define "Done" for Each Must-Have
```
Feature: Unified Docker Compose
- [ ] Single docker-compose.yml starts all services
- [ ] .env.example with all required variables
- [ ] Health check passes for all services
- [ ] Quick Start guide tested on clean Mac
```

### 5️⃣ Launch Checklist
```markdown
## Code
- [ ] All Must-have features merged and tested
- [ ] Docker images built and verified

## Documentation
- [ ] README updated with new features
- [ ] Quick Start guide complete
- [ ] API docs published

## Launch
- [ ] GitHub release with changelog
- [ ] Product Hunt / HackerNews post
- [ ] Twitter/LinkedIn announcement
- [ ] Blog post

## Post-Launch (48h)
- [ ] Monitor GitHub issues
- [ ] Respond to all community questions
- [ ] Collect feedback for next release
```

### 6️⃣ Output
Write to `docs/releases/vX.Y.Z-plan.md`

---

## Key Principles
- "If in doubt, cut it out" — MVP means Minimum
- Every Must-have needs clear Done criteria
- Won't items are just as important to document
- Ship, learn, iterate

## When to Use
Before any version release, when cutting scope, or planning Community/Enterprise launch.
