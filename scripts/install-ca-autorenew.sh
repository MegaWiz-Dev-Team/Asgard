#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  install-ca-autorenew — one-time privileged installer                ║
# ║                                                                      ║
# ║  Installs the Asgard root-CA auto-distribution system:               ║
# ║    • com.asgard.ca-distributor  (root, every 6h + at boot)           ║
# ║    • com.asgard.ca-portal       (LAN download page on :8079)         ║
# ║                                                                      ║
# ║  Run ONCE:  sudo bash install-ca-autorenew.sh                        ║
# ║  Re-runnable / idempotent.                                           ║
# ╚══════════════════════════════════════════════════════════════════════╝
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run with sudo:  sudo bash $0" >&2; exit 1
fi

SCRIPTS="/Users/mimir/Developer/Asgard/scripts"
LAUNCHD_SRC="$SCRIPTS/launchd"
DEST="/Library/LaunchDaemons"
DIST_DIR="/usr/local/share/asgard/ca-dist"
DAEMONS=(com.asgard.ca-distributor com.asgard.ca-portal)

echo "==> Creating published dir $DIST_DIR"
install -d -o mimir -g staff -m 0755 "$DIST_DIR"

echo "==> Installing LaunchDaemon plists into $DEST"
for d in "${DAEMONS[@]}"; do
  install -o root -g wheel -m 0644 "$LAUNCHD_SRC/$d.plist" "$DEST/$d.plist"
done

echo "==> (Re)bootstrapping daemons"
for d in "${DAEMONS[@]}"; do
  launchctl bootout "system/$d" 2>/dev/null || true
  launchctl bootstrap system "$DEST/$d.plist"
  launchctl enable "system/$d"
done

echo "==> Kicking off the first distribution now"
launchctl kickstart -k "system/com.asgard.ca-distributor"

sleep 3
echo ""
echo "==> Result"
LIVE_FP=$(/opt/homebrew/bin/kubectl --kubeconfig=/Users/mimir/.kube/config \
  get secret asgard-root-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | /opt/homebrew/bin/openssl x509 -noout -fingerprint -sha256 | sed 's/.*=//; s/://g')
KC_FP=$(security find-certificate -a -c "Asgard Private Enterprise Root CA" -p \
  /Library/Keychains/System.keychain 2>/dev/null \
  | /opt/homebrew/bin/openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//; s/://g')
echo "    live cluster root fp : $LIVE_FP"
echo "    System keychain  fp  : $KC_FP"
[[ "$LIVE_FP" == "$KC_FP" ]] && echo "    ✅ keychain in sync with cluster" \
                            || echo "    ⚠️  not yet matching — see $SCRIPTS/../logs/ca-distributor.log"
echo ""
echo "    LAN portal: http://$(scutil --get LocalHostName).local:8079/   (and http://$(ipconfig getifaddr en0 2>/dev/null || echo 192.168.1.129):8079/)"
echo ""
echo "Done. Status:  launchctl print system/com.asgard.ca-distributor | grep state"
