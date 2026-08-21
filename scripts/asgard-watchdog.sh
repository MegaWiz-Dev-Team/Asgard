#!/usr/bin/env bash
#
# asgard-watchdog — runs asgard-preflight on a timer and raises an alert when
# the cluster/infra degrades. HOST-SIDE on purpose: the 2026-06-12 outage took
# down the in-cluster observability path (Odin) too, so the watchdog must NOT
# depend on the cluster it watches. It writes alerts straight to the OpenSearch
# indexer (which survives cluster outages) and to a local log.
#
# Debounced: alerts once on OK→DEGRADED, re-alerts only every REPEAT_EVERY ticks
# while still degraded, and once on DEGRADED→RECOVERED. No per-tick spam.
#
# Meant to be driven by launchd (com.asgard.watchdog) every ~5 min, or run by hand.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFLIGHT="${PREFLIGHT:-$HERE/asgard-preflight.sh}"
STATE="${STATE:-$HOME/.asgard-watchdog.state}"
LOG="${LOG:-$HOME/.asgard-watchdog.log}"

ALERT_THRESHOLD="${ALERT_THRESHOLD:-2}"   # 2=FAIL only, 1=also WARN
REPEAT_EVERY="${REPEAT_EVERY:-12}"        # re-alert every N ticks while degraded (~1h at 5min)

# Opt-in auto-recovery (INC-2026-06-15): when a runtime wedge is detected, restart
# OrbStack (`orbctl stop/start`, the documented fix). OFF by default — restarting
# the cluster is disruptive; set AUTO_RECOVER=1 to enable. Guards: wedge signal
# only, at most once per cooldown, alert before + after.
AUTO_RECOVER="${AUTO_RECOVER:-0}"
RECOVER_AFTER_TICKS="${RECOVER_AFTER_TICKS:-3}"       # require N consecutive wedge ticks (~15min @5min) before restarting — debounce transient blips
RECOVER_COOLDOWN="${RECOVER_COOLDOWN:-3600}"          # seconds (max 1 restart/hour)
RECOVER_STATE="${RECOVER_STATE:-$HOME/.asgard-watchdog.recover}"
ORBCTL="${ORBCTL:-$(command -v orbctl 2>/dev/null || echo /usr/local/bin/orbctl)}"

INDEXER_URL="${INDEXER_URL:-https://localhost:30920}"
INDEXER_USER="${INDEXER_USER:-admin}"
INDEXER_PASS="${INDEXER_PASS:-admin}"
INDEX="${INDEX:-asgard-alerts}"

# Secrets/overrides (e.g. DISCORD_WEBHOOK) live in a gitignored, chmod-600 file —
# NOT committed. launchd has no shell env, so we source it explicitly.
[[ -f "$HOME/.asgard-watchdog.env" ]] && source "$HOME/.asgard-watchdog.env"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HOST=$(scutil --get LocalHostName 2>/dev/null || hostname)

# run preflight (read-only)
JSON=$("$PREFLIGHT" --json 2>/dev/null); CODE=$?

# previous state
PREV_CODE=0; SINCE=0
if [[ -f "$STATE" ]]; then read -r PREV_CODE SINCE < "$STATE" 2>/dev/null || true; fi
[[ "$PREV_CODE" =~ ^[0-9]+$ ]] || PREV_CODE=0
[[ "$SINCE" =~ ^[0-9]+$ ]] || SINCE=0

degraded() { (( $1 >= ALERT_THRESHOLD )); }

ACTION="none"
if degraded "$CODE"; then
  if ! degraded "$PREV_CODE"; then ACTION="degraded"; SINCE=1
  else SINCE=$((SINCE+1)); (( SINCE % REPEAT_EVERY == 0 )) && ACTION="reminder"; fi
else
  if degraded "$PREV_CODE"; then ACTION="recovered"; fi
  SINCE=0
fi

printf '%s %s\n' "$CODE" "$SINCE" > "$STATE"
printf '%s code=%s action=%s %s\n' "$NOW" "$CODE" "$ACTION" "$JSON" >> "$LOG"

# Heartbeat: every tick, publish the CURRENT health snapshot (id=current) so Odin /
# agents can read live status (not just transition alerts). Best-effort.
HEARTBEAT=$(JSON="$JSON" NOW="$NOW" HOST="$HOST" CODE="$CODE" python3 -c '
import json,os
pf=json.loads(os.environ["JSON"])
print(json.dumps({"@timestamp":os.environ["NOW"],"ts":os.environ["NOW"],"source":"asgard-watchdog","kind":"heartbeat","host":os.environ["HOST"],"code":int(os.environ["CODE"]),"status":pf.get("status"),"fail":pf.get("fail",[]),"warn":pf.get("warn",[]),"fail_count":len(pf.get("fail",[]))}))' 2>/dev/null)
[ -n "$HEARTBEAT" ] && curl -sk --max-time 10 -u "$INDEXER_USER:$INDEXER_PASS" \
  -X PUT "$INDEXER_URL/$INDEX/_doc/current" \
  -H 'Content-Type: application/json' --data-binary "$HEARTBEAT" >/dev/null 2>&1

send_alert() {
  local kind="$1"
  local doc
  doc=$(JSON="$JSON" NOW="$NOW" HOST="$HOST" KIND="$kind" CODE="$CODE" python3 -c '
import json,os
pf=json.loads(os.environ["JSON"])
print(json.dumps({
  "@timestamp": os.environ["NOW"],
  "source": "asgard-watchdog",
  "host": os.environ["HOST"],
  "kind": os.environ["KIND"],
  "code": int(os.environ["CODE"]),
  "status": pf.get("status"),
  "fail": pf.get("fail", []),
  "warn": pf.get("warn", []),
  "fail_count": len(pf.get("fail", [])),
}))') || return 1
  curl -sk --max-time 12 -u "$INDEXER_USER:$INDEXER_PASS" \
    -X POST "$INDEXER_URL/$INDEX/_doc?refresh=wait_for" \
    -H 'Content-Type: application/json' --data-binary "$doc" >/dev/null 2>&1 \
    && echo "[watchdog] alert sent ($kind) → $INDEX" \
    || echo "[watchdog] WARN: could not reach indexer to send $kind alert"

  send_discord "$kind"
}

# Post a human-readable embed to Discord (only if a webhook is configured).
send_discord() {
  [[ -z "$DISCORD_WEBHOOK" ]] && return 0
  local kind="$1"
  local payload
  payload=$(JSON="$JSON" HOST="$HOST" KIND="$kind" NOW="$NOW" python3 -c '
import json,os
pf=json.loads(os.environ["JSON"]); kind=os.environ["KIND"]
color={"degraded":15158332,"reminder":15105570,"recovered":3066993}.get(kind,9807270)  # red/orange/green
emoji={"degraded":"🔴","reminder":"🟠","recovered":"🟢"}.get(kind,"⚪")
title={"degraded":"Asgard DEGRADED","reminder":"Asgard still degraded","recovered":"Asgard RECOVERED"}.get(kind,"Asgard")
fails=pf.get("fail",[]) or pf.get("warn",[])
# Discord embed: cap field length to stay under limits
desc="\n".join("• "+f for f in fails[:12]) or "all checks passing"
if len(fails)>12: desc+=f"\n…and {len(fails)-12} more"
print(json.dumps({"embeds":[{
  "title":f"{emoji} {title}",
  "description":desc[:3900],
  "color":color,
  "fields":[{"name":"status","value":str(pf.get("status")),"inline":True},
            {"name":"failing","value":str(len(pf.get("fail",[]))),"inline":True},
            {"name":"host","value":os.environ["HOST"],"inline":True}],
  "footer":{"text":"asgard-watchdog • "+os.environ["NOW"]}
}]}))') || return 0
  curl -s --max-time 12 -H 'Content-Type: application/json' \
    -d "$payload" "$DISCORD_WEBHOOK" >/dev/null 2>&1 \
    && echo "[watchdog] Discord notified ($kind)" \
    || echo "[watchdog] WARN: Discord webhook post failed"
}

# Opt-in: restart OrbStack on a sustained runtime wedge (INC-2026-06-15). Only
# fires on the wedge signal, after ≥RECOVER_AFTER_TICKS consecutive degraded
# ticks (debounce), at most once per cooldown, alerts before + after. No-op
# unless AUTO_RECOVER=1, so it can't surprise-restart the cluster.
maybe_auto_recover() {
  [[ "$AUTO_RECOVER" == "1" ]] || return 0
  degraded "$CODE" || return 0
  printf '%s' "$JSON" | grep -qiE 'cluster unreachable|Terminating >1h|sandbox|PLEG|OrbStack' || return 0
  # debounce: only on a SUSTAINED wedge, not a one-off blip. SINCE is the
  # consecutive-degraded counter from the state machine above.
  if (( SINCE < RECOVER_AFTER_TICKS )); then
    echo "[watchdog] auto-recover armed (wedge ${SINCE}/${RECOVER_AFTER_TICKS} ticks — holding)"; return 0
  fi
  local last=0 now; [[ -f "$RECOVER_STATE" ]] && last=$(cat "$RECOVER_STATE" 2>/dev/null || echo 0)
  now=$(date +%s)
  if (( now - last < RECOVER_COOLDOWN )); then
    echo "[watchdog] auto-recover suppressed (cooldown — last $(( now - last ))s ago)"; return 0
  fi
  echo "$now" > "$RECOVER_STATE"
  echo "[watchdog] 🛠️ AUTO-RECOVER: runtime wedge → $ORBCTL stop/start"
  [[ -n "$DISCORD_WEBHOOK" ]] && curl -s --max-time 10 -H 'Content-Type: application/json' \
    -d '{"content":"🛠️ asgard-watchdog AUTO-RECOVER: runtime wedge — restarting OrbStack (orbctl stop/start)"}' \
    "$DISCORD_WEBHOOK" >/dev/null 2>&1
  "$ORBCTL" stop >/dev/null 2>&1; sleep 3; "$ORBCTL" start >/dev/null 2>&1
  [[ -n "$DISCORD_WEBHOOK" ]] && curl -s --max-time 10 -H 'Content-Type: application/json' \
    -d '{"content":"✅ asgard-watchdog: OrbStack restarted — pods rescheduling"}' \
    "$DISCORD_WEBHOOK" >/dev/null 2>&1
}

case "$ACTION" in
  degraded)  echo "[watchdog] OK→DEGRADED (code=$CODE)"; send_alert "degraded" ;;
  reminder)  echo "[watchdog] still degraded (${SINCE} ticks)"; send_alert "reminder" ;;
  recovered) echo "[watchdog] DEGRADED→RECOVERED"; send_alert "recovered" ;;
  none)      echo "[watchdog] code=$CODE, no state change" ;;
esac

# Evaluated EVERY tick (not only on alert transitions) so the ≥N-tick debounce
# can fire mid-streak; its own guards decide whether it actually restarts.
maybe_auto_recover

exit 0
