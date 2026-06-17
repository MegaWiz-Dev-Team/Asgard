#!/usr/bin/env bash
#
# asgard-deploy-check — pre-build/redeploy guard against VERSION REGRESSION.
# Complements asgard-build-guard.sh (which guards host disk / memory / cluster
# health) with the code↔DB↔branch version invariants. The two regressions this
# catches — both hit in real incidents:
#   1. sqlx MIGRATION DRIFT — the live DB has migrations applied that the build
#      does NOT embed → the strict migrator PANICS on boot → CrashLoop.
#      (clean-main mimir-api, 2026-06-13.)
#   2. STALE BUILD — the build branch is behind origin/main → you ship old code
#      or lose already-merged features. (dashboard lost the Explorer page.)
# Also surfaces the current deployed image (for rollback) + rollout safety.
#
# Read-only. Exit: 0 = OK, 1 = WARN (look before you leap), 2 = FAIL (do NOT deploy).
#
# Usage:   asgard-deploy-check.sh [deploy-name]            # default: mimir-api
#   env:   REPO       (default ~/Developer/Mimir)
#          BRANCH     (default: current checkout branch)
#          NS         (default: asgard)            — namespace of the deploy
#          MIG_DIR    (default: ro-ai-bridge/mimir-core-ai/migrations) — "" to skip
#          DB_NS DB_DEPLOY DB DB_USER DB_PASS      (default: asgard-infra mariadb mimir root root)
set -uo pipefail
SVC="${1:-mimir-api}"
REPO="${REPO:-$HOME/Developer/Mimir}"
NS="${NS:-asgard}"
MIG_DIR="${MIG_DIR:-ro-ai-bridge/mimir-core-ai/migrations}"
DB_NS="${DB_NS:-asgard-infra}"; DB_DEPLOY="${DB_DEPLOY:-mariadb}"; DB="${DB:-mimir}"
DB_USER="${DB_USER:-root}"; DB_PASS="${DB_PASS:-root}"
RC=0; warn(){ echo "  ⚠️  $*"; [ "$RC" -lt 1 ] && RC=1; }; fail(){ echo "  ❌ $*"; RC=2; }; ok(){ echo "  ✓ $*"; }

echo "▶ asgard-deploy-check: $SVC  (repo=$REPO ns=$NS)"

# ── 1. build source: right branch, clean tree, not behind main ──────────────
echo "1) build source"
if [ -d "$REPO/.git" ]; then
  cd "$REPO" || exit 3
  BR="${BRANCH:-$(git branch --show-current)}"
  echo "   branch: $BR"
  [ -n "$(git status --porcelain)" ] && warn "working tree DIRTY — docker build snapshots the dir; uncommitted/other-session edits will leak into the image. Commit/stash first." || ok "working tree clean"
  git fetch origin main --quiet 2>/dev/null
  BEHIND=$(git rev-list --count "HEAD..origin/main" 2>/dev/null || echo "?")
  AHEAD=$(git rev-list --count "origin/main..HEAD" 2>/dev/null || echo "?")
  if [ "${BEHIND:-0}" != "0" ] && [ "$BEHIND" != "?" ]; then
    warn "branch is $BEHIND commits BEHIND origin/main → risk of shipping stale code / losing merged features. Merge main first, or build from main."
  else ok "up to date with origin/main (ahead $AHEAD)"; fi
else warn "REPO not a git repo: $REPO"; fi

# ── 2. MIGRATION DRIFT (the boot-panic killer) ──────────────────────────────
echo "2) sqlx migration drift ($MIG_DIR vs $DB_NS/$DB)"
if [ -n "$MIG_DIR" ] && [ -d "$REPO/$MIG_DIR" ]; then
  # versions the build will EMBED (on-disk = exactly what docker build copies)
  ls "$REPO/$MIG_DIR"/*.sql 2>/dev/null | sed -E 's#.*/([0-9]+)_.*#\1#' | grep -E '^[0-9]+$' | LC_ALL=C sort -u > /tmp/.dc_embed
  # versions APPLIED in the live DB
  if kubectl -n "$DB_NS" exec -i "deploy/$DB_DEPLOY" -- mariadb -u"$DB_USER" -p"$DB_PASS" -N "$DB" \
       -e "SELECT version FROM _sqlx_migrations" 2>/dev/null | LC_ALL=C sort -u > /tmp/.dc_applied && [ -s /tmp/.dc_applied ]; then
    MISSING=$(comm -23 /tmp/.dc_applied /tmp/.dc_embed)   # applied ∉ build → PANIC
    PENDING=$(comm -13 /tmp/.dc_applied /tmp/.dc_embed)   # build ∉ applied → run on boot
    if [ -n "$MISSING" ]; then
      fail "DB has $(echo "$MISSING"|grep -c .) migration(s) the build does NOT embed → mimir-api will PANIC on boot (sqlx strict). Land them to this branch first:"
      echo "$MISSING" | sed 's/^/        applied-not-in-build: /'
    else ok "every applied migration is embedded (no boot-panic risk)"; fi
    if [ -n "$PENDING" ]; then
      warn "$(echo "$PENDING"|grep -c .) migration(s) will RUN on boot (not yet applied) → BACKUP THE DB FIRST + review for conflicts:"
      echo "$PENDING" | sed 's/^/        pending: /'
    else ok "0 pending — boot runs no migration (zero DB mutation)"; fi
  else warn "could not read _sqlx_migrations from $DB_NS/$DB_DEPLOY — verify manually"; fi
else echo "   (skipped — MIG_DIR empty or absent; non-sqlx service)"; fi

# ── 3. rollback readiness + rollout safety ──────────────────────────────────
echo "3) rollback + rollout safety"
IMG=$(kubectl -n "$NS" get deploy "$SVC" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
PP=$(kubectl -n "$NS" get deploy "$SVC" -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}' 2>/dev/null)
RP=$(kubectl -n "$NS" get deploy "$SVC" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null)
MU=$(kubectl -n "$NS" get deploy "$SVC" -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)
if [ -n "$IMG" ]; then
  ok "current image (roll back to this if the new one fails): $IMG   [pullPolicy=$PP]"
  echo "        rollback: kubectl -n $NS set image deploy/$SVC $SVC=$IMG"
  [ "$PP" = "Never" ] && echo "        ↳ pullPolicy=Never ⇒ build a LOCAL image with a DISTINCT tag (don't overwrite the running tag in place)."
  [ -n "$RP" ] && ok "readinessProbe=$RP, maxUnavailable=$MU → a crashlooping new pod will NOT drop service (rolls back to old pod)." \
                || warn "NO readinessProbe → a broken new pod could take traffic. Add one before relying on rolling updates."
else warn "deploy $SVC not found in ns $NS"; fi

echo "── verdict: $([ $RC -eq 0 ] && echo OK || ([ $RC -eq 1 ] && echo WARN || echo 'FAIL — do not deploy'))  (also run asgard-build-guard.sh for host/disk/cluster)"
exit $RC
