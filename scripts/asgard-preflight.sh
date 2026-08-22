#!/usr/bin/env bash
#
# asgard-preflight — read-only health check for the invariants that the
# 2026-06-12 MariaDB incident exposed (and that health.sh does NOT cover).
#
# health.sh checks HTTP liveness of services. This checks the INFRA invariants
# whose silent violation caused / hid that incident:
#   - no PVC stuck Terminating  (the root cause signal)
#   - no pods wedged Pending / ImagePull* / CrashLoop  (Odin + MariaDB were here)
#   - stateful workloads actually have a Running pod    (MariaDB had none)
#   - host memory headroom                              (kernel-panic guard)
#   - key host services reachable                       (Heimdall :8080/:8081)
#   - DB backups are fresh                              (a stale backup is a
#                                                        silent failure too)
#
# Read-only: no kubectl mutation, no service restart. Safe to run anytime, and
# it is the body of asgard-watchdog.sh.
#
# Exit codes:  0 = OK   1 = WARN (degraded)   2 = FAIL (critical)
#
# Usage:
#   ./asgard-preflight.sh            human output
#   ./asgard-preflight.sh --json     machine output (for the watchdog)
set -uo pipefail

JSON=0
[[ "${1:-}" == "--json" ]] && JSON=1

# Tunables
MIN_FREE_GB="${MIN_FREE_GB:-8}"
BACKUP_MAX_AGE_DAYS="${BACKUP_MAX_AGE_DAYS:-3}"
KUBE_NS="${KUBE_NS:-asgard asgard-infra asgard-rl wazuh}"
KCTL="kubectl --request-timeout=8s"
T7_BASE="${T7_BASE:-/Volumes/T7 Shield}"   # quoted everywhere (path has a space)

GREEN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[1;33m'; NC='\033[0m'
FAILS=(); WARNS=(); OKS=()
ok()   { OKS+=("$1");   [[ $JSON -eq 0 ]] && echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { WARNS+=("$1"); [[ $JSON -eq 0 ]] && echo -e "  ${YEL}⚠️  $1${NC}"; }
fail() { FAILS+=("$1"); [[ $JSON -eq 0 ]] && echo -e "  ${RED}❌ $1${NC}"; }

section() { [[ $JSON -eq 0 ]] && echo -e "\n$1"; }

# ── 1. host memory headroom ───────────────────────────────────────────────
section "🧠 Host memory"
FREE=$(vm_stat 2>/dev/null | awk '/page size/{ps=$8} /Pages free/{gsub(/\./,"",$3);f=$3} /Pages inactive/{gsub(/\./,"",$3);i=$3} END{printf "%d",(f+i)*ps/1073741824}')
if [[ -z "$FREE" ]]; then warn "memory: could not read vm_stat"
elif (( FREE < MIN_FREE_GB )); then fail "memory headroom ${FREE}GB < ${MIN_FREE_GB}GB"
else ok "memory headroom ${FREE}GB"; fi

# ── 2. kubernetes reachable? ──────────────────────────────────────────────
section "☸️  Kubernetes"
if ! $KCTL get ns >/dev/null 2>&1; then
  fail "cluster unreachable (OrbStack/K3s down?) — skipping K8s checks"
else
  ok "cluster reachable"

  # 2a. PVCs stuck Terminating — THE incident root-cause signal
  TERM_PVC=$($KCTL get pvc -A --no-headers 2>/dev/null | awk '$3=="Terminating"{print $1"/"$2}')
  if [[ -n "$TERM_PVC" ]]; then
    while read -r p; do [[ -n "$p" ]] && fail "PVC stuck Terminating: $p"; done <<< "$TERM_PVC"
  else ok "no PVC stuck Terminating"; fi

  # 2a2. pods stuck Terminating >1h — the chronic runtime/kubelet wedge signal.
  # INC-2026-06-15: pods sat Terminating for ~3 days before the acute outage; the
  # kubelet couldn't create OR destroy sandboxes. Catch it while still chronic.
  TERM_OLD=$($KCTL get pods -A -o json 2>/dev/null | python3 -c '
import sys, json, datetime
now = datetime.datetime.now(datetime.timezone.utc)
for p in json.load(sys.stdin).get("items", []):
    dt = p.get("metadata", {}).get("deletionTimestamp")
    if not dt:
        continue
    t = datetime.datetime.fromisoformat(dt.replace("Z", "+00:00"))
    age = (now - t).total_seconds() / 3600.0
    if age > 1:
        print(f"{p[\"metadata\"][\"namespace\"]}/{p[\"metadata\"][\"name\"]} ({age:.1f}h)")
' 2>/dev/null)
  if [[ -n "$TERM_OLD" ]]; then
    while read -r p; do [[ -n "$p" ]] && fail "pod stuck Terminating >1h: $p"; done <<< "$TERM_OLD"
  else ok "no pod stuck Terminating >1h"; fi

  # 2b. pods wedged (Pending / ImagePull* / CrashLoop / Error) — exclude Completed
  for ns in $KUBE_NS; do
    BAD=$($KCTL get pods -n "$ns" --no-headers 2>/dev/null | \
      awk '$3 ~ /Pending|ImagePullBackOff|ErrImageNeverPull|ErrImagePull|CrashLoopBackOff|Error|Init:Error/ {print $1" ("$3")"}')
    if [[ -n "$BAD" ]]; then
      while read -r p; do [[ -n "$p" ]] && fail "pod wedged in $ns: $p"; done <<< "$BAD"
    fi
  done

  # 2b2. node resource pressure — INC-2026-06-12 part 2: a 18GB docker build cache
  # filled the OrbStack node disk → DiskPressure → cluster-wide pod eviction +
  # kubelet image-GC removed locally-built (unpullable) images. Catch it early.
  NODE_PRESSURE=$($KCTL get nodes -o jsonpath='{range .items[*]}{range .status.conditions[?(@.status=="True")]}{.type}{"\n"}{end}{end}' 2>/dev/null | grep -E 'DiskPressure|MemoryPressure|PIDPressure')
  if [[ -n "$NODE_PRESSURE" ]]; then
    while read -r c; do [[ -n "$c" ]] && fail "node under $c (evictions imminent — check 'docker system df' build cache)"; done <<< "$NODE_PRESSURE"
  else ok "no node resource pressure"; fi

  # 2c. stateful workloads have a Running pod
  for sts in "asgard-infra:mariadb"; do
    ns="${sts%%:*}"; name="${sts##*:}"
    RUN=$($KCTL get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | grep -c "$name")
    if (( RUN < 1 )); then fail "no Running pod for ${name} in ${ns}"; else ok "${name}: ${RUN} Running pod"; fi
  done
fi

# ── 3. host services (native, not in cluster) ─────────────────────────────
section "🖥️  Host services"
hc() { local n="$1" u="$2"; if curl -sf --max-time 4 "$u" >/dev/null 2>&1; then ok "$n"; else fail "$n unreachable ($u)"; fi; }
hc "Heimdall gateway :8080" "http://localhost:8080/health"
# :8081 mlx server has no /health; check the port is listening + model loaded
if curl -sf --max-time 5 "http://localhost:8081/v1/models" >/dev/null 2>&1; then ok "Heimdall MLX :8081 (model server)"; else warn "Heimdall MLX :8081 not responding /v1/models"; fi

# ── 4. backup freshness ───────────────────────────────────────────────────
section "💾 Backups (T7)"
if [[ ! -d "$T7_BASE" ]]; then
  warn "T7 not mounted — cannot verify backups"
else
  NEWEST=$(find "$T7_BASE" -maxdepth 4 -name '*.sql.gz' -type f 2>/dev/null | while IFS= read -r f; do stat -f '%m %N' "$f"; done | sort -rn | head -1)
  if [[ -z "$NEWEST" ]]; then
    warn "no *.sql.gz DB backups found on T7"
  else
    TS="${NEWEST%% *}"; NOWS=$(date +%s); AGE_D=$(( (NOWS - TS) / 86400 ))
    if (( AGE_D > BACKUP_MAX_AGE_DAYS )); then warn "newest DB backup is ${AGE_D}d old (> ${BACKUP_MAX_AGE_DAYS}d)"
    else ok "newest DB backup ${AGE_D}d old"; fi
  fi
fi

# ── 5. Nótt HB (prod) — HB engine on Cloud Run (critical), chat/agents on Mac ─
# De-SPOF'd 2026-07-10: prod HB compute (/analyze) is served by the GCP Cloud Run engine
# (nott-engine); /chat + Sleep-Expert agents stay on the Mac (local-LLM).
# LOCKED DOWN 2026-07-10: the engine is IAM-restricted — only the mega-care backend SA may invoke
# it — so an UNAUTHENTICATED probe now returns HTTP 403. A 401/403 therefore means "up + auth
# working" (healthy); only a connection failure (000) or a 5xx means the service itself is down.
# We can no longer run an unauthenticated /triage functional probe — liveness (any HTTP response)
# is the check. (Cloud Run also RESERVES /healthz — GFE 404s it — so probe /viewer/index.html.)
section "🩸 Nótt HB (prod)"
NOTT_ENGINE_URL="${NOTT_ENGINE_URL:-https://nott-engine-842423068850.asia-southeast1.run.app}"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$NOTT_ENGINE_URL/viewer/index.html" 2>/dev/null)
case "$code" in
  200)     ok "Nótt HB engine reachable (Cloud Run, HTTP 200)" ;;
  401|403) ok "Nótt HB engine reachable (Cloud Run, HTTP $code — IAM-locked, backend-only)" ;;
  *)       fail "Nótt HB engine (Cloud Run) unreachable/erroring (HTTP ${code:-000}) — prod Doctor-Consult Hypoxic Burden at risk" ;;
esac
# chat + Sleep-Expert agents run on the Mac (local-LLM). Tunnel down = degrade only (HB unaffected).
NOTT_CHAT_HC="${NOTT_CHAT_HC:-https://nott.megawiz.co.th}"
if curl -sf --max-time 8 "$NOTT_CHAT_HC/healthz" >/dev/null 2>&1; then
  ok "Nótt chat/agent engine reachable (Mac tunnel)"
else
  warn "Nótt chat engine (Mac tunnel) unreachable — /nott-chat + Sleep-Expert degrade (HB unaffected, on Cloud Run)"
fi

# ── 6. launchd ops jobs ───────────────────────────────────────────────────
# 2026-08-21: nightly-backup, ca-expiry-watch and boot-report had been dead for
# weeks. A job whose script disappears (a branch switch is enough — launchd runs
# them straight out of the Asgard working tree) exits EX_CONFIG 78, lands in the
# penalty box and never runs again. Nothing else in this file would notice: the
# backup-age check only catches it days late, and a CA watch that never runs has
# no symptom at all until the certificate expires.
section "🚀 launchd ops jobs"
LD_BAD=0
UID_NUM=$(id -u)
while read -r LABEL; do
  [[ -z "$LABEL" ]] && continue
  INFO=$(launchctl print "gui/${UID_NUM}/${LABEL}" 2>/dev/null)
  if [[ -z "$INFO" ]]; then warn "launchd ${LABEL}: not loaded"; LD_BAD=1; continue; fi
  # Every absolute path the job executes must exist — covers both the bare
  # script and the "/bin/bash <script>" form.
  MISSING=$(echo "$INFO" | awk '/arguments = \{/{a=1;next} a&&/\}/{a=0} a{gsub(/^[ \t]+|[ \t]+$/,"");if($0 ~ /^\//) print}' \
            | while IFS= read -r P; do [[ -e "$P" ]] || echo "$P"; done)
  if [[ -n "$MISSING" ]]; then
    fail "launchd ${LABEL}: program missing ($(echo "$MISSING" | head -1))"; LD_BAD=1; continue
  fi
  # A running job's last exit code is history, not a verdict.
  echo "$INFO" | grep -q "state = running" && continue
  EC=$(echo "$INFO" | awk -F'= ' '/last exit code/{print $2; exit}')
  case "$EC" in
    78*)          fail "launchd ${LABEL}: EX_CONFIG 78 — penalty box, job never runs"; LD_BAD=1 ;;
    0|"(never exited)"|"") ;;
    *)            warn "launchd ${LABEL}: last exit ${EC}"; LD_BAD=1 ;;
  esac
done < <(launchctl list 2>/dev/null | grep -oE 'com\.asgard\.[a-z0-9.-]+' | sort -u)
(( LD_BAD == 0 )) && ok "launchd asgard jobs healthy"

# ── 7. NetworkPolicy selectors that match nothing ─────────────────────────
# 2026-08-22: an OrbStack restart re-evaluated every NetworkPolicy, and three
# namespaces turned out to be missing the labels those policies select on — so
# rules written to ALLOW database traffic could only deny it. Zitadel lost
# Postgres, SSO died with it, and Bifrost/mimir-api followed. A namespaceSelector
# that matches no namespace is never a working allow-rule; it is an outage
# waiting for the next restart.
section "🔒 NetworkPolicy selectors"
NS_JSON="$($KCTL get ns -o json 2>/dev/null)"
# A dormant namespace (no pods) with a broken selector is a warning; the same
# break in a namespace that is actually serving is an outage in waiting.
NS_WITH_PODS="$($KCTL get pods -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')"
# NSJSON has to sit on the python3 command: in a pipeline the env prefix only
# reaches the FIRST command, so hanging it off kubectl leaves python blind and
# every selector then "matches no namespace".
NP_ORPHANS=$($KCTL get netpol -A -o json 2>/dev/null | NSJSON="$NS_JSON" PODNS="$NS_WITH_PODS" python3 -c '
import json, os, sys
pols = json.load(sys.stdin).get("items", [])
nss = json.loads(os.environ.get("NSJSON") or "{}").get("items", [])
labels = [n["metadata"].get("labels") or {} for n in nss]
live = set((os.environ.get("PODNS") or "").split())
out = []
for pol in pols:
    meta = pol["metadata"]
    ns_name = meta["namespace"]
    pol_name = meta["name"]
    for direction, key in (("ingress", "from"), ("egress", "to")):
        for rule in pol.get("spec", {}).get(direction) or []:
            for peer in rule.get(key) or []:
                sel = (peer.get("namespaceSelector") or {}).get("matchLabels")
                if not sel:
                    continue
                if not any(all(l.get(k) == v for k, v in sel.items()) for l in labels):
                    pairs = ",".join(k + "=" + v for k, v in sorted(sel.items()))
                    sev = "FAIL" if ns_name in live else "WARN"
                    out.append(sev + "|" + ns_name + "/" + pol_name + " " + direction + " selects [" + pairs + "] - matches NO namespace")
print("\n".join(sorted(set(out))))
')
NP_RC=$?
if (( NP_RC != 0 )); then
  # A check that cannot run must not read as a pass — that is how the label gap
  # stayed invisible in the first place.
  warn "netpol selector check failed to run (rc=${NP_RC})"
elif [[ -n "$NP_ORPHANS" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
      FAIL\|*) fail "netpol ${line#FAIL|}" ;;
      *)       warn "netpol ${line#WARN|} (namespace has no pods — latent)" ;;
    esac
  done <<< "$NP_ORPHANS"
else
  ok "every NetworkPolicy namespaceSelector matches a live namespace"
fi

# ── verdict ───────────────────────────────────────────────────────────────
CODE=0; (( ${#WARNS[@]} > 0 )) && CODE=1; (( ${#FAILS[@]} > 0 )) && CODE=2
if [[ $JSON -eq 1 ]]; then
  # build JSON arrays — guard empties so an empty array is [] not [""]
  # (printf with a format + zero args emits one empty field → the [""] bug).
  fails_json=""; warns_json=""
  (( ${#FAILS[@]} )) && fails_json=$(printf '"%s",' "${FAILS[@]}" | sed 's/,$//')
  (( ${#WARNS[@]} )) && warns_json=$(printf '"%s",' "${WARNS[@]}" | sed 's/,$//')
  printf '{"code":%d,"status":"%s","fail":[%s],"warn":[%s],"ok_count":%d}\n' \
    "$CODE" "$([[ $CODE -eq 0 ]] && echo OK || ([[ $CODE -eq 1 ]] && echo WARN || echo FAIL))" \
    "$fails_json" "$warns_json" "${#OKS[@]}"
else
  echo -e "\n═══════════════════════"
  echo -e "Result: ${GREEN}${#OKS[@]} ok${NC}, ${YEL}${#WARNS[@]} warn${NC}, ${RED}${#FAILS[@]} fail${NC}  → exit $CODE"
fi
exit $CODE
