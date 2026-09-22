#!/usr/bin/env bash
#
# asgard-shutdown — graceful, data-safe shutdown of the Asgard stack on this
# Mac mini. Codifies the manual procedure that avoids the failure mode behind
# INC-2026-06-12 (a dirty stop → MariaDB / PVC corruption).
#
# Order of operations — each step is gated; nothing destructive runs unless the
# step before it finished cleanly. It NEVER force-kills MariaDB or deletes state:
#   1. read-only preflight        know the state before we touch it
#   2. backup freshness gate      backup-first rule; snapshot if stale
#   3. orb stop (graceful)        SIGTERM to every pod incl. MariaDB → flush
#   4. (opt) stop host services   Heimdall MLX/VLM/gateway launchd jobs
#   5. (opt) power off macOS      graceful Apple Event, sudo only as fallback
#
# Usage:
#   ./asgard-shutdown.sh                stop the stack (orb stop), leave Mac on
#   ./asgard-shutdown.sh --poweroff     stop the stack, then power off the Mac
#   ./asgard-shutdown.sh --stop-host    also stop Heimdall host services
#   ./asgard-shutdown.sh -y             non-interactive (assume yes to prompts)
#   ./asgard-shutdown.sh --skip-backup  skip the backup gate (acknowledged)
#   ./asgard-shutdown.sh --force-backup always snapshot first, even if fresh
# Flags combine, e.g.  ./asgard-shutdown.sh --poweroff -y
#
# Env tunables: BACKUP_MAX_AGE_DAYS (default 1), T7_BASE (default /Volumes/T7 Shield)
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ── flags ─────────────────────────────────────────────────────────────────
POWEROFF=0; STOP_HOST=0; ASSUME_YES=0; SKIP_BACKUP=0; FORCE_BACKUP=0
for a in "$@"; do
  case "$a" in
    --poweroff|-p)  POWEROFF=1 ;;
    --stop-host)    STOP_HOST=1 ;;
    --yes|-y)       ASSUME_YES=1 ;;
    --skip-backup)  SKIP_BACKUP=1 ;;
    --force-backup) FORCE_BACKUP=1 ;;
    -h|--help)      usage ;;
    *) echo "unknown flag: $a (try --help)"; exit 64 ;;
  esac
done

# ── tunables ──────────────────────────────────────────────────────────────
BACKUP_MAX_AGE_DAYS="${BACKUP_MAX_AGE_DAYS:-1}"
T7_BASE="${T7_BASE:-/Volumes/T7 Shield}"
HEIMDALL_SERVICES=(
  com.asgard.heimdall-gateway
  com.asgard.heimdall-mlx
  com.asgard.heimdall-vlm-q4
  com.asgard.heimdall-vlm-q8
  com.asgard.heimdall-vlm-qwen2
)

GREEN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[1;33m'; BLU='\033[0;34m'; NC='\033[0m'
say()  { echo -e "$@"; }
step() { echo -e "\n${BLU}▶ $*${NC}"; }
ok()   { echo -e "  ${GREEN}✅ $*${NC}"; }
warn() { echo -e "  ${YEL}⚠️  $*${NC}"; }
err()  { echo -e "  ${RED}❌ $*${NC}"; }
die()  { echo -e "\n${RED}ABORT:${NC} $*"; exit 1; }

# Plain-text prompts only (read -p does not interpret color escapes).
confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  local ans=""
  read -r -p "  $1 [y/N] " ans </dev/tty || ans=""
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ── banner ────────────────────────────────────────────────────────────────
echo -e "${BLU}🏰 Asgard safe shutdown${NC}"
if [[ $POWEROFF -eq 1 ]]; then
  echo -e "   plan: stop stack → ${RED}power off the Mac mini${NC}"
else
  echo -e "   plan: stop stack (orb stop), leave the Mac powered on"
fi
[[ $STOP_HOST -eq 1 ]] && echo -e "         + stop Heimdall host services"
confirm "Proceed?" || { echo "cancelled."; exit 0; }

# ── 1. preflight (read-only) ──────────────────────────────────────────────
step "1/5  Pre-shutdown health (read-only)"
if [[ -x "${SCRIPT_DIR}/asgard-preflight.sh" ]]; then
  "${SCRIPT_DIR}/asgard-preflight.sh"
  case $? in
    0) ok "preflight clean" ;;
    1) warn "preflight WARN (see above) — safe to continue a graceful stop" ;;
    2) warn "preflight FAIL (see above). A FAIL such as a wedged pod does NOT"
       warn "block a graceful stop — but review it before powering off."
       confirm "Continue with shutdown anyway?" || die "stopped at preflight gate" ;;
  esac
else
  warn "asgard-preflight.sh not found/executable — skipping health gate"
fi

# ── 2. backup freshness gate (backup-first rule) ──────────────────────────
step "2/5  Backup gate"
if [[ $SKIP_BACKUP -eq 1 ]]; then
  warn "--skip-backup: not snapshotting (acknowledged)"
else
  AGE_D=""
  if [[ -d "$T7_BASE" ]]; then
    NEWEST=$(find "$T7_BASE" -maxdepth 4 -name '*.sql.gz' -type f 2>/dev/null \
             | while IFS= read -r f; do stat -f '%m' "$f"; done | sort -rn | head -1)
    [[ -n "$NEWEST" ]] && AGE_D=$(( ( $(date +%s) - NEWEST ) / 86400 ))
  else
    warn "T7 not mounted — cannot verify or refresh backups"
  fi

  if [[ $FORCE_BACKUP -eq 1 ]] || { [[ -n "$AGE_D" ]] && (( AGE_D > BACKUP_MAX_AGE_DAYS )); }; then
    if [[ $FORCE_BACKUP -eq 1 ]]; then say "  --force-backup requested"
    else warn "newest DB backup ${AGE_D}d old (> ${BACKUP_MAX_AGE_DAYS}d)"; fi
    if confirm "Run a fresh backup now (nightly-backup.sh, can take minutes)?"; then
      step "    backing up → T7 …"
      "${SCRIPT_DIR}/nightly-backup.sh" \
        && ok "backup complete" \
        || warn "backup returned non-zero — check logs/nightly-backup.log before relying on it"
    else
      warn "skipping backup at user request"
    fi
  elif [[ -n "$AGE_D" ]]; then
    ok "newest DB backup ${AGE_D}d old (≤ ${BACKUP_MAX_AGE_DAYS}d) — fresh enough"
  fi
fi

# ── 3. graceful stack stop (orb stop) ─────────────────────────────────────
step "3/5  Stopping OrbStack (graceful SIGTERM → MariaDB flushes & exits cleanly)"
command -v orb >/dev/null 2>&1 || die "orb CLI not found — cannot stop the cluster gracefully"
STATUS=$(orb status 2>/dev/null || true)
if [[ "$STATUS" == "Stopped" ]]; then
  ok "OrbStack already stopped"
else
  orb stop || die "orb stop failed — NOT powering off; investigate before forcing"
  STATUS=$(orb status 2>/dev/null || true)
  [[ "$STATUS" == "Stopped" ]] \
    && ok "OrbStack stopped cleanly" \
    || die "OrbStack did not reach 'Stopped' (got: ${STATUS:-?}) — investigate"
fi

# ── 4. host-native services (optional) ────────────────────────────────────
step "4/5  Heimdall host services"
if [[ $STOP_HOST -eq 1 ]]; then
  for svc in "${HEIMDALL_SERVICES[@]}"; do
    launchctl list 2>/dev/null | grep -q "$svc" || continue
    launchctl bootout "gui/$(id -u)/$svc" 2>/dev/null \
      && ok "stopped $svc" \
      || warn "could not stop $svc (may already be down)"
  done
  warn "host services reload on next login/boot (RunAtLoad)"
elif [[ $POWEROFF -eq 1 ]]; then
  ok "leaving Heimdall to macOS shutdown to stop gracefully"
else
  ok "left running (stateless inference). Pass --stop-host to also stop them."
fi

# ── 5. power off (optional) ───────────────────────────────────────────────
step "5/5  Power off"
if [[ $POWEROFF -eq 0 ]]; then
  ok "stack stopped, Mac left on. (re-run with --poweroff to also shut down macOS)"
  exit 0
fi
confirm "Power off the Mac mini NOW?" || { warn "stack stopped but power-off cancelled — Mac left on"; exit 0; }
say "  issuing graceful shutdown (Apple Event, no sudo)…"
if osascript -e 'tell application "System Events" to shut down' 2>/dev/null; then
  ok "shutdown signal sent — the Mac will power off shortly"
  ok "if a GUI dialog blocks it, confirm on screen, or the sudo fallback runs below"
else
  warn "Apple Event shutdown failed — falling back to 'sudo shutdown' (asks for password)"
  sudo shutdown -h now
fi
