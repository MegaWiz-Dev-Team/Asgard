#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  asgard-ca-expiry-check — SAFETY NET (no root needed)                 ║
# ║                                                                      ║
# ║  Independent watchdog for the Asgard root CA trust anchor. Even if    ║
# ║  the root LaunchDaemon (com.asgard.ca-distributor) is never installed ║
# ║  or dies, this SCREAMS before the trust store silently expires — the  ║
# ║  exact failure that broke *.asgard.internal on 2026-07-08.           ║
# ║                                                                      ║
# ║  Checks, read-only, as the user (no keychain writes → no sudo):      ║
# ║   1. the newest Asgard root in the System keychain — days until it   ║
# ║      expires (alert if < THRESHOLD or already expired)               ║
# ║   2. DRIFT: does the keychain actually trust the CURRENT cluster     ║
# ║      root fingerprint? (catches key-preserving re-issues not synced) ║
# ║                                                                      ║
# ║  Alerts to Discord (reuses ~/.asgard-watchdog.env) + logs + exit≠0.  ║
# ║  Runs via com.asgard.ca-expiry-watch (user LaunchAgent, daily).      ║
# ╚══════════════════════════════════════════════════════════════════════╝
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export KUBECONFIG="${KUBECONFIG:-/Users/mimir/.kube/config}"

CN="Asgard Private Enterprise Root CA"
KEYCHAIN="/Library/Keychains/System.keychain"
THRESHOLD_DAYS="${ASGARD_CA_WARN_DAYS:-30}"
NS="cert-manager"; SECRET="asgard-root-secret"
LOG_DIR="/Users/mimir/Developer/Asgard/logs"; LOG="$LOG_DIR/ca-expiry-check.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

[[ -f "$HOME/.asgard-watchdog.env" ]] && source "$HOME/.asgard-watchdog.env"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

log()    { echo "$(/bin/date -u +%FT%TZ) $*" | tee -a "$LOG" >&2; }
notify() { [[ -z "$DISCORD_WEBHOOK" ]] && return 0
  curl -s --max-time 10 -H 'Content-Type: application/json' \
    -d "{\"username\":\"Heimdall\",\"content\":\"🔐 CA-watch: $1\"}" "$DISCORD_WEBHOOK" >/dev/null 2>&1 || true; }
fp256()  { openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//; s/://g'; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PROBLEM=0

# ── 1. Newest Asgard root in the System keychain → days to expiry ─────────
security find-certificate -a -c "$CN" -p "$KEYCHAIN" 2>/dev/null > "$TMP/kc.pem" || true
if [[ ! -s "$TMP/kc.pem" ]]; then
  log "CRITICAL: no '$CN' found in System keychain — *.asgard.internal is UNTRUSTED"
  notify "❌ no Asgard root in System keychain — HTTPS to *.asgard.internal is broken. Install: sudo bash ~/Developer/Asgard/scripts/install-ca-autorenew.sh"
  exit 2
fi
awk -v d="$TMP" 'BEGIN{n=0} /-----BEGIN CERTIFICATE-----/{n++} {print >> (d"/a-"n".pem")}' "$TMP/kc.pem"
NOW=$(/bin/date -u +%s); BEST_LEFT=-999999; BEST_END=""; BEST_FP=""
KC_FPS=""
for f in "$TMP"/a-*.pem; do
  [[ -s "$f" ]] || continue
  KC_FPS="$KC_FPS $(fp256 "$f")"
  end="$(openssl x509 -in "$f" -noout -enddate 2>/dev/null | sed 's/.*=//')"
  [[ -z "$end" ]] && continue
  end_s=$(/bin/date -j -f "%b %e %T %Y %Z" "$end" +%s 2>/dev/null || echo 0)
  left=$(( (end_s - NOW) / 86400 ))
  if (( left > BEST_LEFT )); then BEST_LEFT=$left; BEST_END="$end"; BEST_FP="$(fp256 "$f")"; fi
done
log "keychain newest Asgard root: fp=${BEST_FP:0:16}… expires '$BEST_END' (${BEST_LEFT}d left)"
if (( BEST_LEFT < 0 )); then
  log "CRITICAL: keychain Asgard root EXPIRED ${BEST_LEFT#-}d ago"
  notify "❌ System-keychain Asgard root EXPIRED ($BEST_END). *.asgard.internal HTTPS broken. Fix: sudo bash ~/Developer/Asgard/scripts/install-ca-autorenew.sh"
  PROBLEM=2
elif (( BEST_LEFT < THRESHOLD_DAYS )); then
  log "WARN: keychain Asgard root expires in ${BEST_LEFT}d (< ${THRESHOLD_DAYS}d)"
  notify "⚠️ System-keychain Asgard root expires in ${BEST_LEFT}d ($BEST_END). Ensure com.asgard.ca-distributor is running (it auto-syncs re-issues)."
  PROBLEM=1
fi

# ── 2. DRIFT: does the keychain trust the CURRENT cluster root? ───────────
kubectl get secret "$SECRET" -n "$NS" -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d > "$TMP/live.crt" 2>/dev/null || true
[[ -s "$TMP/live.crt" ]] || kubectl get secret "$SECRET" -n "$NS" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > "$TMP/live.crt" 2>/dev/null || true
if [[ -s "$TMP/live.crt" ]] && openssl x509 -in "$TMP/live.crt" -noout >/dev/null 2>&1; then
  LIVE_FP="$(fp256 "$TMP/live.crt")"
  if [[ " $KC_FPS " == *" $LIVE_FP "* ]]; then
    log "OK: keychain trusts the live cluster root ($LIVE_FP)"
  else
    log "DRIFT: cluster root fp=$LIVE_FP is NOT trusted in the keychain — a re-issue was not distributed"
    notify "⚠️ Keychain has DRIFTED from the cluster root (re-issue not synced). Run: sudo launchctl kickstart -k system/com.asgard.ca-distributor  (or the install script if not yet installed)"
    PROBLEM=$(( PROBLEM > 1 ? PROBLEM : 1 ))
  fi
else
  log "note: could not reach cluster to compare (kubectl/OrbStack down) — skipped drift check"
fi

(( PROBLEM == 0 )) && log "OK: Asgard root trust healthy (${BEST_LEFT}d headroom)"
exit "$PROBLEM"
