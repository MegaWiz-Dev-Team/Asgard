#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  install-ca-client — trust the Asgard root CA on a *client* Mac       ║
# ║  (a MacBook, NOT the mini). No kubectl needed: it pulls the cert      ║
# ║  from the ca-portal the mini publishes.                              ║
# ║                                                                      ║
# ║  Usage:                                                              ║
# ║    sudo bash install-ca-client.sh                 # default mini IP  ║
# ║    sudo bash install-ca-client.sh 100.107.26.89   # explicit host    ║
# ║    sudo bash install-ca-client.sh ca.asgard.internal   # on tailnet  ║
# ║    sudo bash install-ca-client.sh <host> --hosts  # also map names   ║
# ║                                                                      ║
# ║  Idempotent. The 10-year root means you run this once per Mac.       ║
# ╚══════════════════════════════════════════════════════════════════════╝
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then echo "Run with sudo:  sudo bash $0 $*" >&2; exit 1; fi

MINI="${1:-100.107.26.89}"      # Tailscale IP of the mini by default
DO_HOSTS=0; [[ "${2:-}" == "--hosts" ]] && DO_HOSTS=1
PORT="8079"
BASE="http://${MINI}:${PORT}"
CN="Asgard Private Enterprise Root CA"
KEYCHAIN="/Library/Keychains/System.keychain"
OB="/opt/homebrew/bin/openssl"; [[ -x "$OB" ]] || OB="openssl"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fp256(){ "$OB" x509 -in "$1" -noout -fingerprint -sha256 | sed 's/.*=//; s/://g'; }

echo "==> Fetching root CA from $BASE"
curl -fsS --max-time 15 "$BASE/asgard-root-ca.crt" -o "$TMP/ca.crt"
curl -fsS --max-time 15 "$BASE/fingerprint.sha256.txt" -o "$TMP/fp.txt" 2>/dev/null || true

# Validate: must be a CA, currently valid, and self-consistent with the
# published fingerprint (guards against a tampered download on plain HTTP).
"$OB" x509 -in "$TMP/ca.crt" -noout -ext basicConstraints 2>/dev/null | grep -qi 'CA:TRUE' \
  || { echo "ERROR: downloaded file is not a CA cert"; exit 1; }
"$OB" x509 -in "$TMP/ca.crt" -noout -checkend 0 >/dev/null 2>&1 \
  || { echo "ERROR: cert is expired"; exit 1; }
GOT="$(fp256 "$TMP/ca.crt")"
PUB="$(tr -d '[:space:]' < "$TMP/fp.txt" 2>/dev/null || true)"
if [[ -n "$PUB" && "$PUB" != "$GOT" ]]; then
  echo "ERROR: fingerprint mismatch (download=$GOT published=$PUB) — possible tampering, aborting"; exit 1
fi
echo "    SHA-256: $GOT"
echo "    Expires: $("$OB" x509 -in "$TMP/ca.crt" -noout -enddate | sed 's/.*=//')"
echo "    >>> verify the SHA-256 above matches the mini before trusting <<<"

# Already trusted?
ALREADY=0
security find-certificate -a -c "$CN" -p "$KEYCHAIN" 2>/dev/null > "$TMP/have.pem" || true
if [[ -s "$TMP/have.pem" ]]; then
  awk -v d="$TMP" 'BEGIN{n=0}/-----BEGIN CERTIFICATE-----/{n++}{print >> (d"/h-"n".pem")}' "$TMP/have.pem"
  for f in "$TMP"/h-*.pem; do [[ -s "$f" ]] && [[ "$(fp256 "$f")" == "$GOT" ]] && ALREADY=1; done
fi

if [[ "$ALREADY" == "1" ]]; then
  echo "==> Already trusted in System keychain — nothing to do"
else
  echo "==> Importing into System keychain as trusted root"
  security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$TMP/ca.crt"
  echo "    ✅ trusted"
fi

if [[ "$DO_HOSTS" == "1" ]]; then
  echo "==> Mapping *.asgard.internal in /etc/hosts (off-tailnet fallback)"
  curl -fsS --max-time 15 "$BASE/asgard-hosts.txt" -o "$TMP/hosts.txt"
  BODY="$(grep -vE '^\s*#' "$TMP/hosts.txt" | grep -v '^\s*$')"
  # Replace any prior asgard block, marked for clean re-runs.
  sed -i '' '/# >>> asgard >>>/,/# <<< asgard <<</d' /etc/hosts 2>/dev/null || true
  { echo "# >>> asgard >>>"; echo "$BODY"; echo "# <<< asgard <<<"; } >> /etc/hosts
  echo "    added:"; echo "$BODY" | sed 's/^/      /'
fi

echo ""
echo "Done. Test:  curl -I https://embla.asgard.internal:8443   (on tailnet, no -k needed)"
