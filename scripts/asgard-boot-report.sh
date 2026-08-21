#!/usr/bin/env bash
#
# asgard-boot-report — fired ONCE per host boot (launchd com.asgard.boot-report,
# RunAtLoad). Waits for the cluster to come up, takes a FULL census of every
# Asgard service, and posts a single summary to Discord *as Odin* via the webhook.
#
# Why host-side and not inside Odin: the whole point is to report when boot went
# wrong — and a cluster/Odin-pod that failed to start can't report on itself
# (same lesson as asgard-watchdog). So this runs on the host, independent of the
# cluster it watches, and posts under the "Odin 🏛️" identity so it reads as Odin
# in the channel.
#
# "All services, really" = auto-enumerated, NOT a hardcoded list (which drifts):
#   - every Deployment + StatefulSet across: asgard, asgard-infra, wazuh
#       · desired>0 & ready==desired → UP
#       · desired>0 & ready<desired  → DOWN  (a real problem)
#       · desired==0                 → IDLE  (scaled to 0 on purpose — laminar,
#                                              llmgoat, redis-infra, … — NOT a fault)
#   - native host services (not in K8s): Heimdall gateway/MLX/VLM + Syn AppleVision
#
# Usage:
#   ./asgard-boot-report.sh             wait for boot to settle, then post
#   ./asgard-boot-report.sh --dry-run   compute census + print the message, DON'T post
#   ./asgard-boot-report.sh --no-wait   skip the settle loop, census now (for testing)
set -uo pipefail

DRY=0; NOWAIT=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --no-wait) NOWAIT=1 ;;
    --force)   FORCE=1 ;;
  esac
done

# ── tunables ───────────────────────────────────────────────────────────────
BOOT_WINDOW="${BOOT_WINDOW:-1800}"    # only treat a run as a real boot if uptime < this (s)
KUBE_NS="${KUBE_NS:-asgard asgard-infra wazuh}"
CLUSTER_WAIT="${CLUSTER_WAIT:-600}"   # max seconds to wait for kubectl to reach the cluster
SETTLE_MAX="${SETTLE_MAX:-900}"       # max seconds to wait for pods to become ready
POLL="${POLL:-20}"                    # seconds between settle polls
MIN_WORKLOADS="${MIN_WORKLOADS:-25}"  # don't declare "all up" until we've seen at least this many active workloads (guards against an empty/early cluster reading 0-down)
KCTL="kubectl --request-timeout=8s"

# Secrets (DISCORD_WEBHOOK) live in the same gitignored, chmod-600 file the
# watchdog uses. launchd has no shell env, so source it explicitly.
[[ -f "$HOME/.asgard-watchdog.env" ]] && source "$HOME/.asgard-watchdog.env"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname)"
START_EPOCH="$(date +%s)"

# ── fresh-boot guard ─────────────────────────────────────────────────────────
# launchd RunAtLoad fires every time the agent is loaded — at real boot/login AND
# on any manual `launchctl bootstrap`. We only want to report "หาก start server
# ใหม่" = a genuine boot. Gate on system uptime: if the box has been up longer
# than BOOT_WINDOW, this load is NOT a fresh boot → do nothing (so re-registering
# the agent never spams the channel). --force / --no-wait / --dry-run bypass it.
# format: "{ sec = 1781358055, usec = 708862 } …" — $4 is "sec," (note: "usec"
# also contains "sec", so a greedy regex grabs the wrong one — use the field).
BOOTSEC="$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')"
if [[ "$BOOTSEC" =~ ^[0-9]+$ ]]; then
  UPTIME=$(( START_EPOCH - BOOTSEC ))
else
  UPTIME=0
fi
if (( DRY == 0 && NOWAIT == 0 && FORCE == 0 )) && (( UPTIME > BOOT_WINDOW )); then
  echo "[boot-report] uptime ${UPTIME}s > ${BOOT_WINDOW}s — not a fresh boot, skipping (use --force to override)"
  exit 0
fi

# ── host (native) service probes ─────────────────────────────────────────────
http_up() { curl -sf --max-time 4 "$1" >/dev/null 2>&1; }
tcp_up()  { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3>&-; return 0; } || return 1; }
launchd_up() { launchctl list "$1" 2>/dev/null | grep -q '"PID"'; }

# echoes: "<name>\t<up|down>" per host service
host_census() {
  local -a checks=(
    "Heimdall gateway:8080|http|http://localhost:8080/health"
    "Heimdall MLX:8081|http|http://localhost:8081/v1/models"
    "Heimdall VLM-q4:8082|tcp|8082"
    "Heimdall VLM-q8:8083|tcp|8083"
    "Heimdall VLM-qwen2:8087|tcp|8087"
    "Syn AppleVision|launchd|com.asgard.syn-applevision"
  )
  local c name kind arg
  for c in "${checks[@]}"; do
    name="${c%%|*}"; kind="$(cut -d'|' -f2 <<<"$c")"; arg="${c##*|}"
    case "$kind" in
      http)    http_up "$arg"    && printf '%s\tup\n' "$name" || printf '%s\tdown\n' "$name" ;;
      tcp)     tcp_up  "$arg"    && printf '%s\tup\n' "$name" || printf '%s\tdown\n' "$name" ;;
      launchd) launchd_up "$arg" && printf '%s\tup\n' "$name" || printf '%s\tdown\n' "$name" ;;
    esac
  done
}

# ── k8s census ────────────────────────────────────────────────────────────────
# echoes one line per workload: "<ns>\t<kind>\t<name>\t<state>\t<ready>/<desired>"
# state ∈ up|down|idle. Auto-discovers every Deployment + StatefulSet.
k8s_census() {
  local ns line kind name desired ready state
  for ns in $KUBE_NS; do
    while IFS=$'\t' read -r kind name desired ready; do
      [[ -z "$name" ]] && continue
      [[ -z "$desired" ]] && desired=0
      [[ -z "$ready" ]] && ready=0
      if   (( desired == 0 ));        then state="idle"
      elif (( ready >= desired ));    then state="up"
      else                                 state="down"; fi
      printf '%s\t%s\t%s\t%s\t%d/%d\n' "$ns" "$kind" "$name" "$state" "$ready" "$desired"
    done < <($KCTL get deploy,statefulset -n "$ns" \
        -o jsonpath='{range .items[*]}{.kind}{"\t"}{.metadata.name}{"\t"}{.spec.replicas}{"\t"}{.status.readyReplicas}{"\n"}{end}' 2>/dev/null)
  done
}

# down-count from a census blob (k8s + host), for the settle loop
count_down() { grep -c $'\tdown\t\|\tdown$' <<<"$1" 2>/dev/null || true; }

cluster_reachable() { $KCTL get ns >/dev/null 2>&1; }

# ── 1. wait for the cluster to be reachable ──────────────────────────────────
CLUSTER_OK=0
if (( NOWAIT == 1 )); then
  cluster_reachable && CLUSTER_OK=1
else
  while (( $(date +%s) - START_EPOCH < CLUSTER_WAIT )); do
    if cluster_reachable; then CLUSTER_OK=1; break; fi
    sleep "$POLL"
  done
fi

# ── 2. settle loop: wait until nothing is DOWN (or SETTLE_MAX elapses) ────────
K8S=""; HOSTC=""
if (( CLUSTER_OK == 1 )); then
  while :; do
    K8S="$(k8s_census)"
    HOSTC="$(host_census)"
    active_total=$(grep -cE $'\tup\t|\tdown\t' <<<"$K8S")
    k8s_down=$(grep -c $'\tdown\t' <<<"$K8S" || true)
    host_down=$(grep -c $'\tdown$' <<<"$HOSTC" || true)
    elapsed=$(( $(date +%s) - START_EPOCH ))
    if (( NOWAIT == 1 )); then break; fi
    # settled when nothing is down AND we've actually seen the cluster populate
    if (( k8s_down == 0 && host_down == 0 && active_total >= MIN_WORKLOADS )); then break; fi
    if (( elapsed >= SETTLE_MAX )); then break; fi
    sleep "$POLL"
  done
else
  # cluster never came up — still probe host services so we report what we can
  HOSTC="$(host_census)"
fi

ELAPSED=$(( $(date +%s) - START_EPOCH ))

# ── 3. tally ─────────────────────────────────────────────────────────────────
UP_LIST="$(grep $'\tup\t'   <<<"$K8S" 2>/dev/null || true)"
DOWN_LIST="$(grep $'\tdown\t' <<<"$K8S" 2>/dev/null || true)"
IDLE_LIST="$(grep $'\tidle\t' <<<"$K8S" 2>/dev/null || true)"
HOST_UP_LIST="$(grep $'\tup$'   <<<"$HOSTC" 2>/dev/null || true)"
HOST_DOWN_LIST="$(grep $'\tdown$' <<<"$HOSTC" 2>/dev/null || true)"

cnt() { [[ -z "$1" ]] && echo 0 || grep -c . <<<"$1"; }
UP_N=$(cnt "$UP_LIST"); DOWN_N=$(cnt "$DOWN_LIST"); IDLE_N=$(cnt "$IDLE_LIST")
HOST_UP_N=$(cnt "$HOST_UP_LIST"); HOST_DOWN_N=$(cnt "$HOST_DOWN_LIST")
ACTIVE_N=$(( UP_N + DOWN_N ))
HOST_N=$(( HOST_UP_N + HOST_DOWN_N ))
TOTAL_DOWN=$(( DOWN_N + HOST_DOWN_N ))

# friendly down lines: "ns/name (ready/desired)" and host "name"
fmt_down_k8s() { awk -F'\t' '{print "• "$1"/"$3" ("$5")"}' <<<"$1"; }
fmt_down_host() { awk -F'\t' '{print "• "$1" (host)"}' <<<"$1"; }
DOWN_PRETTY="$( [[ -n "$DOWN_LIST" ]] && fmt_down_k8s "$DOWN_LIST"; [[ -n "$HOST_DOWN_LIST" ]] && fmt_down_host "$HOST_DOWN_LIST" )"

# ── 4. verdict ────────────────────────────────────────────────────────────────
if (( CLUSTER_OK == 0 )); then
  KIND="cluster-down"; STATUS="🔴 Asgard boot — Kubernetes did not come up"
elif (( TOTAL_DOWN == 0 )); then
  KIND="ok"; STATUS="🟢 Asgard boot complete — all services up"
else
  KIND="degraded"; STATUS="🔴 Asgard boot — ${TOTAL_DOWN} service(s) did not start"
fi

# ── 5. compose Discord payload (as Odin) ──────────────────────────────────────
PAYLOAD="$(KIND="$KIND" STATUS="$STATUS" UP_N="$UP_N" ACTIVE_N="$ACTIVE_N" \
  IDLE_N="$IDLE_N" HOST_UP_N="$HOST_UP_N" HOST_N="$HOST_N" TOTAL_DOWN="$TOTAL_DOWN" \
  DOWN_PRETTY="$DOWN_PRETTY" CLUSTER_OK="$CLUSTER_OK" ELAPSED="$ELAPSED" \
  HOSTN="$HOST" NOW="$NOW" python3 -c '
import json, os
kind = os.environ["KIND"]
color = {"ok": 3066993, "degraded": 15158332, "cluster-down": 15158332}.get(kind, 9807270)
down = os.environ["DOWN_PRETTY"].strip()
cluster_ok = os.environ["CLUSTER_OK"] == "1"
if kind == "ok":
    desc = "✅ Every Asgard service with desired replicas came up cleanly."
elif not cluster_ok:
    desc = "❌ kubectl could not reach the cluster within the boot window (OrbStack / K3s not up?).\n_All K8s service states unknown — only host services were probed._"
else:
    lines = down.split("\n") if down else []
    shown = lines[:25]
    desc = "**Did not start:**\n" + "\n".join(shown)
    if len(lines) > 25:
        desc += f"\n…and {len(lines)-25} more"
desc = desc[:4000]
up_n = os.environ["UP_N"]; active_n = os.environ["ACTIVE_N"]
host_up = os.environ["HOST_UP_N"]; host_n = os.environ["HOST_N"]
fields = [
    {"name": "K8s services", "value": f"{up_n}/{active_n} up", "inline": True},
    {"name": "Host services", "value": f"{host_up}/{host_n} up", "inline": True},
    {"name": "Idle (scaled-0)", "value": os.environ["IDLE_N"], "inline": True},
    {"name": "Down", "value": os.environ["TOTAL_DOWN"], "inline": True},
    {"name": "Settle time", "value": os.environ["ELAPSED"] + "s", "inline": True},
    {"name": "Host", "value": os.environ["HOSTN"], "inline": True},
]
print(json.dumps({
    "username": "Odin 🏛️",
    "embeds": [{
        "title": os.environ["STATUS"],
        "description": desc,
        "color": color,
        "fields": fields,
        "footer": {"text": "asgard-boot-report • " + os.environ["NOW"]},
    }],
}))')"

# ── 6. emit / post ────────────────────────────────────────────────────────────
if (( DRY == 1 )); then
  echo "── DRY RUN (not posting) ───────────────────────────────"
  echo "verdict: $STATUS   (settle ${ELAPSED}s, cluster_ok=$CLUSTER_OK)"
  echo "K8s: ${UP_N}/${ACTIVE_N} up, ${IDLE_N} idle, ${DOWN_N} down   Host: ${HOST_UP_N}/${HOST_N} up"
  [[ -n "$DOWN_PRETTY" ]] && { echo "down:"; echo "$DOWN_PRETTY"; }
  echo "── payload ─────────────────────────────────────────────"
  echo "$PAYLOAD" | python3 -m json.tool 2>/dev/null || echo "$PAYLOAD"
  exit 0
fi

if [[ -z "$DISCORD_WEBHOOK" ]]; then
  echo "[boot-report] ERROR: DISCORD_WEBHOOK not set (~/.asgard-watchdog.env) — cannot post" >&2
  exit 1
fi

if curl -s --max-time 15 -H 'Content-Type: application/json' -d "$PAYLOAD" "$DISCORD_WEBHOOK" >/dev/null 2>&1; then
  echo "[boot-report] posted to Discord as Odin ($KIND): ${UP_N}/${ACTIVE_N} k8s up, ${HOST_UP_N}/${HOST_N} host up, ${TOTAL_DOWN} down (settle ${ELAPSED}s)"
else
  echo "[boot-report] WARN: Discord webhook post failed" >&2
  exit 1
fi
