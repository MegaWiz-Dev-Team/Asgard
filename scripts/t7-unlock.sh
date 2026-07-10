#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  🏰 ASGARD — T7 Shield auto-unlock (APFS Encrypted)          ║
# ╚══════════════════════════════════════════════════════════════╝
# Unlocks + mounts the encrypted APFS volume "T7 Shield" at login.
# Passphrase: ~/.asgard-t7-passphrase (0600; off-site copy in Secret Manager
# `asgard-t7-passphrase`, project asgard-489513).
# Scheduled via launchd `com.asgard.t7-unlock` (RunAtLoad). Dependent services
# (eir-cgm-minio, vor-img) are KeepAlive=true and self-heal once mounted.
set -uo pipefail

PF="$HOME/.asgard-t7-passphrase"
LOG="$HOME/Library/Logs/t7-unlock.log"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

if [ -d "/Volumes/T7 Shield" ]; then
  log "already mounted — nothing to do"
  exit 0
fi
if [ ! -f "$PF" ]; then
  log "FAIL: passphrase file missing ($PF)"
  exit 1
fi

# Wait up to ~60s for the disk to enumerate after boot, then unlock by name.
# apfs-list line: "APFS Volume Disk (Role):   disk4s1 (No specific role)" → id is $5.
for i in $(seq 1 12); do
  VOLID=$(diskutil apfs list 2>/dev/null | awk '/APFS Volume Disk/{id=$5} /Name:.*T7 Shield/{print id; exit}')
  if [ -n "${VOLID:-}" ]; then
    if printf %s "$(cat "$PF")" | diskutil apfs unlockVolume "$VOLID" -stdinpassphrase >> "$LOG" 2>&1; then
      log "unlocked + mounted ${VOLID}"
      exit 0
    fi
    log "unlock attempt failed for ${VOLID} (try $i)"
  fi
  sleep 5
done
log "FAIL: T7 Shield volume not found/unlockable after wait"
exit 1
