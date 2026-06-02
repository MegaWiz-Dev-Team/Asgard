# Odin Orchestrator — Multi-Agent Security Automation Design

**Status:** DRAFT / blueprint (no prod code beyond Phase 0)
**Author:** design session 2026-06-02 (post Wazuh-MeetUp demo)
**Scope:** Turn Odin from a read-only SOC-analyst dashboard into the supervising
orchestrator of Asgard's security agents (Loki, Tyr, Huginn, Muninn) with safe,
gated write-paths up to GitHub issue/PR automation.

---

## 1. Vision (user's words, restated)

> Odin ปกครองเหล่า multi-agent เทพผู้คุม Asgard:
> - Odin สั่ง **Loki** ทำ red-team เจาะระบบด้วย KALI
> - Odin สั่ง **Tyr** ตรวจ SIEM (Wazuh) alert → ส่ง GitHub issue
> - Odin สั่ง **Huginn** ทำ VA scan ด้วย ZAP → สร้าง GitHub issue
> - Odin สั่ง **Muninn** อ่าน GitHub issue → เรียก Claude Code ทำ PR แก้
> - Odin **list PR** มาให้ review → สั่งแก้/merge เข้า main

This is an **agentic security loop**: detect → triage → fix → verify, with humans
at the dangerous edges.

---

## 2. What EXISTS today (verified 2026-06-02, not assumed)

| Capability | Reality | Evidence |
|---|---|---|
| Odin read tools | ✅ 17 read tools (tyr_search_alerts, huginn_list_scans, muninn_list_issues, loki_list_results, vardr/forseti/mjolnir…) | `Odin/src/agents.rs` |
| Odin auth | ✅ bearer-token middleware on /api/*, random per-startup token, env login | `Odin/src/main.rs` (commit 44fc479) |
| Odin in cluster | ✅ pod runs, reaches services via cluster DNS (`heimdall-host.asgard.svc` etc.), `odin.asgard.internal` via ingress + Tailscale | deployed |
| Huginn scan + issue | ✅ `huginn_start_scan` (ZAP), `findings.rs` already has `github_issues` field | tested: 221 scans, findings 0 |
| Muninn issue→PR | ✅ engine exists: `code_agent_provider`, `fix_mode=review`, `watched_repos` | `/api/config` — but watched_repos=[], code_agent=none (not wired) |
| Loki red-team | ⚠️ HTTP-payload injection tests only (sql/jwt/path…). **No KALI/shell executor exists** | `Loki/api/src/handlers/` |
| Loki guardrails | ⚠️ `guards.rs` exists with allowlist + payload-block + auth, but 3 are placeholders (see §5) | `Loki/api/src/guards.rs` |
| Tyr alert→issue | ❌ not built | — |
| Tyr dedup/noise filter | ❌ not built | grep: none |
| `gh` CLI | ✅ logged in (megacare-dev) on host — but NOT in any pod | — |

**Bottom line:** ~70% of the *pieces* exist. What's missing is the **wiring**,
the **write-tools in Odin**, and the **safety/gate layer** before any write-path
goes live.

---

## 3. Core principle — the 3-power model (separation of duties)

The single most important design decision. Asgard already has the cast — each plays
a distinct, non-overlapping role (verified against existing code, not invented):

```
Odin   = COMMANDER  (LLM, fast/flash)  — decides WHAT to do (human intent → dispatch)
Frigg  = ADVISOR    (LLM, smart/pro)   — decides SHOULD we (review + consensus vote)
Thor   = ENFORCER   (rules, no LLM)    — decides is it ALLOWED (policy gate, deterministic)
agents = HANDS      (Loki/Huginn/Muninn) — actually do it
```

Why three, not one — **defense in depth across *different* failure modes:**
- Odin alone = a commander who signs his own warrants → no brake.
- Add Frigg = a second, *smarter* LLM that catches Odin's mistakes/hallucinations
  — but two LLMs can still be wrong the same way.
- Add Thor = a **deterministic rule engine** as the final brake — an LLM can be
  prompt-injected or hallucinate, but it cannot lie to a hard allowlist / rate-limit
  / CIDR check evaluated outside the model.

This maps onto **what already exists** (don't reinvent):
- **Frigg is real**: `Mimir/scripts/odin_frigg_model_selection.py` benchmarks "Odin
  orchestrator (flash)" vs "Frigg advisor (pro)"; Bifrost has `governance_votes`,
  an "Odin + Frigg consensus" voting panel, and `POST /api/v1/rl/proposals/vote`.
  Both can run Claude Code via Hermodr. → Frigg = the advisor/consensus partner.
- **Thor is new** (reserved name, born Phase 3) = the deterministic policy enforcer,
  implemented with **Regorus** (Rego/OPA engine in Rust — see §3a).

Rule: **whoever performs an action must not be the one who authorises it.**
- Loki writing its own `guards.rs` = the prankster guarding himself → not trustworthy.
- Odin gating its own writes = the commander signing his own warrants → not trustworthy.

### Flow by tier

```
T0 read           : Odin → agent                                    (no gate)
T1 scan           : Odin → Thor(allowlist+ratelimit+dryrun) → agent → Tyr audit
T2 write-staged   : Odin → Thor(idempotency+dedup) → agent → Tyr audit
T3 write-prod     : Odin → Frigg(consensus vote) → Thor(policy) → HUMAN approve → agent → Tyr audit
```

**Frigg consensus gates T3 only** (merge-to-main, KALI exec, Wazuh active-response/
block-IP). T0–T2 skip Frigg — keeps the common path fast and avoids over-gating.
Reuses Bifrost's existing `governance_votes` rather than inventing a new mechanism.

### Should Thor / Frigg-gating exist *now*? — NO (reserve, don't build yet)

Today Odin has **only read tools (T0)** + one T1 (`huginn_start_scan`). Building Thor
or wiring Frigg-vote now = guarding an empty vault = over-engineering.
- **Thor is born in Phase 3** (first real write-path). Until then Loki keeps its
  in-process `guards.rs` (harden it — §5); Odin does inline HITL for `huginn_start_scan`.
- **Frigg-vote is wired in Phase 4/5** (when T3 actions appear), reusing Bifrost
  governance_votes.

Naming: Thor honours the "extend, don't proliferate Norse names" rule — one
justified addition for a distinct role (deterministic enforcement). Frigg already
exists. Skuggi (เงา) stays Heimdall's PII guardrail — unrelated, do not repurpose.

---

## 3a. Thor implementation — Regorus (Rego/OPA in Rust)

Decision: **Thor embeds [Regorus](https://github.com/microsoft/regorus)** — Microsoft's
MIT-licensed Rust interpreter of the **Rego** policy language (same language as
Open Policy Agent). Researched 2026-06-02 against the OPA org repos.

**Why Regorus over the OPA daemon:**

| | OPA (`opa`, Go) | **Regorus (Rust lib)** ✅ |
|---|---|---|
| Deploy | separate daemon / sidecar | **embedded in-process** (Thor is Rust, like Odin/Loki) |
| Network hop | yes (Thor→OPA over HTTP) | **none** (in-binary eval) |
| Language | Rego (full) | Rego (mostly OPA v1.2.0 compliant) |
| License | Apache-2.0 | **MIT** (fits open-core) |
| Provenance | OPA team | Microsoft; used in Azure Container Instances prod |
| Footprint | full runtime | tiny, `no_std` capable |

**Why policy-as-code beats hardcoded `guards.rs`:**
- Rules live in `.rego` files (e.g. `thor/policies/loki_scope.rego`,
  `merge_to_main.rego`) — **edit policy without recompiling Rust**.
- **One policy set covers all agents** — Loki/Huginn/Muninn/Odin send a JSON `input`,
  Thor returns `allow` + reason from a single rulebase.
- **Testable** — Rego has a native test framework (like `conftest`); policy gets unit
  tests, reviewed in PRs.
- Loki's current `guards.rs` allowlist/blocklist → migrated to Rego policy under Thor.

**Example Thor policy:**

```rego
# thor/policies/write_action.rego
package thor.authz
default allow = false

# T1 scan: target must be allowlisted and not an external IP
allow {
    input.tier == "T1"
    data.allowed_services[_] == input.target
    not is_external_ip(input.target)
}

# T3 merge: needs Frigg consensus + human approval, and never auto-merge to main
allow {
    input.tier == "T3"
    input.action == "merge_pr"
    input.frigg_vote == "approve"
    input.human_approved == true
    input.target_branch != "main"
}
```

Flow: agent/Odin builds JSON `input` → Thor (`regorus::Engine::eval`) → `{allow, reason}`
→ every decision logged to Tyr. The `thor` crate = thin wrapper: load policy bundle +
data (allowlists/CIDRs) + eval + audit.

---

## 4. Capability tiers (the backbone of safety)

Every Odin tool is classified. Default posture = **read-only**; higher tiers need
explicit enablement + Thor.

| Tier | Meaning | Examples | Gate (who must approve) |
|---|---|---|---|
| **T0 read** | observe only, no side effects | tyr_search_alerts, huginn_list_scans, loki_stats | none |
| **T1 scan** | active but non-destructive probe | huginn_start_scan (ZAP), loki HTTP-injection test | **Thor** (Rego: allowlist + rate-limit + dry-run echo) |
| **T2 write-staged** | create reversible artifacts | create GitHub issue, open draft PR, write KB doc | **Thor** (Rego: idempotency/dedup) + audit |
| **T3 write-prod** | irreversible / prod-affecting | merge PR to main, Loki KALI exec, block IP (Wazuh active-response) | **Frigg** (consensus vote) → **Thor** (Rego policy) → **human** (HITL) + blast-radius limit |

Odin's system prompt must state its default tier and refuse to self-escalate.
Frigg only enters at T3; Thor enters at T1+; humans only at T3.

---

## 5. Guardrail AUDIT — what's real vs placeholder (Loki `guards.rs`)

Verified by reading the file. **Be honest on stage: some guards are stubs.**

✅ **Real & tested** (has unit tests):
- `guard_target_service` — service allowlist (bifrost/heimdall/mimir/syn/qdrant/mariadb; external → blocked)
- `guard_dangerous_payload` — blocks DROP/DELETE/GRANT/`system(`/`bash`/`sh -c`/`subprocess`
- `guard_test_type` — 6 read-only test types only
- `guard_authorization` — requires `X-Loki-Test` header

⚠️ **Placeholder / not enforced** (must fix before any write-path):
1. **Rate limiter** — `check_rate_limit` returns Ok() always ("production will enforce"). → needs Redis-backed counter.
2. **DryRunGuard.validate()** — no-op, returns Ok(). → must actually force dry-run when set.
3. **Payload block is substring `.contains()`** — bypassable via encoding/case (e.g. `ba\x73h`). → needs normalize-then-match + structural validation, not a single string filter.

❌ **Missing entirely**:
4. **No KALI/shell executor** — so "Loki runs Kali" does not exist yet. *Good* (safer). If added, `guards.rs` is NOT sufficient —需 a **command allowlist + sandbox** (gVisor/dedicated namespace), never substring-filtered shell.
5. **No scope check on IP/CIDR** — allowlist is by service name, not network. Add explicit private-CIDR-only enforcement before any network scan.

---

## 6. Tyr noise control — dedup harness (before alert→issue)

Wazuh is noisy. Opening a GitHub issue per alert = issue flood. Required before
Phase 2 Tyr→issue:

- **Fingerprint** = hash(rule.id + agent.name + normalized data fields). 
- **Dedup window**: if same fingerprint seen within N hours → attach to existing
  issue (comment/count++), don't open new.
- **Severity gate**: only rule.level ≥ threshold (e.g. 10) becomes an issue; lower
  → aggregate into a daily digest.
- **Stateful store**: `odin-issue-dedup` index in the Wazuh indexer (Odin already
  has TYR_INDEXER creds) — fingerprint → issue URL.
- **Prompt harness**: the LLM step that drafts the issue must be given *only* the
  deduped, top-N alerts, with explicit "do not invent counts" instruction
  (we already saw gemma hallucinate scan numbers — §8 lesson).

---

## 7. Phased roadmap

**Phase 0 — DONE (this session):** Odin read + chat + auth + 9-service health + report. Demo-ready, in cluster.

**Phase 1 — Save/Export (safe, no new agent power):**
- Chat report → Copy Markdown (browser), Save-to-Tyr (`odin-reports-*` index via existing creds), Download .md.
- Add chat "thinking…" indicator (UX gap found in demo — bubble was blank during tool calls).
- No Thor needed (T0/T2-local-only).

**Phase 2 — Detect→Issue (first staged write, T2):**
- `huginn_start_scan` already T1. Add Odin tool `create_github_issue` (T2).
- Tyr dedup harness (§6) feeds it.
- `gh` token as k8s secret in Odin pod (NOT in image/git).
- HITL: Odin proposes the issue, human clicks "create" (or fix_mode=review style).
- **Thor born here as a thin policy fn** (idempotency + audit), grows in P3.

**Phase 3 — Issue→PR (T2/T3, Muninn):**
- Wire Muninn `watched_repos` + `code_agent_provider` (Claude Code) — engine exists.
- KB **service→repo map** in Mimir tenant `asgard_platform` (source of truth; do NOT let the LLM guess repo from agent.name).
- Thor enforces: PR target ≠ main, branch naming, diff size cap.

**Phase 4 — Loki KALI red-team (T3, highest risk):**
- Only if truly needed. Requires sandboxed command executor + command allowlist + private-CIDR-only + the §5 placeholder fixes made real.
- Thor mandatory; dry-run plan shown before exec; human approve.

**Phase 5 — PR review→merge (T3 write-prod):**
- Odin lists PRs → human reviews in UI → merge to main is **always** human-clicked.
- Thor: merge only after CI green + required approvals.

---

## 8. Lessons already learned this session (bake into design)

- **LLM hallucinates structured data** — gemma invented scan counts/scan_id when
  Huginn was unreachable. → tools must return real data or a clear error; never let
  the model fill gaps. Phase-2 issue drafting must cite only fetched, deduped facts.
- **Browser→localhost/ClusterIP fails from Tailscale** — all UI data must proxy
  through Odin server-side (we did this for health/issues/config). Same for any
  future write call.
- **max_tokens default truncates** — set explicitly (now 4096) so reports complete.
- **Auth was cosmetic** — login overlay with no backend check. Fixed with real
  middleware. Any new endpoint inherits the middleware by being under `protected`.

---

## 9. Open decisions (for the user)

- [x] Thor = reserved name, born Phase 3; engine = **Regorus** (Rego/OPA in Rust). ✓ decided 2026-06-02
- [x] Frigg = advisor/consensus, gates **T3 only**, reuses Bifrost governance_votes. ✓ decided 2026-06-02
- [ ] GitHub target repo(s) + where the `gh` token lives (k8s secret).
- [ ] Mimir KB write path needs JWT — decide auth approach for service→repo map.
- [ ] Keep Wazuh/Muninn scaled up (Odin live) vs scale-to-0 between uses (RAM).
- [ ] Whether KALI executor (Phase 4) is in scope at all, or Loki stays HTTP-only.

---

## 10. Naming note

- **Skuggi (เงา)** = Heimdall's PII guardrail (ADR-007, prod). **Unrelated** to
  Loki control — do NOT repurpose it.
- **Thor** = new policy-enforcement role (this doc). Born Phase 3.
- Keeps the project's "extend, don't proliferate Norse names" rule: Thor is one
  well-justified addition for a distinct role (separation of duties), not a clone.
