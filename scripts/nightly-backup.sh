#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  🏰 ASGARD — Nightly Backup Wrapper                          ║
# ╚══════════════════════════════════════════════════════════════╝
# Wraps backup-full-k8s.sh for scheduled (launchd) execution:
#   guard (T7 mounted) → disk headroom check → backup → rotate → heartbeat → notify
#
# Scheduled via launchd `com.asgard.nightly-backup` (03:00 daily).
# Retention: keep last RETAIN dated backup dirs on T7.
#
# Manual run / dry test:  ./scripts/nightly-backup.sh
set -uo pipefail

T7="/Volumes/T7 Shield"
SCRIPT_DIR="/Users/mimir/Developer/Asgard/scripts"
LOG_DIR="/Users/mimir/Developer/Asgard/logs"
HEARTBEAT="${T7}/asgard-backups/last-backup-status.txt"
RETAIN=30
TS=$(date +%Y-%m-%d_%H%M%S)

mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/nightly-backup.log"
log()    { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Asgard Backup\"" 2>/dev/null || true; }
# Discord embed ($1=color $2=title $3=desc) — reuses the watchdog webhook config.
discord_notify() {
  [ -f "$HOME/.asgard-watchdog.env" ] && . "$HOME/.asgard-watchdog.env" 2>/dev/null
  [ -z "${DISCORD_WEBHOOK:-}" ] && return 0
  local payload
  payload=$(DN_C="$1" DN_T="$2" DN_D="$3" DN_TS="$TS" python3 -c 'import json,os;print(json.dumps({"embeds":[{"title":os.environ["DN_T"],"description":os.environ["DN_D"],"color":int(os.environ["DN_C"]),"footer":{"text":"asgard nightly-backup • "+os.environ["DN_TS"]}}]}))' 2>/dev/null)
  [ -n "$payload" ] && curl -s --max-time 12 -H 'Content-Type: application/json' -d "$payload" "$DISCORD_WEBHOOK" >/dev/null 2>&1
}

log "════════ nightly backup start (${TS}) ════════"

# 1. Guard — T7 mounted AND writable (don't run a half-backup onto the boot disk)
if [ ! -d "$T7" ] || ! touch "${T7}/.write-test" 2>/dev/null; then
  log "FAIL: T7 not mounted/writable — skipping run"
  notify "T7 not mounted — nightly backup skipped"
  discord_notify 15105570 "🟠 Asgard Backup SKIPPED" "T7 ไม่ได้ mount/เขียนไม่ได้ — nightly backup ข้ามรอบนี้ (เสียบ T7 แล้วรันมือ: nightly-backup.sh)"
  mkdir -p "$(dirname "$HEARTBEAT")" 2>/dev/null || true
  printf "last_run=%s\nstatus=SKIPPED_NO_T7\n" "$TS" > "$HEARTBEAT" 2>/dev/null || true
  exit 1
fi
rm -f "${T7}/.write-test"

# 2. Host disk headroom (the real constraint — warn under 20 GB)
FREE_GB=$(df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}')
log "host disk free: ${FREE_GB:-?} GB"
if [ "${FREE_GB:-0}" -lt 20 ]; then
  log "WARN: host disk < 20 GB free before backup"
  notify "host disk low (${FREE_GB}GB) — backup proceeding"
fi

# 3. Run the full backup (writes to T7/asgard-backup-<DATE>/)
"${SCRIPT_DIR}/backup-full-k8s.sh" >>"$LOG" 2>&1
RC=$?
log "backup-full-k8s.sh exit=${RC}"

# 4. Rotate — keep the newest RETAIN dated dirs, delete older
ls -dt "${T7}"/asgard-backup-* 2>/dev/null | tail -n +$((RETAIN+1)) | while read -r d; do
  log "rotate: removing old backup ${d}"
  rm -rf "$d"
done

# 5. Heartbeat — single glanceable status file on T7
LATEST=$(ls -dt "${T7}"/asgard-backup-* 2>/dev/null | head -1)
# NOTE: `grep -c` prints "0" but EXITS 1 when there are no FAIL rows (the normal,
# healthy case). The old `|| echo "?"` then appended "?", making FAILS="0\n?" —
# which is != "0" and != "?", so every successful backup falsely fired the
# "🔴 ISSUES" alert (and leaked a stray "?"). Capture only grep's stdout; use "?"
# solely when the manifest is missing/unreadable (empty result).
FAILS=$(grep -c "| FAIL |" "${LATEST}/MANIFEST.md" 2>/dev/null || true)
[ -n "$FAILS" ] || FAILS="?"
SIZE=$(du -sh "$LATEST" 2>/dev/null | cut -f1)
KEPT=$(ls -d "${T7}"/asgard-backup-* 2>/dev/null | wc -l | tr -d ' ')
{
  echo "last_run=${TS}"
  echo "exit_code=${RC}"
  echo "latest=${LATEST}"
  echo "size=${SIZE}"
  echo "failed_components=${FAILS}"
  echo "retained_backups=${KEPT}"
} > "$HEARTBEAT"
log "heartbeat: size=${SIZE} fails=${FAILS} retained=${KEPT}"

# 5b. Off-site mirror → GCS (optional, for disaster recovery — T7 is a single drive).
# Config in ~/.asgard-watchdog.env:
#   GCS_BACKUP_BUCKET=asgard-archive   (bucket name, no gs://)
#   GCS_SA_KEY=/path/to/sa-key.json    (service account key — for UNATTENDED auth;
#                                        user-login tokens expire and break 3AM runs)
#   GCS_MIRROR_DOW=7                    (1=Mon..7=Sun to upload; "*"=every night; default 7)
#   GCS_STORAGE_CLASS=COLDLINE  GCS_PROJECT=asgard-489513
GCS_STATUS="off (GCS_BACKUP_BUCKET not set)"
[ -f "$HOME/.asgard-watchdog.env" ] && . "$HOME/.asgard-watchdog.env" 2>/dev/null
if [ -n "${GCS_BACKUP_BUCKET:-}" ] && [ -n "${LATEST:-}" ]; then
  DOW=$(date +%u); WANT="${GCS_MIRROR_DOW:-7}"
  if [ "$WANT" = "*" ] || [ "$DOW" = "$WANT" ]; then
    [ -n "${GCS_SA_KEY:-}" ] && [ -f "${GCS_SA_KEY}" ] && \
      gcloud auth activate-service-account --key-file="${GCS_SA_KEY}" --project="${GCS_PROJECT:-asgard-489513}" >>"$LOG" 2>&1
    DEST_URI="gs://${GCS_BACKUP_BUCKET}/infra-backups/$(basename "$LATEST")"
    log "GCS mirror → ${DEST_URI}"
    if gcloud storage cp -r "$LATEST" "gs://${GCS_BACKUP_BUCKET}/infra-backups/" \
         --storage-class="${GCS_STORAGE_CLASS:-COLDLINE}" >>"$LOG" 2>&1; then
      GCS_STATUS="OK → ${DEST_URI}"; log "GCS mirror OK"
    else
      GCS_STATUS="FAILED (check gcloud auth / SA key)"; log "GCS mirror FAILED"
    fi
  else
    GCS_STATUS="skipped (weekly: uploads on DOW=${WANT}, today=${DOW})"
  fi
fi
log "gcs: ${GCS_STATUS}"

# 6. Notify on any problem (non-zero exit OR a FAIL row in the manifest)
if [ "$RC" -ne 0 ] || { [ "$FAILS" != "0" ] && [ "$FAILS" != "?" ]; }; then
  notify "needs attention: ${FAILS} failed component(s), rc=${RC}"
  discord_notify 15158332 "🔴 Asgard Backup ISSUES" "fails=${FAILS} • rc=${RC} • size=${SIZE} • gcs: ${GCS_STATUS}"
  log "════════ FINISHED WITH ISSUES (fails=${FAILS}, rc=${RC}) ════════"
  exit 2
fi
discord_notify 3066993 "🟢 Asgard Backup OK" "size=${SIZE} • retained=${KEPT} backups • gcs: ${GCS_STATUS}"
log "════════ nightly backup OK (${SIZE}) ════════"
