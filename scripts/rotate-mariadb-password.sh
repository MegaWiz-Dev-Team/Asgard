#!/bin/bash
# Rotate MariaDB password (INC-2026-05-17-001 P0 followup, O1a)
#
# Prompts for new password (silent), then:
#   1. ALTER USER on live MariaDB
#   2. Update asgard-secrets (MARIADB_PASSWORD + MIMIR_DATABASE_URL)
#   3. Reconcile mariadb-secret
#   4. Restart Mimir
#   5. Verify
#
# Backs up the old password to /tmp/ before any change so rollback is possible.

set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${GREEN}MariaDB password rotation${NC}"
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ----- Helpers: URL-encode + SQL-escape -----
# URL-encode keeps only RFC 3986 unreserved chars + percent-encodes the rest.
# Required because MIMIR_DATABASE_URL contains the password as URL userinfo
# and characters like @ : / # ? must be percent-encoded there.
urlencode() {
  local s="$1" i c
  for ((i=0; i<${#s}; i++)); do
    c="${s:$i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
      *)               printf '%%%02X' "'$c" ;;
    esac
  done
}

# SQL-escape for MariaDB string literals: doubles `'` and escapes `\`.
# Both treatments survive default MariaDB sql_mode (with or without
# NO_BACKSLASH_ESCAPES).
sql_escape() {
  local s="$1"
  s="${s//\\/\\\\}"   # backslash → \\
  s="${s//\'/\'\'}"   # single quote → ''
  printf '%s' "$s"
}

# ----- Offer auto-generated URL/SQL-safe password -----
# openssl rand avoids the SIGPIPE landmine that `tr </dev/urandom | head` hits
# under `set -o pipefail` (head closes the pipe → tr exits 141 → script aborts).
SUGGESTED=$(openssl rand -hex 24)
echo "Suggested random password (48-char alphanumeric, safe for URL + SQL):"
echo "  ${YELLOW}${SUGGESTED}${NC}"
echo "Copy/paste this, or type your own. Avoid these chars in custom passwords:"
echo "  @ : / # ? & = % \\ ' \" \$ (they need escaping and break URLs)"
echo

# ----- Prompt for new password (twice) -----
IFS= read -rsp "Enter NEW MariaDB password (hidden): " NEW_PW
echo
IFS= read -rsp "Confirm NEW MariaDB password:        " NEW_PW_CONFIRM
echo
echo

if [ -z "$NEW_PW" ]; then
  echo "${RED}❌ Password empty — abort${NC}"; exit 1
fi
if [ "$NEW_PW" != "$NEW_PW_CONFIRM" ]; then
  echo "${RED}❌ Passwords don't match — abort${NC}"; exit 1
fi
if [ ${#NEW_PW} -lt 16 ]; then
  echo "${YELLOW}⚠  Password is shorter than 16 chars.${NC}"
  read -rp "Continue anyway? (y/N) " yn
  [ "$yn" = "y" ] || exit 1
fi

# Warn (don't block) on chars that REQUIRE encoding. Script handles them
# correctly via urlencode + sql_escape, but a clean alphanumeric password
# is easier to copy/paste between tools.
if [[ "$NEW_PW" =~ [@:/\#\?\&\=\%\\\"\'\$\ ] ]]; then
  echo "${YELLOW}⚠  Password contains chars that need URL/SQL encoding.${NC}"
  echo "    Script handles them correctly, but a clean alphanumeric password"
  echo "    is portable across more tools."
  read -rp "Continue with this password? (y/N) " yn
  [ "$yn" = "y" ] || exit 1
fi

# Compute encoded forms once (used in steps 1, 2, 3)
NEW_PW_URL=$(urlencode "$NEW_PW")
NEW_PW_SQL=$(sql_escape "$NEW_PW")

# ----- Read current password (for backup + rollback) -----
echo "📋 Reading current MariaDB password for rollback…"
CURRENT_PW=$(kubectl get secret asgard-secrets -n asgard \
  -o jsonpath='{.data.MARIADB_PASSWORD}' | base64 -d)

if [ -z "$CURRENT_PW" ]; then
  echo "${RED}❌ Could not read current MARIADB_PASSWORD from asgard-secrets${NC}"; exit 1
fi

BACKUP_FILE="/tmp/asgard-mariadb-rollback-$(date +%Y%m%d-%H%M%S).txt"
umask 077
{
  echo "# MariaDB rotation backup — $(date -Iseconds)"
  echo "# To roll back, set the password back to the value below:"
  echo "OLD_MARIADB_PASSWORD=$CURRENT_PW"
} > "$BACKUP_FILE"
echo "   → backup written to ${BACKUP_FILE} (mode 0600)"

if [ "$NEW_PW" = "$CURRENT_PW" ]; then
  echo "${YELLOW}⚠  New password is the same as the current one — nothing to rotate${NC}"; exit 0
fi

# ----- Verify current password actually works -----
# Pass password via stdin instead of -p to avoid shell-escaping problems
# when the current password contains chars like @ : / etc.
echo "🔍 Verifying current password works against live MariaDB…"
if ! printf '[client]\nuser=mimir\npassword=%s\n' "$CURRENT_PW" | \
     kubectl exec -i -n asgard-infra deploy/mariadb -- \
       sh -c 'cat > /tmp/.my.cnf && mariadb --defaults-file=/tmp/.my.cnf -e "SELECT 1;" ; rm -f /tmp/.my.cnf' \
     >/dev/null 2>&1; then
  echo "${RED}❌ Current password from asgard-secrets does not work against live MariaDB.${NC}"
  echo "   Aborting — the cluster state has drifted further than this script can safely handle."
  echo "   Backup of (broken) current password: ${BACKUP_FILE}"
  exit 1
fi
echo "   ${GREEN}✓${NC} current password verified"

# ----- Final confirmation -----
echo ""
echo "About to:"
echo "  1. ALTER USER 'mimir'@'%' on live MariaDB → new password"
echo "  2. Patch asgard-secrets: MARIADB_PASSWORD + MIMIR_DATABASE_URL"
echo "  3. Run ./scripts/reconcile-mariadb-secret.sh"
echo "  4. Roll restart deployment/mimir-api"
echo ""
echo "Expected Mimir downtime: ~30 seconds (between step 1 and step 4)"
read -rp "Proceed? type 'yes' to continue: " confirm
if [ "$confirm" != "yes" ]; then
  echo "Cancelled. Backup preserved at ${BACKUP_FILE}"; exit 0
fi

# ============================================
# Step 1: ALTER USER
# ============================================
echo ""
echo "🔄 Step 1/4: ALTER USER on MariaDB…"
# Pipe the SQL via stdin so the password (with SQL-escaped quotes) doesn't
# get mangled by the shell -e argument parser.
printf "ALTER USER 'mimir'@'%%' IDENTIFIED BY '%s'; FLUSH PRIVILEGES;\n" "$NEW_PW_SQL" | \
  kubectl exec -i -n asgard-infra deploy/mariadb -- mariadb -u root -proot
echo "   ${GREEN}✓${NC} MariaDB user 'mimir' password rotated"

# ============================================
# Step 2: Patch asgard-secrets
# ============================================
echo ""
echo "🔄 Step 2/4: Patch asgard-secrets…"

# URL: password must be URL-encoded (RFC 3986 userinfo)
NEW_DB_URL="mysql://mimir:${NEW_PW_URL}@mariadb.asgard-infra.svc:3306/mimir"
# Secret stores the RAW password (not URL-encoded) for MARIADB_PASSWORD,
# so kubectl exec / cypher / SDK clients reading it via secretKeyRef get
# the original chars. Only the URL form needs encoding.
NEW_PW_B64=$(printf '%s' "$NEW_PW"      | base64 | tr -d '\n')
NEW_URL_B64=$(printf '%s' "$NEW_DB_URL" | base64 | tr -d '\n')

kubectl patch secret asgard-secrets -n asgard --type=json -p="[
  {\"op\": \"replace\", \"path\": \"/data/MARIADB_PASSWORD\",   \"value\": \"$NEW_PW_B64\"},
  {\"op\": \"replace\", \"path\": \"/data/MIMIR_DATABASE_URL\", \"value\": \"$NEW_URL_B64\"}
]"
echo "   ${GREEN}✓${NC} asgard-secrets updated"

# ============================================
# Step 3: Reconcile mariadb-secret
# ============================================
echo ""
echo "🔄 Step 3/4: Reconcile mariadb-secret with asgard-secrets…"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/reconcile-mariadb-secret.sh"

# ============================================
# Step 4: Restart Mimir
# ============================================
echo ""
echo "🔄 Step 4/4: Rolling restart deployment/mimir-api…"
kubectl rollout restart deployment/mimir-api -n asgard
kubectl rollout status  deployment/mimir-api -n asgard --timeout=90s
echo "   ${GREEN}✓${NC} Mimir restarted"

# ============================================
# Verification
# ============================================
echo ""
echo "🔍 Verifying…"
sleep 3

if printf '[client]\nuser=mimir\npassword=%s\n' "$NEW_PW" | \
   kubectl exec -i -n asgard-infra deploy/mariadb -- \
     sh -c 'cat > /tmp/.my.cnf && mariadb --defaults-file=/tmp/.my.cnf -e "SELECT 1;" ; rm -f /tmp/.my.cnf' \
   >/dev/null 2>&1; then
  echo "   ${GREEN}✓${NC} New password authenticates to MariaDB"
else
  echo "   ${RED}✗${NC} New password failed against MariaDB — investigate immediately"
fi

POD=$(kubectl get pod -n asgard -l app=mimir-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$POD" ]; then
  if kubectl logs "$POD" -n asgard --tail=50 2>&1 | grep -qi "access denied"; then
    echo "   ${RED}✗${NC} Mimir logs show 'Access denied' — rotation may have failed"
  else
    echo "   ${GREEN}✓${NC} Mimir logs clean (no 'Access denied')"
  fi
fi

echo ""
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${GREEN}✅ MariaDB rotation complete${NC}"
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Rollback file (delete when no longer needed):  ${BACKUP_FILE}"
echo ""
echo "Run ./scripts/validate-k8s-before-deploy.sh to confirm Check 5 now passes."
