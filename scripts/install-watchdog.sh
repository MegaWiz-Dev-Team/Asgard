#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  install-watchdog — deploy the host health watchdog to a STABLE path  ║
# ║                                                                       ║
# ║  Copies asgard-watchdog.sh + asgard-preflight.sh to ~/bin (decoupled  ║
# ║  from this git checkout, so a branch switch can't swap the live       ║
# ║  script out from under launchd), installs the launchd agent, and      ║
# ║  reloads it.                                                          ║
# ║                                                                       ║
# ║  Run:  bash install-watchdog.sh        (user-level, no sudo)          ║
# ║  Re-runnable / idempotent — re-run after editing either script.       ║
# ║                                                                       ║
# ║  Host enablement (AUTO_RECOVER, DISCORD_WEBHOOK, …) lives in the       ║
# ║  gitignored, chmod-600 ~/.asgard-watchdog.env — NOT managed here.     ║
# ╚══════════════════════════════════════════════════════════════════════╝
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/bin"
LABEL="com.asgard.watchdog"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$BIN" "$HOME/Library/Logs"

# 1. Deploy the watchdog AND its preflight dependency — they must stay
#    co-located: asgard-watchdog.sh resolves asgard-preflight.sh from its own
#    directory ($HERE), so shipping one without the other breaks it.
install -m 0755 "$HERE/asgard-watchdog.sh"  "$BIN/asgard-watchdog.sh"
install -m 0755 "$HERE/asgard-preflight.sh" "$BIN/asgard-preflight.sh"
echo "✓ scripts → $BIN"

# 2. Install + (re)load the launchd agent (points at $BIN, not the git tree).
install -m 0644 "$HERE/launchd/$LABEL.plist" "$PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "✓ launchd agent (re)loaded: $LABEL"

# 3. Smoke test: fire one tick now (RunAtLoad already did, this is belt-and-braces).
launchctl kickstart "gui/$(id -u)/$LABEL" 2>/dev/null || true
echo "✓ kicked one tick — check ~/.asgard-watchdog.log and ~/Library/Logs/asgard-watchdog.out.log"
