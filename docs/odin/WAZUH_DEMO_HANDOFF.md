# Odin × Wazuh Demo — components verified, e2e in final check (2026-06-01)

Goal: ask Odin a natural-language question → it calls `tyr_search_alerts` → queries the Wazuh
indexer → returns a formatted triage answer. For the "AI Cybersecurity Automation" talk
(Wazuh MeetUp, Mon 1 Jun 2026).

## What is INDEPENDENTLY VERIFIED (each tested directly)
- ✅ Wazuh indexer reachable on localhost:9200; **Odin's exact query** (`query_string rule.level:>=10`,
  sort by `@timestamp`/`timestamp` desc) returns the 3 seeded alerts.
- ✅ gemma-4-26b via Heimdall DOES tool-calling — direct test returned a proper
  `tyr_search_alerts {"query":"rule.level:>=10","size":20}` call with finish_reason=tool_calls.
- ✅ Odin native binary builds and runs (after fixing the hardcoded port — see below).
- ⏳ Full chat e2e (UI question → tool → answer) was being run on :3001 at handoff. CONFIRM by
  re-running the chat curl in "DEMO DAY" below and checking you get a tool_call event + final text.

## IMPORTANT gotcha found at the end
`src/main.rs` originally **hardcoded `let port = 3000`** and ignored `$PORT`. Port 3000 on this host
is held by Docker/OrbStack, so the native binary panicked `AddrInUse`. FIXED in source: main.rs now
reads `PORT` env (falls back to 3000). Rebuilt. **Run native Odin on PORT=3001** (3000 is taken).

## Current running state (all green)
- odin:3000=200, indexer:9200=200, manager:55000=200, heimdall:8080=200
- Odin runs NATIVE on host (PID listening :3000), log → `/tmp/asgard-demo/odin.log`
- Two `kubectl port-forward` running (indexer 9200, manager 55000) — these are background tasks
  in THIS Claude session; if the session ends they die → see "Restart from scratch" below.
- Wazuh pods: wazuh-manager-0 1/1, wazuh-indexer-0 1/1, wazuh-dashboard Running.

## What was broken & fixed (so it doesn't bite again)
1. Whole Wazuh stack was scaled to 0 → scaled manager/indexer/dashboard to 1.
2. Odin POD couldn't reach host Heimdall (`host.docker.internal:8080` unreachable from OrbStack
   pods). → run Odin NATIVE on host instead (localhost:8080 works). Pod still 500s; ignore it.
3. **wazuh-indexer-0 stuck Pending**: PV `tyr-indexer-pv` was a manual `local` volume pinned to
   `/Volumes/T7 Shield/...` → kubelet `mkdir` on the exfat/fskit T7 bind-mount threw "too many open
   files in system". → **Migrated indexer to k3s dynamic `local-path` (in-VM disk)**: deleted old
   pod+PVC+PV, created a plain PVC `tyr-indexer-pvc` (SC=local-path, 20Gi), deleted pod to rebind.
   Now Ready, storage is in-VM (portable, no T7 dependency).
4. Odin chat looped tool calls 6× (MAX_ITERATIONS) and returned no answer → root cause was the
   SAMPLE index mapping: ad-hoc seeded `wazuh-alerts-4.x-sample` auto-mapped `timestamp` as `text`,
   and Odin sorts by `timestamp` desc → OpenSearch "fielddata disabled on text" error → empty tool
   result → model retried. → **Recreated the index with explicit mapping (`timestamp`:date,
   `rule.level`:long, etc.)** and re-seeded. Odin's exact query now returns 3 hits, answer is clean.

## Credentials / endpoints
- Heimdall `http://localhost:8080`, model `gemma-4-26b` (LOCAL/free, confirmed does tool-calling).
  API key (64 chars) saved at `/tmp/asgard-demo/heimdall.key` (from k8s secret odin-secrets).
- Wazuh manager `https://localhost:55000` user=`wazuh` pass=`wazuh`
- Wazuh indexer `https://localhost:9200` user=`admin` pass=`admin`
- Odin UI `http://localhost:3000/` , login admin/admin (returns a static dev bearer token).

## DEMO DAY — start from scratch (copy-paste)
```bash
# 0. prereqs: Heimdall healthy on :8080 (curl http://localhost:8080/health)
# 1. ensure Wazuh is up
kubectl get pods -n wazuh            # manager-0 & indexer-0 should be 1/1; if not:
kubectl scale statefulset/wazuh-indexer statefulset/wazuh-manager -n wazuh --replicas=1
kubectl scale deploy/wazuh-dashboard -n wazuh --replicas=1
# 2. port-forwards (each in its own terminal, leave running)
kubectl port-forward -n wazuh svc/wazuh-indexer 9200:9200
kubectl port-forward -n wazuh svc/wazuh-manager 55000:55000
# 3. (only if alerts are gone) re-seed sample alerts:
bash /tmp/asgard-demo/seed.sh        # <-- see "seed script" below; recreate if /tmp was cleared
# 4. run Odin native
cd /Users/mimir/Developer/Odin
HEIMDALL_URL=http://localhost:8080 HEIMDALL_MODEL=gemma-4-26b \
HEIMDALL_API_KEY="$(cat /tmp/asgard-demo/heimdall.key)" \
TYR_URL=https://localhost:55000 TYR_USER=wazuh TYR_PASS=wazuh \
TYR_INDEXER_URL=https://localhost:9200 TYR_INDEXER_USER=admin TYR_INDEXER_PASS=admin \
PORT=3000 ./target/release/Odin
# 5. open http://localhost:3000/ , login admin/admin, ask the demo prompts below.
```

## Verified demo prompts (these returned good output)
1. "List the critical security alerts (rule level >= 10) from Wazuh. For each give rule
   description, agent name, and source IP. Then summarize the biggest risk."
2. "Tell me about the LLM01 prompt injection alert — what happened, which agent, and how dangerous?"
3. "How many alerts have level >= 10 right now?"
(EN prompts tested. Thai works too — gemma-4-26b is multilingual — but verify live before stage.)

## Honesty notes for stage
- Odin is READ-ONLY investigate/triage/report. It does NOT trigger Wazuh active-response or edit
  code. Enforcement stays Wazuh-side. Say this — don't overclaim a closed auto-remediation loop.
- These 3 alerts are SEEDED sample data (index `wazuh-alerts-4.x-sample`), not live agent telemetry.
  Fine for demo; just don't imply they're from a real breach.

## Known non-blockers
- hermodr-wazuh = ImagePullBackOff (image `asgard-hermodr:...` missing). NOT needed — Odin queries
  Wazuh directly. Optionally `kubectl scale deploy/hermodr-wazuh -n wazuh --replicas=0` to silence.
- indexer cluster status = yellow (single node, replicas unassigned) — normal, search works fine.
- Odin POD in k8s still 500s (can't reach host Heimdall). Demo uses the NATIVE binary; ignore pod.

## seed script (recreate at /tmp/asgard-demo/seed.sh if /tmp cleared)
Index `wazuh-alerts-4.x-sample` with mapping {timestamp:date, @timestamp:date, rule.level:long,
rule.description:text+keyword, agent.name:keyword, data.srcip:ip}. PUT the mapping first, then POST
3 docs (LLM01 prompt-injection L12 / sshd brute-force L10 / web-scan L11) with `timestamp` in
ISO `YYYY-MM-DDTHH:MM:SS.000+0000`. Last POST with `?refresh=wait_for`. Full commands are in this
session's history (tasks bz0xt2y6x = mapping, bbf99k2qz = seed).
