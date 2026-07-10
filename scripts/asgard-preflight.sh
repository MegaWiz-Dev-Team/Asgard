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
KUBE_NS="${KUBE_NS:-asgard asgard-infra wazuh}"
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

# ── 5. Nótt HB (prod-facing, via the Cloudflare tunnel) ───────────────────
# Prod Doctor-Consult reaches the Nótt engine over nott.megawiz.co.th. If that's
# down, prod HB/severity/triage return a clean 503 → a FAIL here so the watchdog
# raises the Discord alert (with its debounce + recovery). Longer timeout than the
# LAN hc() since it traverses Cloudflare.
section "🩸 Nótt HB (prod)"
NOTT_URL="${NOTT_URL:-https://nott.megawiz.co.th}"
if curl -sf --max-time 8 "$NOTT_URL/healthz" >/dev/null 2>&1; then
  ok "Nótt HB engine reachable ($NOTT_URL)"
  if curl -sf --max-time 8 -X POST "$NOTT_URL/triage" -H 'Content-Type: application/json' \
       -d '{"ahi":25,"hb":150}' 2>/dev/null | grep -q '"hb_severity"'; then
    ok "Nótt /triage computes HB severity"
  else
    warn "Nótt reachable but /triage not returning hb_severity (HB compute may be broken / stale image)"
  fi
else
  fail "Nótt HB engine unreachable ($NOTT_URL/healthz) — prod Doctor-Consult HB features are DOWN (503)"
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
