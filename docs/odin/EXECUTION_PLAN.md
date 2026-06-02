# Odin Orchestrator — Gap Analysis & Execution Plan

**Date:** 2026-06-02 · **Basis:** ODIN_ORCHESTRATOR_DESIGN.md (vision) verified against real code.
**Method:** every claim below checked in source/cluster, not assumed. ✅=verified real, ⚠️=partial/stub, ❌=missing.

---

## 1. Vision recap (the agentic security loop)

```
Loki red-team ─┐
Huginn VA scan ─┼─▶ findings ─▶ GitHub issue ─▶ Muninn fix (PR) ─▶ human review ─▶ merge
Tyr SIEM alert ─┘                    ▲                                    ▲
                              Odin orchestrates          Frigg consensus + Thor policy gate
```

---

## 2. GAP ANALYSIS — what's real vs what's missing (verified 2026-06-02)

| Capability | Status | Evidence | Gap to close |
|---|---|---|---|
| Odin read/triage/report | ✅ real | deployed, 18 tools, health-proxy 11 svc | — |
| Odin auth (token) | ✅ real | middleware, random token | — |
| Huginn ZAP scan | ✅ real | `huginn_start_scan` tested (221 scans) | — |
| **Huginn → GitHub issue** | ✅ **real code** | `notify.rs:create_github_issues` does real `POST /repos/{}/issues` | only needs `GITHUB_TOKEN` in pod + correct repo mapping (currently `asgard/{service}` guess) |
| Muninn issue→PR engine | ✅ real | watcher poll loop + OpenCode→Heimdall agent | `watched_repos=[]` + `code_agent=none` → idle. Wire config to activate |
| Tyr SIEM read | ✅ real | `tyr_search_alerts` | — |
| **Tyr alert → GitHub issue** | ❌ missing | no bridge | build: alert→issue with dedup (§4) |
| **Tyr dedup/noise filter** | ❌ missing | grep none | required before alert→issue (issue flood) |
| Loki HTTP-injection test | ✅ real | handlers/ exist | — |
| **Loki KALI executor** | ❌ missing | no shell exec in code | big build + sandbox; or keep HTTP-only |
| Loki guardrails | ⚠️ partial | guards.rs: allowlist/payload-block REAL; **rate-limit + dry-run = placeholder (return Ok)** | enforce for real before write-path |
| **Frigg consensus** | ⚠️ logic-only | Bifrost `rl_governance_voting.rs` has `evaluate_consensus()` (Odin AND Frigg approve) BUT routes are **GET only** (pending/details) — **no POST vote endpoint**, no Frigg agent process | wire POST vote route + instantiate Frigg as an agent that actually votes |
| **Thor policy enforcer** | ❌ missing | not built | new `thor` crate w/ Regorus (verify crate version at start) |
| Odin list PR → review → merge | ❌ missing | no tool | add `gh pr` tools (T2 list, T3 merge) |
| KB service→repo map | ❌ missing | Huginn guesses `asgard/{service}` | Mimir KB (tenant asgard_platform) as source of truth |

**Headline finding:** the loop is ~70% built but **disconnected**. Three concrete blockers,
in order: (1) no GITHUB_TOKEN wired anywhere → no issue actually gets created; (2) Muninn idle
(empty config); (3) no dedup → turning it on would flood issues. Frigg/Thor are *governance*
gaps that only matter once write-paths open.

---

## 3. Critical-path insight

The vision's hardest-sounding parts are **already coded**:
- Huginn→issue = real API call (just needs token)
- Muninn→PR = real engine (just needs config)
- Frigg consensus = real `evaluate_consensus()` logic (just needs a POST route + a voter)

What's genuinely missing is **glue + safety**, not the hard agent logic. So the plan front-loads
cheap glue wins and defers the expensive/risky builds (KALI, full Thor).

---

## 4. EXECUTION PLAN — phased, each step independently shippable

### Phase 1 — Save/Export + UX (safe, no agent power) ⏱️ small
- [ ] Chat report: Copy-Markdown + Save-to-Tyr (`odin-reports-*` index, Odin has creds) + Download .md
- [ ] Chat "thinking…" indicator (demo gap: blank bubble during tool calls)
- **Gate:** none (T0/T2-local). **Risk:** none. **Unblocks:** usable reports today.

### Phase 2 — Detect → GitHub issue (first staged write, T2) ✅ DONE 2026-06-02
- [x] `GITHUB_TOKEN` in `huginn-secrets` (93-char fine-grained PAT) + wired to Huginn pod
- [x] Huginn repo mapping: `asgard/{service}` (404) → `service_to_repo()` → `MegaWiz-Dev-Team/<Repo>`
      (Huginn@6d9fe23, deployed img 468c792). E2E proven: token created+closed issue#2 on Odin repo.
- [x] **Tyr dedup harness**: `issue_fingerprint(repo,title)` → `odin-issue-dedup` index (TYR_INDEXER creds)
- [x] Odin **propose_github_issue** tool (READ-ONLY proposal) + **POST /api/issues/create** (HITL confirm,
      dedup, server-side create, audit) + chat confirm-card UI. Odin@7315680, deployed img 5b222733.
- [x] **Thor v0** = the thin dedup+idempotency in create_issue (not full Regorus yet)
- **Gate:** human clicks "Create issue". **Risk:** low. **Status:** loop works; needs token on Odin (below).

  **⚠️ Manual step — set GITHUB_TOKEN on Odin (value must not pass through chat/logs):**
  ```bash
  # copy the already-valid token from huginn-secrets into odin-secrets
  TOK=$(kubectl get secret huginn-secrets -n asgard -o jsonpath='{.data.github_token}' | base64 -d)
  kubectl patch secret odin-secrets -n asgard --type=merge \
    -p "{\"stringData\":{\"GITHUB_TOKEN\":\"$TOK\"}}"
  # wire env from the secret key, then restart
  kubectl patch deploy odin -n asgard --type=json -p='[{"op":"add",
    "path":"/spec/template/spec/containers/0/env/-",
    "value":{"name":"GITHUB_TOKEN","valueFrom":{"secretKeyRef":{"name":"odin-secrets","key":"GITHUB_TOKEN"}}}}]'
  kubectl rollout restart deploy/odin -n asgard
  ```
  Until set, `/api/issues/create` returns 503 (propose still works, create is blocked — safe default).

  **Try it:** Odin chat → "open an issue to track the LLM01 prompt-injection alert" → confirm-card +
  "Create issue" button → click → real issue + dedup (click again = same link).

  **Not done (deferred from original Phase 2 scope):**
  - Tyr alert→issue *auto-bridge* (currently human asks Odin in chat; no autonomous alert→issue yet)
  - KB-based service→repo map in Mimir (used a hardcoded map instead — fine for ~16 repos)

### Phase 3 — Issue → PR (T2/T3, Muninn) ⏱️ medium
- [ ] Set Muninn `WATCHED_REPOS` + `CODE_AGENT_PROVIDER=opencode` (Heimdall backend)
- [ ] Scale Muninn up; verify poll loop picks issues → opens **draft** PR (fix_mode=review)
- [ ] Thor policy: PR target≠main, branch-naming, diff-size cap
- **Gate:** fix_mode=review (human approves PR). **Risk:** medium (writes code). **Unblocks:** auto-fix.

### Phase 4 — Frigg consensus + Thor (Regorus) ⏱️ large
- [ ] Add POST vote route to Bifrost (`evaluate_consensus()` exists — just expose it)
- [ ] Instantiate Frigg as an agent (pro-tier model) that casts a real vote on T3 proposals
- [ ] Build `thor` crate: embed Regorus (verify crate version), load `.rego` bundle, migrate
      Loki guards.rs → Rego policy, eval flow, audit→Tyr
- [ ] Enforce real rate-limit + dry-run in Loki (kill the placeholders)
- **Gate:** Frigg vote + Thor policy. **Risk:** high. **Unblocks:** safe T3.

### Phase 5 — PR review → merge (T3 write-prod) ⏱️ medium
- [ ] Odin `gh_pr_list` (T2) + `gh_pr_merge` (T3)
- [ ] Merge to main = Frigg approve + Thor (CI green + approvals) + **human click** always
- **Gate:** full 3-power + human. **Risk:** highest. **Unblocks:** closed loop.

### Phase X (optional, defer) — Loki KALI executor
- Only if HTTP-injection is insufficient. Needs sandbox (gVisor/namespace) + command allowlist +
  private-CIDR-only + the §2 placeholder fixes. Highest risk; not on critical path.

---

## 5. Status / next action

**Phase 2 = DONE (2026-06-02)** — detect→issue loop built, deployed, E2E-proven. Only the manual
GITHUB_TOKEN step on Odin remains (boxed above) to flip create from 503→live.

**Next candidates** (pick by appetite):
- **Phase 1** (Save/Export + typing indicator) — still unbuilt; pure value, zero risk.
- **Phase 3** (Muninn issue→PR) — engine exists, just wire `WATCHED_REPOS` + `CODE_AGENT_PROVIDER=opencode`.
- **Tyr alert→issue auto-bridge** — close the "autonomous" gap left in Phase 2.

Do NOT start with Frigg/Thor — they gate write-paths that don't fully exist yet (guarding an empty vault).

---

## 6. Cross-cutting (apply every phase)
- Real data or clear error — never let the LLM invent (lesson: gemma faked scan counts).
- Proxy all data server-side through Odin (browser/Tailscale can't reach ClusterIP).
- Audit every write to Tyr (who/when/what/result).
- HITL at every T3; capability tier stated in Odin's system prompt; refuse self-escalation.
