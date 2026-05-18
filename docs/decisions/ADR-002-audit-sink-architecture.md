# ADR-002: Audit Sink Architecture for Asgard-Underwriter

**Status:** Accepted
**Date:** 2026-05-17
**Deciders:** paripol@megawiz.co
**Context for:** Asgard-Underwriter v2.2.1 → v3.0 Phase A.2 — Tyr audit integration
**Related:** [ADR-001](ADR-001-database-choice.md), [feedback_include_tyr_in_pii_designs memory](memory)

## Context

The Asgard platform has a hard rule (recorded as `feedback_include_tyr_in_pii_designs`): any PII/medical/external-doc/regulated-decision workflow must include Tyr as a **first-class** detection and audit layer — not an afterthought.

Asgard-Underwriter handles PHI from insurance applicants every time a case is created. Without an audit trail, the system cannot pass PDPA or HIPAA-equivalent compliance reviews. Current v2.2.1 has zero audit logging — this is a compliance blocker, not a nice-to-have.

The complication: **Tyr (Wazuh-based SIEM) is currently scaled down** (per [tyr_wazuh_scaled_down memory](memory)). The full Wazuh deployment is not always available. We cannot let audit functionality depend on Tyr being up — that would block production.

We need an audit architecture that:
1. **Always logs**, even when Tyr is down
2. **Tamper-evident** — modifying past entries must be detectable
3. **Pluggable sinks** — can target local DB, Wazuh, or both
4. **Forward-compatible** — when Tyr scales back up, no code change required, just config

## Decision

**Implement audit as a Rust trait with multiple sink implementations.** Underwriter writes audit events through a sink trait. Default config: LocalDbSink + Wazuh stub fan-out.

```rust
#[async_trait]
pub trait AuditSink: Send + Sync {
    async fn emit(&self, event: AuditEvent) -> Result<()>;
}

pub struct LocalDbSink { pool: MariaDbPool }
pub struct TyrWazuhSink { client: WazuhClient }  // stub until Tyr scales up
pub struct FanoutSink { sinks: Vec<Arc<dyn AuditSink>> }
```

**Default deployment configuration:**

```
AUDIT_SINK=fanout
AUDIT_FANOUT=local,wazuh-stub
```

- `LocalDbSink` writes to MariaDB `audit_events` table (per ADR-001)
- `TyrWazuhSink` POSTs to Wazuh HTTP receiver endpoint (or no-ops if endpoint not configured)
- `FanoutSink` writes to both — local always succeeds, Wazuh failure is logged but does not fail the request

**Tamper-evidence via hash chain.** Each `audit_events` row has:

- `event_id` UUID
- `prev_event_hash` SHA-256 of previous event row (per actor or globally — see implementation note)
- `event_hash` SHA-256 of (this event's content || prev_event_hash)

Modifying any past event breaks the chain. A verifier job (`scripts/verify_audit_chain.sh`) walks the chain and reports the first broken link.

## Alternatives Considered

### 1. Direct Tyr/Wazuh integration only (rejected)

- Single sink, simpler code

**Why rejected:**
- Tyr is scaled down; depending on it would mean audit failures during downtime
- Tightly couples Underwriter to Wazuh's deployment lifecycle
- Underwriter must work standalone on a customer Mac mini even if customer never scales up Wazuh

### 2. Local-only sink, defer Tyr forever (rejected)

- Write only to MariaDB; never touch Wazuh

**Why rejected:**
- Memory rule says Tyr must be first-class, not deferred indefinitely
- Building Wazuh integration later means revisiting every event-emission call site
- Stub now is cheap; integration later via config flip is the right pattern

### 3. Append-only log file (rejected)

- Write JSON lines to a rotated log file; cron-ship to S3 / Wazuh / etc.

**Why rejected:**
- File-based logs are easy to rotate and lose
- No query API for audit lookups during incident response
- Hash chain enforcement is awkward across rotated files
- MariaDB row-level approach gives us SQL queries + ACID transactions for free

### 4. Postgres-native audit (rejected — for now)

- Postgres triggers + JSONB for richer semantics

**Why rejected:**
- Conflicts with ADR-001 (MariaDB first)
- Can revisit when/if Postgres switch happens

### 5. Trust the application — no audit (rejected)

- Skip audit entirely

**Why rejected:**
- Violates compliance hard rule
- Memory `feedback_include_tyr_in_pii_designs` says first-class, non-negotiable

## Consequences

### Positive

- **Always-on audit** — local sink works without external dependencies
- **Forward path to Tyr** — config flip, no code change
- **Tamper-evident** — hash chain detects retroactive modification
- **Per-deployment** — fits on-prem appliance model from [ADR-009](ADR-009-single-tenant-mac-mini-deployment.md)
- **Reusable** — the trait + sinks also serve PrimeKG/Mega Care workstream (Phase 5 audit) without rewrite

### Negative

- **Hash chain in app code** (not Postgres trigger) — see ADR-001 trade-offs
- **Wazuh stub** is a stub; integration tests with real Wazuh are deferred until Tyr scales
- **Storage growth** — audit_events table grows monotonically; need retention runbook (probably ship rotation to cold storage after N days)
- **Performance overhead** — every write path emits an event; ~1 extra DB row per case operation. Acceptable at expected scale.

### Risks

- **Hash chain bug ships with no detection** — if hash computation has a bug, all rows are technically valid but verification would fail. Mitigation: unit-test chain construction + verify on every CI run
- **Wazuh schema drift** — when Tyr scales up, Wazuh expectations may have evolved. Mitigation: stub format follows current Wazuh JSON spec, adapter updates on integration

## Implementation Notes

### Critical events that MUST emit (Phase A.2 minimum)

| # | Event | Trigger |
|---|---|---|
| 1 | `case.created` | New case via `POST /api/v1/cases` |
| 2 | `case.modified` | Case fields updated |
| 3 | `case.deleted` | Case removed |
| 4 | `file.uploaded` | New file attached, includes file hash |
| 5 | `file.downloaded` | File retrieved (data exfiltration trail) |
| 6 | `extraction.completed` | OCR + structured extraction finished |
| 7 | `pii.detected` | Skuggi PII hit |
| 8 | `manual_review.escalated` | Extraction → HITL queue |
| 9 | `hitl.assigned` | Queue item assigned to reviewer |
| 10 | `hitl.decision` | Reviewer accept/reject/modify |
| 11 | `assessment.decided` | Final risk score assigned |
| 12 | `pdf.exported` | Case report PDF generated |
| 13 | `auth.success` / `auth.failure` | Once JWT lands (Phase A.3) |

### Event schema

```rust
pub struct AuditEvent {
    pub event_id: Uuid,
    pub ts: DateTime<Utc>,
    pub actor: Actor,               // tenant_id + user_id + source_ip
    pub action: String,             // dotted lowercase, e.g. "case.created"
    pub resource: ResourceRef,      // type + id, e.g. ("case", "c_a1b2...")
    pub severity: Severity,         // info / notice / warning / critical
    pub before: Option<JsonValue>,  // hash of pre-state (NOT raw — PHI safety)
    pub after: Option<JsonValue>,   // hash of post-state
    pub metadata: JsonValue,        // event-specific extras
    pub prev_event_hash: [u8; 32],
    pub event_hash: [u8; 32],
}
```

### Hash chain scope

Two reasonable choices:
- **Global chain** — one chain across all events. Simple, but every write contends on tail
- **Per-actor chain** — chain segmented by actor (user). No contention; but actor switching obscures cross-actor correlation

**Decision:** start with **global chain** for v3.0. If contention shows up in load tests (Phase D.2), partition to per-table or per-actor. The verifier supports both.

### Wazuh stub specifics

```rust
impl AuditSink for TyrWazuhSink {
    async fn emit(&self, event: AuditEvent) -> Result<()> {
        if self.client.endpoint.is_none() {
            return Ok(());  // no-op, stub mode
        }
        // POST to Wazuh HTTP receiver, fire-and-forget with bounded retry
        // Body: Wazuh-compatible JSON envelope around AuditEvent
    }
}
```

### Retention policy (out of scope for v3.0)

- Default: keep all events forever locally
- Future: configurable retention window + cold-storage shipping
- Compliance: must comply with both PDPA (Thai) and any sector-specific rules; document per customer

## Validation

This decision is validated when:

- [ ] `AuditSink` trait defined + 3 impls (LocalDbSink, TyrWazuhSink, FanoutSink)
- [ ] All 13 critical events emit through the sink in normal flow
- [ ] `verify_audit_chain.sh` walks the chain and reports OK on a clean run
- [ ] Tamper test passes: manually UPDATE a row → verifier reports broken link with row number
- [ ] Wazuh stub: when endpoint unconfigured, all emits succeed and no errors logged
- [ ] Wazuh stub: when endpoint configured but unreachable, local sink still succeeds, Wazuh failure is logged at WARN, no request failure propagates

## References

- [feedback_include_tyr_in_pii_designs memory](memory)
- [tyr_wazuh_scaled_down memory](memory)
- [asgard_tyr_siem memory](memory) — Tyr architecture
- [ADR-001](ADR-001-database-choice.md) — MariaDB foundation
- [ADR-009](ADR-009-single-tenant-mac-mini-deployment.md) — per-deployment audit, no cross-box SIEM
