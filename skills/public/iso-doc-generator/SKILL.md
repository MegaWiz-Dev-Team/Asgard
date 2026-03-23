---
name: iso-doc-generator
description: Use this skill to generate or update ISO 29110 compliance documents (SI-02, PM-02, SI-04, PM-01). Trigger when asked to create release documentation, update sprint records, or prepare audit-ready compliance artifacts.
version: "1.0"
author: asgard-team
tags: [iso, documentation, compliance, ISO-29110, audit]
tools: [mimir_search, fenrir_execute]
---

# ISO Document Generator

## Overview
Generate and maintain ISO 29110 compliance documents for the Asgard ecosystem. Ensures all sprint deliverables have proper traceability, test evidence, and release documentation.

## When to Use
- Sprint closing — generate SI-02 (Test Report), PM-02 (Meeting Minutes), SI-04 (Release Notes)
- Release tagging — update PM-01 (Project Plan/Roadmap)
- Audit preparation — verify document completeness
- New service onboarding — create initial ISO document set

## Document Templates

### SI-02: Software Test Report
- Test scope and coverage
- Test results (pass/fail counts)
- Defects found and resolution status
- Forseti integration evidence

### PM-02: Meeting/Sprint Review Minutes
- Sprint goals and outcomes
- Completed vs deferred items
- Decisions and action items
- Next sprint preview

### SI-04: Release Notes
- Version number and tag
- Changes included (features, fixes, security)
- Breaking changes
- Deployment instructions

## Instructions
1. **Identify document type** — determine which ISO document is needed
2. **Gather sprint data** — collect completed tasks, test results, decisions
3. **Apply template** — use the appropriate template structure above
4. **Cross-reference** — ensure traceability between documents (SI-02 ↔ SI-04 ↔ PM-02)
5. **Output as Markdown** — use standard ISO 29110 section headings

## Quality Bar
- All sections must be complete (no TBD placeholders)
- Test results must include actual counts, not estimates
- Version numbers must follow semver
- Dates must be ISO 8601 format
