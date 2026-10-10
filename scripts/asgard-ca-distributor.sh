#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  asgard-ca-distributor — auto-distribute the Asgard root CA           ║
# ║                                                                      ║
# ║  cert-manager auto-RENEWS the root cert (asgard-root-secret).        ║
# ║  Nothing auto-DISTRIBUTES it, so trust stores drift and silently    ║
# ║  expire. This pulls the live root from the cluster and keeps it in   ║
# ║  sync everywhere a human would otherwise have to:                    ║
# ║    1. macOS System keychain  (trusted anchor on this host)           ║
# ║    2. published .crt files   (repo + stable system path)             ║
# ║    3. a LAN portal directory (served by com.asgard.ca-portal)        ║
# ║                                                                      ║
# ║  Idempotent: re-imports only when the live fingerprint differs from  ║
# ║  what is already trusted, and prunes only EXPIRED Asgard roots so a  ║
# ║  key-rotation transition window keeps both anchors trusted.          ║
# ║                                                                      ║
# ║  Designed to run as root via launchd (keychain writes need root).    ║
# ╚══════════════════════════════════════════════════════════════════════╝
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export KUBECONFIG="${KUBECONFIG:-/Users/mimir/.kube/config}"

# ── Config ───────────────────────────────────────────────────────────────
NS="cert-manager"
SECRET="asgard-root-secret"
CN="Asgard Private Enterprise Root CA"
KEYCHAIN="/Library/Keychains/System.keychain"
DIST_DIR="/usr/local/share/asgard/ca-dist"          # served on the LAN
REPO_CRT="/Users/mimir/Developer/Mimir/docs/certs/asgard-root-ca.crt"
LOG_DIR="/Users/mimir/Developer/Asgard/logs"
LOG="$LOG_DIR/ca-distributor.log"
PORTAL_PORT="8079"

# Discord webhook (same gitignored, chmod-600 file the watchdog uses)
[[ -f "$HOME/.asgard-watchdog.env" ]] && source "$HOME/.asgard-watchdog.env"
[[ -f "/Users/mimir/.asgard-watchdog.env" ]] && source "/Users/mimir/.asgard-watchdog.env"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

mkdir -p "$LOG_DIR" "$DIST_DIR" 2>/dev/null || true

log() { echo "$(/bin/date -u +%FT%TZ) $*" | tee -a "$LOG" >&2; }

notify() {  # $1 = message ; best-effort, never fails the run
  [[ -z "$DISCORD_WEBHOOK" ]] && return 0
  local msg="$1"
  curl -s --max-time 10 -H 'Content-Type: application/json' \
    -d "{\"username\":\"Heimdall\",\"content\":\"🔐 ${msg}\"}" \
    "$DISCORD_WEBHOOK" >/dev/null 2>&1 || true
}

fp256() { openssl x509 -in "$1" -noout -fingerprint -sha256 | sed 's/.*=//; s/://g'; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. Fetch the live root cert from the cluster ─────────────────────────
fetch_field() { kubectl get secret "$SECRET" -n "$NS" -o jsonpath="{.data.$1}" 2>/dev/null | base64 -d 2>/dev/null; }
fetch_field 'ca\.crt'  > "$TMP/live.crt" || true
[[ -s "$TMP/live.crt" ]] || fetch_field 'tls\.crt' > "$TMP/live.crt"

if [[ ! -s "$TMP/live.crt" ]] || ! openssl x509 -in "$TMP/live.crt" -noout >/dev/null 2>&1; then
  log "ERROR: could not fetch a valid root cert from secret $NS/$SECRET — aborting (leaving trust stores untouched)"
  exit 1
fi
# sanity: must be a CA and currently valid
if ! openssl x509 -in "$TMP/live.crt" -noout -ext basicConstraints 2>/dev/null | grep -qi 'CA:TRUE'; then
  log "ERROR: fetched cert is not a CA — aborting"; exit 1
fi
if ! openssl x509 -in "$TMP/live.crt" -noout -checkend 0 >/dev/null 2>&1; then
  log "ERROR: live root cert is already expired — aborting"; exit 1
fi

LIVE_FP="$(fp256 "$TMP/live.crt")"
LIVE_END="$(openssl x509 -in "$TMP/live.crt" -noout -enddate | sed 's/.*=//')"
CHANGED=0

# ── 2. Publish files (idempotent) ────────────────────────────────────────
publish() {  # $1 = dest path
  local dest="$1"
  if ! cmp -s "$TMP/live.crt" "$dest" 2>/dev/null; then
    install -m 0644 "$TMP/live.crt" "$dest" && log "published -> $dest" && CHANGED=1
  fi
}
publish "$DIST_DIR/asgard-root-ca.crt"
cp -f "$DIST_DIR/asgard-root-ca.crt" "$DIST_DIR/asgard-root-ca.pem" 2>/dev/null || true
echo "$LIVE_FP" > "$DIST_DIR/fingerprint.sha256.txt"
[[ -d "$(dirname "$REPO_CRT")" ]] && publish "$REPO_CRT"
# Make the client installer downloadable from the portal too (for MacBooks).
CLIENT_SH="$(dirname "$0")/install-ca-client.sh"
[[ -f "$CLIENT_SH" ]] && install -m 0644 "$CLIENT_SH" "$DIST_DIR/install-ca-client.sh" 2>/dev/null || true

# LAN/tailnet portal landing page + hosts snippet (always regenerated; cheap).
# Detect the durable Tailscale IP (preferred — reachable anywhere on the tailnet
# and DHCP-stable) plus the current LAN IP as a fallback target.
TS_IP="$( { tailscale ip -4 2>/dev/null || /opt/homebrew/bin/tailscale ip -4 2>/dev/null; } | head -1 )"
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
TARGET_IP="${TS_IP:-${LAN_IP:-127.0.0.1}}"   # where *.asgard.internal should point

# Hosts-file snippet for devices NOT on the tailnet (tailnet devices resolve via
# dnsmasq split-DNS automatically). Names come from the live ingress routes.
ASG_HOSTS="$(kubectl get ingress -A -o jsonpath='{range .items[*]}{range .spec.rules[*]}{.host} {end}{end}' 2>/dev/null \
  | tr ' ' '\n' | grep -i 'asgard\.internal' | sort -u | tr '\n' ' ')"
{
  echo "# Asgard *.asgard.internal -> mini. Append to /etc/hosts on non-tailnet devices."
  echo "# (Tailnet devices get this automatically via dnsmasq split-DNS.)"
  echo "${TARGET_IP}  ${ASG_HOSTS}"
} > "$DIST_DIR/asgard-hosts.txt"

# Build the list of download URLs (friendly tailnet name first, then raw IPs).
DL_HOSTS=""
[[ -n "$TS_IP"  ]] && DL_HOSTS="$DL_HOSTS ca.asgard.internal $TS_IP"
[[ -n "$LAN_IP" ]] && DL_HOSTS="$DL_HOSTS $LAN_IP"
LINKS=""
for h in $DL_HOSTS; do LINKS="${LINKS}<li><code>http://${h}:${PORTAL_PORT}/asgard-root-ca.crt</code></li>"; done

cat > "$DIST_DIR/index.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Asgard Root CA</title>
<style>body{font:15px -apple-system,system-ui,sans-serif;max-width:720px;margin:40px auto;padding:0 16px;color:#1a1a1a}
code{background:#f3f3f3;padding:2px 6px;border-radius:4px;word-break:break-all}
pre{background:#f3f3f3;padding:12px;border-radius:6px;overflow:auto}
a.btn{display:inline-block;background:#2d6cdf;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none;margin:8px 0}
small{color:#666}h3{margin-top:1.6em}</style></head><body>
<h1>🔐 Asgard Private Enterprise Root CA</h1>
<p>Install this certificate once to trust every <code>*.asgard.internal</code> endpoint.
This root is valid for <b>10 years</b>, so you won't need to repeat this until it rotates.</p>
<p><a class="btn" href="asgard-root-ca.crt" download>Download asgard-root-ca.crt</a></p>
<p><b>Expires:</b> ${LIVE_END}<br>
<b>SHA-256 fingerprint — verify this matches before trusting:</b><br><code>${LIVE_FP}</code></p>
<h3>Download links</h3><ul>${LINKS}</ul>

<h3>📱 Android</h3>
<ol><li>Download the .crt above.</li>
<li>Settings → Security → <i>Encryption &amp; credentials</i> → <i>Install a certificate</i> → <b>CA certificate</b> → pick the file (a screen lock/PIN is required).</li>
<li>Browsers (Chrome) trust it immediately (a "network monitored" notice is normal). Non-browser apps only trust user CAs if they opt in — Android limitation.</li>
<li>Names resolve automatically when the phone is on the tailnet (Tailscale app installed).</li></ol>

<h3>🍎 iPhone / iPad</h3>
<ol><li>Open this page in <b>Safari</b> → Download → Settings → <i>Profile Downloaded</i> → Install.</li>
<li>Settings → General → About → <i>Certificate Trust Settings</i> → enable trust for the Asgard root.</li></ol>

<h3>💻 macOS</h3>
<pre>sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain asgard-root-ca.crt</pre>

<h3>🐧 Linux</h3>
<pre>sudo cp asgard-root-ca.crt /usr/local/share/ca-certificates/ &amp;&amp; sudo update-ca-certificates</pre>

<h3>Resolving the names</h3>
<p>On the <b>tailnet</b> nothing extra is needed — <code>*.asgard.internal</code> resolves via split-DNS.
Off-tailnet, append <a href="asgard-hosts.txt">asgard-hosts.txt</a> to your <code>/etc/hosts</code>.</p>
<p><small>Auto-published by com.asgard.ca-distributor — always reflects the live cluster root.</small></p>
</body></html>
HTML

# ── 3. macOS System keychain sync ────────────────────────────────────────
# Collect SHA-256 fingerprints currently trusted under this CN.
security find-certificate -a -c "$CN" -p "$KEYCHAIN" 2>/dev/null > "$TMP/trusted.pem" || true
TRUSTED_FPS=""
if [[ -s "$TMP/trusted.pem" ]]; then
  awk -v d="$TMP" 'BEGIN{n=0} /-----BEGIN CERTIFICATE-----/{n++} {print >> (d"/kc-"n".pem")}' "$TMP/trusted.pem"
  for f in "$TMP"/kc-*.pem; do
    [[ -s "$f" ]] || continue
    TRUSTED_FPS="${TRUSTED_FPS} $(fp256 "$f")"
  done
fi

if [[ " $TRUSTED_FPS " == *" $LIVE_FP "* ]]; then
  log "keychain already trusts live root ($LIVE_FP) — no import needed"
else
  if security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$DIST_DIR/asgard-root-ca.crt" 2>>"$LOG"; then
    log "IMPORTED new root into System keychain: fp=$LIVE_FP exp=$LIVE_END"
    notify "Asgard root CA updated in System keychain — new fp \`${LIVE_FP:0:16}…\` valid until ${LIVE_END}"
    CHANGED=1
  else
    log "ERROR: keychain import failed (need root? run via com.asgard.ca-distributor LaunchDaemon)"
  fi
fi

# ── 4. Prune ONLY expired Asgard roots (keep current + transition anchors) ─
if [[ -s "$TMP/trusted.pem" ]]; then
  for f in "$TMP"/kc-*.pem; do
    [[ -s "$f" ]] || continue
    if ! openssl x509 -in "$f" -noout -checkend 0 >/dev/null 2>&1; then
      sha1="$(openssl x509 -in "$f" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
      if security delete-certificate -Z "$sha1" "$KEYCHAIN" >/dev/null 2>&1; then
        log "pruned expired root from keychain (sha1=$sha1)"; CHANGED=1
      fi
    fi
  done
fi

if [[ "$CHANGED" == "1" ]]; then
  log "sync complete — CHANGES applied (live fp=$LIVE_FP exp=$LIVE_END)"
else
  log "sync complete — already in sync (live fp=$LIVE_FP exp=$LIVE_END)"
fi
