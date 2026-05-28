# Agent Groups Management System

**Version:** 1.0.0  
**Date:** 2026-05-28  
**Status:** Production Ready

---

## Overview

Agent Groups is a **hierarchical management system** for organizing AI agents by category within Asgard Medical platform. Supports flexible grouping, custom naming, and multi-tenant deployment.

### Key Features

✅ **Hierarchical Grouping** — Organize agents by role/boundary  
✅ **Editable Names** — Change group names without code changes  
✅ **Add Groups Anytime** — Extend with new categories on-demand  
✅ **Multi-Tenant** — Each tenant customizes own group structure  
✅ **UI Integration** — Display order, icons, colors for Agent Studio  
✅ **Soft-Delete** — Archive groups without data loss  

---

## Schema

### agent_groups Table

```sql
CREATE TABLE agent_groups (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  tenant_id VARCHAR(50) NOT NULL,
  name VARCHAR(100) NOT NULL,          -- Unique slug (e.g., "boundary-agents")
  display_name VARCHAR(200),           -- UI display (e.g., "🏛️ Boundary Agents")
  description TEXT,                    -- Purpose & scope
  sort_order INT DEFAULT 0,            -- Display order (1, 2, 3, ...)
  icon_emoji VARCHAR(10),              -- 🏛️, 🩺, 🎯, 🧪, etc
  color_hex VARCHAR(7),                -- #7C3AED, #10B981, etc
  is_active TINYINT(1) DEFAULT 1,     -- Soft-delete flag
  created_at TIMESTAMP,
  updated_at TIMESTAMP,

  UNIQUE KEY (tenant_id, name),
  KEY (tenant_id, is_active),
  KEY (tenant_id, sort_order)
);

-- Link to agents
ALTER TABLE agent_configs
ADD COLUMN agent_group_id BIGINT DEFAULT NULL;
```

---

## Standard Groups (All Tenants)

### 🏛️ Boundary Agents (sort_order=1)

**Purpose:** Trust & policy enforcement  
**Color:** #7C3AED (Purple)

**asgard_medical (5 agents):**
- `eir-clinical` — General diagnosis host
- `eir-pharmacy` — DDI safety gate (MANDATORY)
- `eir-pediatrics` — Age-safe dosing
- `eir-psychiatry` — Safety floor (hard-refuse)
- `eir-emergency` — Fast latency ≤2s

**asgard_insurance (4 agents):**
- `underwriter-risk-assessor`
- `underwriter-medical-analyzer`
- `underwriter-fraud-detector`
- `underwriter-decision-maker`

---

### 🩺 Specialty Agents (sort_order=2)

**Purpose:** Clinical expertise (future: composable skills)  
**Color:** #10B981 (Green)

**asgard_medical (14 agents):**
- `eir-internal-medicine`, `eir-surgery`, `eir-ophthalmology`, `eir-orthopedics`
- `eir-ob-gyn`, `eir-radiology`, `eir-medtech`, `eir-nursing`
- `eir-pt`, `eir-dietitian`, `eir-social-work`, `eir-anesthesia`
- `eir-ent`, `eir-urology`

**asgard_insurance (3 agents):**
- `eir-internal-medicine` (read-only)
- `eir-medtech` (read-only)
- `eir-pharmacy` (read-only)

---

### 🎯 Router & Orchestration (sort_order=3)

**Purpose:** Request routing & specialty classification  
**Color:** #F59E0B (Amber)

**All tenants:**
- `eir-router` — LLM-driven classifier (deprecated per ADR-010)
- `bifrost-router` — Deterministic signal-based gate (proposed)

---

### 🧪 Test Agents (sort_order=99)

**Purpose:** QA, development, verification  
**Color:** #EF4444 (Red)

**All tenants:**
- `test-*`, `dev-*` agents

---

## API Usage

### List Groups (by Tenant)

```bash
curl -H "X-Tenant-Id: asgard_medical" \
  http://localhost:8090/api/v1/agent-groups
```

**Response:**
```json
{
  "groups": [
    {
      "id": 1,
      "name": "boundary-agents",
      "display_name": "🏛️ Boundary Agents",
      "sort_order": 1,
      "icon_emoji": "🏛️",
      "color_hex": "#7C3AED",
      "agent_count": 5,
      "agents": ["eir-clinical", "eir-pharmacy", ...]
    },
    ...
  ]
}
```

### Create New Group

```bash
curl -X POST -H "X-Tenant-Id: asgard_medical" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "training-agents",
    "display_name": "🎓 Training & Demo",
    "description": "Demo agents for training sessions",
    "sort_order": 4,
    "icon_emoji": "🎓",
    "color_hex": "#3B82F6"
  }' \
  http://localhost:8090/api/v1/agent-groups
```

### Update Group (Rename)

```bash
curl -X PATCH -H "X-Tenant-Id: asgard_medical" \
  -H "Content-Type: application/json" \
  -d '{
    "display_name": "🏥 Core Clinical Agents",
    "description": "Updated description"
  }' \
  http://localhost:8090/api/v1/agent-groups/1
```

### Add Agent to Group

```bash
curl -X POST -H "X-Tenant-Id: asgard_medical" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_group_id": 1
  }' \
  http://localhost:8090/api/v1/agents/eir-clinical
```

### List Agents by Group

```sql
SELECT
  ag.display_name as 'Group',
  ac.name, ac.display_name, ac.model_id, ac.agent_version
FROM agent_configs ac
LEFT JOIN agent_groups ag ON ac.agent_group_id = ag.id
WHERE ac.tenant_id = 'asgard_medical'
ORDER BY ag.sort_order, ac.name;
```

---

## Customization Examples

### Example 1: Add "Pediatric Specialists" Group

```sql
INSERT INTO agent_groups (
  tenant_id, name, display_name, description, sort_order, icon_emoji, color_hex
) VALUES (
  'asgard_medical', 'pediatric-specialists', '👶 Pediatric Specialists',
  'Child health specialists and pediatric-aware agents', 2.5, '👶', '#EC4899'
);

-- Then reassign agents:
UPDATE agent_configs
SET agent_group_id = (
  SELECT id FROM agent_groups
  WHERE tenant_id='asgard_medical' AND name='pediatric-specialists'
)
WHERE tenant_id='asgard_medical' AND name IN ('eir-pediatrics', 'eir-nursing');
```

### Example 2: Archive Old "legacy-agents" Group

```sql
UPDATE agent_groups
SET is_active = 0, updated_at = CURRENT_TIMESTAMP
WHERE tenant_id='asgard_medical' AND name='legacy-agents';

-- Agents stay in DB but group won't display in UI
```

### Example 3: Custom Tenant Grouping (asgard_insurance)

```sql
-- Insurance uses same standard groups + custom "Underwriter Bureau"
INSERT INTO agent_groups (
  tenant_id, name, display_name, sort_order, icon_emoji, color_hex
) VALUES (
  'asgard_insurance', 'underwriter-bureau', '🏢 Underwriter Bureau',
  0.5, '🏢', '#1F2937'
);

-- Place underwriter consensus agents in this group
UPDATE agent_configs
SET agent_group_id = (SELECT id FROM agent_groups 
                     WHERE tenant_id='asgard_insurance' AND name='underwriter-bureau')
WHERE tenant_id='asgard_insurance' AND name LIKE 'underwriter-%';
```

---

## Migration Strategy

### For Existing Deployments

```bash
# Step 1: Backup agent_configs
mysqldump mimir agent_configs > agent_configs_backup.sql

# Step 2: Apply schema migration
mysql mimir < migrations/20260528400000_create_agent_groups_table.sql

# Step 3: Seed standard groups
mysql mimir < migrations/20260528410000_seed_agent_groups_all_tenants.sql

# Step 4: Verify
SELECT COUNT(*) FROM agent_groups WHERE tenant_id='asgard_medical';
-- Expected: 4 groups (boundary, specialty, router, test)

SELECT COUNT(*) FROM agent_configs 
WHERE tenant_id='asgard_medical' AND agent_group_id IS NOT NULL;
-- Expected: 21 agents (all assigned to groups)
```

---

## Soft-Delete & Recovery

### Archive a Group

```sql
UPDATE agent_groups
SET is_active = 0
WHERE tenant_id='asgard_medical' AND name='old-group';
```

### Query Only Active Groups

```sql
SELECT * FROM agent_groups
WHERE tenant_id='asgard_medical' AND is_active = 1
ORDER BY sort_order;
```

### Recover Archived Group

```sql
UPDATE agent_groups
SET is_active = 1, updated_at = CURRENT_TIMESTAMP
WHERE tenant_id='asgard_medical' AND name='old-group';
```

---

## Audit & Monitoring

### Track Group Changes

```sql
-- Last 10 group changes
SELECT
  id, tenant_id, name, display_name, updated_at
FROM agent_groups
WHERE tenant_id='asgard_medical'
ORDER BY updated_at DESC
LIMIT 10;
```

### Agent Assignment Audit

```sql
-- Agents missing group assignment
SELECT
  id, name, display_name, tenant_id
FROM agent_configs
WHERE tenant_id='asgard_medical' AND agent_group_id IS NULL;

-- Should be empty (all agents assigned)
```

---

## Future Enhancements

### Planned (Sprint 57+)

- [ ] **Nested Groups** — Sub-categories within groups (e.g., "Boundary Agents" → "Safety Floor" + "DDI Gate")
- [ ] **Group Permissions** — RBAC per group (admin can configure pediatric agents only)
- [ ] **Group Templates** — Pre-built group configurations for tenant onboarding
- [ ] **Dynamic Grouping** — Tag-based groups (search: `label:pediatric-aware`)
- [ ] **Group Metrics** — Avg latency, success rate per group
- [ ] **Version History** — Audit trail of group changes (timestamp + user)

---

## FAQ

**Q: Can I rename a group?**  
A: Yes. Update `display_name` without changing `name` (the slug stays for internal refs).

**Q: What if I add an agent after group creation?**  
A: Assign it manually via `UPDATE agent_configs SET agent_group_id = X`.

**Q: Can tenants have different group structures?**  
A: Yes. asgard_medical and asgard_insurance can have completely different groups.

**Q: How do I migrate agents between groups?**  
A: `UPDATE agent_configs SET agent_group_id = new_group_id WHERE ...`

**Q: What happens if I delete a group?**  
A: Use soft-delete (`is_active = 0`) instead. Hard-delete will NULL agent_group_ids (cascading).

---

## References

- [Asgard Medical AI Agent Specification](asgard-medical-ai-agent-specification.md) — Agent roster & versioning
- [Agent Studio Documentation](agent-studio.md) — UI integration
- [Deployment Runbook](customer-deployment-runbook.md) — Group setup per tenant
