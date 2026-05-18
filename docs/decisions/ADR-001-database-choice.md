# ADR-001: Database Choice for Asgard-Underwriter Persistence

**Status:** Accepted
**Date:** 2026-05-17
**Deciders:** paripol@megawiz.co
**Context for:** Asgard-Underwriter v2.2.1 → v3.0 Phase A.1 — DB persistence
**Supersedes:** none
**Superseded by:** none

## Context

Asgard-Underwriter v2.2.1 currently stores all case data, file metadata, chat sessions, HITL queue, and audit events in an in-memory `HashMap` within `iris/src/main.rs`. This blocks production deployment for any customer:

- Case data lost on restart
- "Persistent chat sessions" (per RELEASE_NOTES) are not actually persistent
- HITL queue cannot survive a process crash
- No audit trail for compliance (HIPAA/PDPA)
- Cannot scale beyond a single process (though scaling is not a near-term goal given 1-Mac-mini-per-customer deployment)

We need a real database. The Asgard stack already runs MariaDB and Postgres in K8s (`asgard-infra` namespace, per [memory](memory)). The decision is which to use for Underwriter — and whether to consider this a forcing function to consolidate the platform onto one database.

## Decision

**Use MariaDB** as the primary database for Asgard-Underwriter.

- Connection via `sqlx` with compile-time checked queries
- Migrations via `sqlx-migrate`
- One database per Underwriter deployment (since 1 Mac mini = 1 customer, no shared DB)
- Schema lives in `iris/migrations/`

We do **not** migrate the wider Asgard stack to Postgres at this time, even though Postgres has clear advantages for Underwriter-specific workloads (audit hash chain, JSONB policy metadata, pgvector for similarity dedup).

## Alternatives Considered

### 1. PostgreSQL (rejected for now, kept as future option)

**Advantages for Underwriter specifically:**
- `audit_events` hash chain — Postgres triggers + JSONB make this cleaner
- Dedup similarity ≥0.95 — pgvector ships in-DB instead of round-tripping to Mimir/Qdrant
- Policy metadata JSONB query — per-insurer schema flexibility without table-per-insurer
- Better text search for chat history (full-text + trigram indexes)
- Better Rust ecosystem alignment (sqlx, sea-orm both treat Postgres as primary target)

**Why rejected (for now):**
- Bifrost stack uses MariaDB (`agent_configs` table per [asgard_agent_registry memory](memory)); Sprint 51e rotation of MariaDB just completed (per [rotation memory](memory))
- Per-customer Postgres adds operational complexity to Mac-mini installs (one more daemon to manage, backup, monitor)
- Platform-wide migration is too large to attempt while juggling S1 RefGraph (May 19-28 + June 2-11)
- Underwriter Phase A.1 needs to ship before optimizing for Postgres-specific features

**Future trigger:** if benchmark shows audit hash chain or dedup similarity is a real bottleneck on MariaDB, revisit per-component switch.

### 2. SQLite (rejected)

- Excellent for single-process per-Mac-mini deployment
- File-based, trivial backup
- Zero ops complexity

**Why rejected:**
- Concurrent write scaling poor (WAL helps but not enough for HITL + audit + case write churn)
- Tooling around audit trail, retention, and Tyr export is heavier for SQLite (no standard tools)
- Less production-tested for healthcare-adjacent workloads
- Migration path to MariaDB/Postgres later is non-trivial (SQL dialect divergence)

### 3. Keep HashMap + periodic snapshot to disk (rejected)

- Zero migration effort
- Predictable performance

**Why rejected:**
- Doesn't solve any of the actual problems (audit, multi-process survival, transactional consistency)
- Sunk-cost trap — would have to migrate later anyway
- Cannot pass PDPA/HIPAA audit requirements

### 4. sled / RocksDB embedded KV (rejected)

- Rust-native, no external service
- Fast

**Why rejected:**
- Not SQL — every query becomes manual code
- No standard reporting tooling
- Schema migrations become application-level concerns
- Wrong abstraction level for relational data (cases ↔ files ↔ extractions ↔ HITL)

## Consequences

### Positive

- **Stack consistency:** MariaDB is already the transactional DB in Asgard (Bifrost `agent_configs`); ops team already knows it
- **Per-customer simplicity:** each Mac mini runs one MariaDB instance, no Postgres-MariaDB dual operate
- **Rotation tested:** MariaDB rotation just passed in Sprint 51e (May 11) — mature operational pattern
- **Backup story:** `mysqldump` + binlog established
- **Skill match:** developer (paripol) already familiar with MariaDB from existing Asgard work

### Negative

- **JSONB pain:** MariaDB JSON support is workable but weaker than Postgres JSONB; policy metadata queries will need more application-side filtering
- **No pgvector:** dedup similarity calculation must round-trip to Mimir/Qdrant for vector ops; adds latency to S2 multi-insurer dedup workflow
- **Hash chain awkwardness:** audit chain integrity needs application-level enforcement (vs Postgres triggers); see [ADR-002](ADR-002-audit-sink-architecture.md) for compensating design
- **Future migration cost:** if a future customer or workload mandates Postgres, per-component switching is workable but not free

### Risks accepted

- Cannot leverage pgvector for in-DB similarity → must keep Qdrant in the loop for dedup
- JSON column queries will be slower than equivalent Postgres JSONB queries
- If Postgres-specific features become required later, switch effort is ~1 sprint per affected component

## Implementation Notes

### Schema scope (10 tables for v3.0)

```
cases               case_id, tenant_id, insurer_id, status, risk_score, ...
case_files          file_id, case_id, file_hash, file_type, ocr_status, ...
extractions         extraction_id, case_id, file_id, raw_text, structured_json, ...
diagnoses           id, case_id, icd10_code, source_extraction_id
medications         id, case_id, drug_name, dose, frequency, source_extraction_id
hitl_queue          queue_id, case_id, assignee, sla_deadline, escalation_level, ...
chat_sessions       session_id, case_id, created_at, updated_at
chat_messages       message_id, session_id, role, content, timestamp
audit_events        event_id, actor, action, resource, before_hash, after_hash, ts
pii_detections      detection_id, case_id, file_id, pii_type, bbox, redacted, ts
```

### Library choices

- **sqlx 0.7+** — compile-time SQL verification, no ORM overhead, async-native
- **sqlx-migrate** — file-based migrations with up/down support
- **testcontainers-rs** — spin up real MariaDB for integration tests, no mocks

### Migration discipline

- Every schema change is a numbered migration file (`migrations/0001_initial.sql`, `0002_audit_hash_chain.sql`, ...)
- Migrations are idempotent (re-runnable)
- Down migrations required for all up migrations (rollback discipline)
- CI fails if migrations don't apply cleanly on a blank DB

## Validation

This decision is validated when:

- [ ] sqlx + migrations integrated into iris build
- [ ] 10 tables defined with FK + indexes
- [ ] testcontainers integration test passes on clean DB
- [ ] All 159 existing backend tests pass with DB-backed services
- [ ] All 10 E2E tests pass with DB-backed services
- [ ] Restart server → case data, chat history, HITL queue, audit log all preserved

## References

- [Asgard stack in OrbStack K8s memory](memory)
- [Sprint 51e rotation status memory](memory) — MariaDB recently rotated
- [underwriter_v3_plan_decisions memory](memory) — MariaDB locked 2026-05-17
- [Asgard-Underwriter v2.2.1 codebase audit](../sprint_tracker_2026_05_17.md)
