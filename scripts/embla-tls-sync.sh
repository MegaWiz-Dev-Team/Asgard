#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  embla-tls-sync — keep the NATIVE Embla engine's TLS leaf in sync     ║
# ║                                                                      ║
# ║  cert-manager auto-RENEWS the leaf (asgard/embla-native-tls, issued   ║
# ║  by asgard-ca-issuer), but the native engine                          ║
# ║  (com.megawiz.embla-engine) reads cert/key from DISK and nothing      ║
# ║  copies the renewed material out of the cluster. asgard-ca-distributor║
# ║  only distributes the ROOT, not leaves — so without this the on-disk  ║
# ║  leaf silently expires and the SwiftUI app (which validates TLS)      ║
# ║  stops talking to the engine. That exact class of failure already bit ║
# ║  once: a TLS flag sat dormant in the plist for 5 weeks and detonated  ║
# ║  on the next reboot (2026-07-15).                                     ║
# ║                                                                      ║
# ║  Idempotent: compares the live secret's fingerprint against what is   ║
# ║  on disk and only writes + restarts the engine when they differ.      ║
# ║  Verifies TLS after the restart and ROLLS BACK if the engine does not ║
# ║  come back healthy.                                                   ║
# ╚══════════════════════════════════════════════════════════════════════╝
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export KUBECONFIG="${KUBECONFIG:-/Users/mimir/.kube/config}"

# ── Config ───────────────────────────────────────────────────────────────
NS="asgard"
SECRET="embla-native-tls"
LABEL="com.megawiz.embla-engine"
TLS_DIR="/Users/mimir/Library/Application Support/Embla/tls"
CERT="$TLS_DIR/cert.pem"
KEY="$TLS_DIR/key.pem"
PROBE="https://127.0.0.1:8088/"          # must validate against the trusted Asgard root
LOG_DIR="/Users/mimir/Developer/Asgard/logs"
LOG="$LOG_DIR/embla-tls-sync.log"
WARN_DAYS=21                              # warn if the leaf expires within this window

[[ -f "$HOME/.asgard-watchdog.env" ]] && source "$HOME/.asgard-watchdog.env"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

mkdir -p "$LOG_DIR" 2>/dev/null || true
log() { echo "$(/bin/date -u +%FT%TZ) $*" | tee -a "$LOG" >&2; }
notify() {
  [[ -z "$DISCORD_WEBHOOK" ]] && return 0
  curl -s --max-time 10 -H 'Content-Type: application/json' \
    -d "{\"username\":\"Heimdall\",\"content\":\"🔐 ${1}\"}" \
    "$DISCORD_WEBHOOK" >/dev/null 2>&1 || true
}
fp256()  { openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//; s/://g'; }
modc()   { openssl x509 -in "$1" -noout -modulus 2>/dev/null | openssl md5; }
modk()   { openssl rsa  -in "$1" -noout -modulus 2>/dev/null | openssl md5; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── 1. Fetch the live leaf from the cluster ──────────────────────────────
fetch() { kubectl get secret "$SECRET" -n "$NS" -o jsonpath="{.data.$1}" 2>/dev/null | base64 -d 2>/dev/null; }
fetch 'tls\.crt' > "$TMP/live.crt" || true
fetch 'tls\.key' > "$TMP/live.key" || true

if [[ ! -s "$TMP/live.crt" || ! -s "$TMP/live.key" ]] || ! openssl x509 -in "$TMP/live.crt" -noout >/dev/null 2>&1; then
  log "ERROR: could not fetch a valid cert/key from secret $NS/$SECRET — leaving disk untouched"
  exit 1
fi

# ── 2. Sanity-gate the new material BEFORE touching a working engine ─────
if ! openssl x509 -in "$TMP/live.crt" -noout -checkend 0 >/dev/null 2>&1; then
  log "ERROR: live leaf is already expired — aborting"; notify "embla-tls-sync: live leaf EXPIRED, not deploying"; exit 1
fi
if [[ "$(modc "$TMP/live.crt")" != "$(modk "$TMP/live.key")" ]]; then
  log "ERROR: live cert/key do not match — aborting"; notify "embla-tls-sync: cert/key mismatch, not deploying"; exit 1
fi
# The SwiftUI app talks to https://127.0.0.1:8088 — without this SAN the app breaks.
if ! openssl x509 -in "$TMP/live.crt" -noout -ext subjectAltName 2>/dev/null | grep -q '127\.0\.0\.1'; then
  log "ERROR: live leaf has no IP:127.0.0.1 SAN — the app would fail TLS; aborting"
  notify "embla-tls-sync: leaf missing 127.0.0.1 SAN, not deploying"; exit 1
fi

LIVE_FP="$(fp256 "$TMP/live.crt")"
DISK_FP="$(fp256 "$CERT" 2>/dev/null || echo none)"
LIVE_END="$(openssl x509 -in "$TMP/live.crt" -noout -enddate | sed 's/.*=//')"

# ── 3. No-op when already in sync (but still warn on an approaching expiry) ──
if [[ "$LIVE_FP" == "$DISK_FP" ]]; then
  if ! openssl x509 -in "$CERT" -noout -checkend $((WARN_DAYS * 86400)) >/dev/null 2>&1; then
    log "WARN: on-disk leaf expires within ${WARN_DAYS}d ($LIVE_END) and cert-manager has not issued a new one yet"
    notify "embla-tls-sync: Embla leaf expires <${WARN_DAYS}d ($LIVE_END) — cert-manager has not renewed yet"
  fi
  exit 0
fi

# ── 4. Install (backup first), restart, verify, roll back on failure ─────
BK="$TLS_DIR/../tls-backup-$(/bin/date +%Y%m%d-%H%M%S)"
mkdir -p "$BK" && cp -p "$CERT" "$KEY" "$BK/" 2>/dev/null || true
log "leaf changed ($DISK_FP -> $LIVE_FP, expires $LIVE_END) — installing; backup at $BK"

install -m 0644 "$TMP/live.crt" "$CERT"
install -m 0600 "$TMP/live.key" "$KEY"
launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

# curl retries handle the engine's startup window; no TLS bypass — this must validate
# against the trusted Asgard root exactly the way the app does.
if curl -s --retry 15 --retry-delay 1 --retry-connrefused --max-time 8 -o /dev/null "$PROBE"; then
  log "OK: engine restarted and serving a VALID chain with the new leaf (expires $LIVE_END)"
  notify "Embla native TLS renewed — engine healthy, leaf valid until $LIVE_END"
  exit 0
fi

log "ERROR: engine unhealthy after new leaf — ROLLING BACK to $BK"
cp -p "$BK/cert.pem" "$CERT" 2>/dev/null || true
cp -p "$BK/key.pem"  "$KEY"  2>/dev/null || true
chmod 600 "$KEY" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
if curl -s --retry 15 --retry-delay 1 --retry-connrefused --max-time 8 -o /dev/null "$PROBE"; then
  log "rollback OK — engine back on the previous leaf"
  notify "⚠️ embla-tls-sync: new leaf FAILED, rolled back — engine healthy on old cert (investigate)"
else
  log "CRITICAL: rollback did not restore a healthy engine — manual intervention needed"
  notify "🚨 embla-tls-sync: new leaf failed AND rollback failed — Embla engine is DOWN"
fi
exit 1
