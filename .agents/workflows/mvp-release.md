---
description: Define MVP scope, success criteria, and launch checklist for a release
---

# MVP & Release Planning

## When to use
- Defining the scope for a new version release
- Cutting scope when behind schedule
- Planning a Community Edition or Enterprise Edition launch
- sprint-to-release transition

## Steps

1. **Define the release goal** (one sentence):
   - Example: "Anyone can `docker compose up` and have a working AI platform with RAG in 15 minutes"

2. **List all candidate features**:
   - Pull from `docs/strategy/gap-mapping.md`
   - Pull from `docs/strategy/platform-review.md` roadmap
   - Pull from repo issue trackers

3. **Prioritize using MoSCoW**:
   | Priority | Meaning | Rule |
   |:--|:--|:--|
   | **Must** | Release is broken without it | Max 40% of effort |
   | **Should** | Important but can workaround | Max 30% of effort |
   | **Could** | Nice to have | Max 20% of effort |
   | **Won't** | Explicitly out of scope | Document why |

4. **Define "Done" criteria** for each Must-have:
   ```
   Feature: Unified Docker Compose
   - [ ] Single docker-compose.yml starts all services
   - [ ] .env.example with all required variables
   - [ ] Health check passes for all services
   - [ ] Quick Start guide tested on clean Mac
   ```

5. **Create launch checklist** in `docs/releases/vX.Y.Z-checklist.md`:
   ```
   # v1.0.0 Community Launch Checklist

   ## Code
   - [ ] All Must-have features merged
   - [ ] All tests passing
   - [ ] Docker images built and tested

   ## Documentation
   - [ ] README updated
   - [ ] Quick Start guide complete
   - [ ] API documentation published
   - [ ] asgardai.dev landing page live

   ## Launch
   - [ ] GitHub release created with changelog
   - [ ] Product Hunt post prepared
   - [ ] HackerNews post drafted
   - [ ] Twitter/LinkedIn announcement ready
   - [ ] Blog post published

   ## Post-Launch
   - [ ] Monitor GitHub issues for first 48 hours
   - [ ] Respond to all community questions
   - [ ] Collect feedback for v1.1 planning
   ```

## Key principles
- "If in doubt, cut it out" — MVP means Minimum
- Ship early, iterate fast
- Every Must-have must have a clear Done criteria
- Won't items are just as important to document as Must items
