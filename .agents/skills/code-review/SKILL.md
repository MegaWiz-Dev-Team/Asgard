---
name: code-review
description: "Conduct structured code reviews for Rust, Python, and TypeScript codebases. PR standards, language-specific checklists, and cross-component impact analysis."
---

# Code Review

> "Code review is about improving the code AND the coder."

## Purpose

Ensure consistent, high-quality code reviews across Asgard's multi-language codebase (Rust, Python, TypeScript). Catch bugs early, share knowledge, and maintain standards.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/architecture.md` | Understand component boundaries |
| `CONTRIBUTING.md` | Contribution guidelines |

---

## Process

### 1️⃣ PR Description Template

Every PR must include:
```markdown
## What
[One-sentence summary]

## Why
[Problem being solved or feature being added]

## How
[Brief technical approach]

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Manual testing done (describe)

## Impact
- [ ] Breaking change? (describe migration)
- [ ] Affects other components? (list them)
- [ ] Database migration needed?
```

### 2️⃣ Rust Review Checklist (Heimdall, Mimir, Eir, Vardr)

```markdown
## Correctness
- [ ] No unwrap() in production paths — use ? or proper error handling
- [ ] Error types are meaningful (not generic anyhow)
- [ ] Ownership model is correct — no unnecessary Clone
- [ ] No unsafe blocks (or thoroughly justified)

## Performance
- [ ] No blocking calls in async context
- [ ] Arc/Mutex used appropriately for shared state
- [ ] Database queries optimized (no N+1)
- [ ] Response streaming where appropriate

## Axum-Specific
- [ ] Error responses use consistent JSON format
- [ ] Extractors ordered correctly (body last)
- [ ] State properly shared via Extension/State
- [ ] Routes follow RESTful conventions

## Dependencies
- [ ] New crates justified and reviewed for security
- [ ] License compatible with AGPL-3.0
- [ ] cargo clippy passes with no warnings
- [ ] cargo audit clean
```

### 3️⃣ Python Review Checklist (Bifrost, Fenrir, Yggdrasil)

```markdown
## Correctness
- [ ] Type hints on all function signatures
- [ ] async/await used correctly (no blocking in async)
- [ ] Exception handling is specific (not bare except)
- [ ] Pydantic models for request/response validation

## Style
- [ ] Follows existing project patterns
- [ ] Docstrings on public functions
- [ ] No hardcoded values — use config/env vars
- [ ] Logging at appropriate levels (debug/info/warning/error)

## FastAPI-Specific
- [ ] Router prefix and tags consistent
- [ ] Response models defined
- [ ] Dependency injection used for shared resources
- [ ] Background tasks for async operations
```

### 4️⃣ TypeScript/Next.js Review Checklist (Mimir Dashboard)

```markdown
## Correctness
- [ ] TypeScript strict mode compliance
- [ ] No any types (use proper typing)
- [ ] Server vs client components correctly categorized
- [ ] API routes handle errors gracefully

## UI/UX
- [ ] Loading states for async operations
- [ ] Error boundaries for component failures
- [ ] Responsive design verified
- [ ] Accessibility basics (labels, alt text, keyboard nav)
```

### 5️⃣ Cross-Component Impact

When a PR touches APIs or shared contracts:
1. Identify all consumers of the changed API
2. Check backward compatibility
3. If breaking: document migration path
4. Update OpenAPI spec if applicable

### 6️⃣ Review Response Protocol

| Severity | Prefix | Action |
|----------|--------|--------|
| Must fix | `🔴 BLOCKER:` | Cannot merge until resolved |
| Should fix | `🟡 SUGGESTION:` | Improve but not blocking |
| Nit | `🟢 NIT:` | Style preference, optional |
| Question | `❓ QUESTION:` | Need clarification |
| Praise | `✨ NICE:` | Positive reinforcement |

---

## Key Principles
- Review the design, not just the code
- Be kind — critique the code, not the person
- "Approve with comments" for nits only
- Self-review before requesting others

## When to Use
Every PR, during sprint retrospectives to improve review quality, or when onboarding new contributors.
