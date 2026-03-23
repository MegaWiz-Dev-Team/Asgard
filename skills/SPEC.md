# Asgard Skills Format Specification

> Compatible with [DeerFlow](https://github.com/bytedance/deer-flow) ecosystem

## Directory Structure

```
Asgard/skills/
├── SPEC.md              ← This file
├── public/              ← Built-in skills shipped with Asgard
│   ├── medical-research/SKILL.md
│   ├── patient-summary/SKILL.md
│   ├── iso-doc-generator/SKILL.md
│   ├── security-audit/SKILL.md
│   └── deployment/SKILL.md
└── custom/              ← Tenant/user-created skills
    └── your-skill/SKILL.md
```

## SKILL.md Format

Each skill is a **Markdown file** with **YAML frontmatter**:

```yaml
---
name: skill-name              # REQUIRED — unique identifier (kebab-case)
description: >                # REQUIRED — when to trigger this skill
  Natural language description used by the agent router
  to decide when to load this skill.
version: "1.0"                # optional — semver
author: asgard-team           # optional
tags: [tag1, tag2]            # optional — used for relevance matching
tools: [mcp_tool_1, tool_2]   # optional — MCP tools this skill needs
---

# Skill Name

## Overview
What this skill does and when to use it.

## Instructions
Step-by-step workflow the agent should follow.

## Quality Bar
Expected output quality criteria.
```

### Required Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Unique skill identifier (kebab-case) |
| `description` | string | Trigger description for progressive loading |

### Optional Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `version` | string | `""` | Semantic version |
| `author` | string | `""` | Skill author |
| `tags` | list | `[]` | Keywords for relevance matching |
| `tools` | list | `[]` | Required MCP tools |

## Progressive Loading

Skills are **NOT** loaded all at once. The `SkillsLoader` matches the current task description against skill `description` and `tags` fields, and injects only relevant skills into the agent's system prompt as:

```xml
<skills>
<skill name="skill-name">
[markdown content]
</skill>
</skills>
```

This keeps the context window lean and works well with token-sensitive models.

## Creating Custom Skills

1. Create a directory under `skills/custom/your-skill-name/`
2. Add a `SKILL.md` file following the format above
3. The skill will be auto-discovered on next scan
