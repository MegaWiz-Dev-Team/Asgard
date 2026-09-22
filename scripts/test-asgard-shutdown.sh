#!/usr/bin/env bash
#
# test-asgard-shutdown — verify asgard-shutdown.sh's control flow WITHOUT any
# real side effect. For each scenario it builds a sandbox, shims the dangerous
# commands (orb / launchctl / osascript / sudo) and the heavy helpers
# (asgard-preflight.sh / nightly-backup.sh) so every invocation is *logged* but
# never executed for real, runs the REAL script (copied in), then asserts which
# commands were — and were NOT — called, plus the exit code.
#
# Safe to run anytime: it touches only a mktemp sandbox. Exit 0 = all pass.
set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/asgard-shutdown.sh"
[[ -f "$SRC" ]] || { echo "FATAL: asgard-shutdown.sh not found next to this test"; exit 2; }

GREEN='\033[0;32m'; RED='\033[0;31m'; BLU='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0
pass()  { PASS=$((PASS+1)); echo -e "    ${GREEN}✓${NC} $1"; }
faild() { FAIL=$((FAIL+1)); echo -e "    ${RED}✗ $1${NC}"; }

want_call() { grep -qF "$2" "$1/calls.log" && pass "$3" || faild "$3 — expected call '$2' not found"; }
no_call()   { grep -qF "$2" "$1/calls.log" && faild "$3 — unexpected call '$2'" || pass "$3"; }
want_rc()   { [[ "$2" == "$3" ]] && pass "$4 (rc=$2)" || faild "$4 — rc=$2 expected $3"; }

make_sandbox() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/bin" "$d/t7"; : > "$d/calls.log"
  cp "$SRC" "$d/asgard-shutdown.sh"; chmod +x "$d/asgard-shutdown.sh"

  # fake orb — stateful: status reflects whether 'stop' has run; honors ORB_STOP_FAILS
  cat > "$d/bin/orb" <<EOF
#!/usr/bin/env bash
echo "orb \$*" >> "$d/calls.log"
case "\$1" in
  status) [[ -f "$d/.stopped" ]] && echo Stopped || echo Running ;;
  stop)   [[ "\${ORB_STOP_FAILS:-0}" == 1 ]] && exit 1; touch "$d/.stopped" ;;
esac
EOF
  # fake launchctl — 'list' returns the heimdall labels so the script's grep matches
  cat > "$d/bin/launchctl" <<EOF
#!/usr/bin/env bash
echo "launchctl \$*" >> "$d/calls.log"
[[ "\$1" == list ]] && printf '%s\n' com.asgard.heimdall-gateway com.asgard.heimdall-mlx com.asgard.heimdall-vlm-q4 com.asgard.heimdall-vlm-q8 com.asgard.heimdall-vlm-qwen2
exit 0
EOF
  # fake osascript — succeeds unless OSA_FAILS=1 (to exercise the sudo fallback)
  cat > "$d/bin/osascript" <<EOF
#!/usr/bin/env bash
echo "osascript \$*" >> "$d/calls.log"
[[ "\${OSA_FAILS:-0}" == 1 ]] && exit 1 || exit 0
EOF
  # fake sudo — log only, never actually elevate/run
  cat > "$d/bin/sudo" <<EOF
#!/usr/bin/env bash
echo "sudo \$*" >> "$d/calls.log"; exit 0
EOF
  chmod +x "$d/bin/"*

  # fake helpers in SCRIPT_DIR (the script calls these by \${SCRIPT_DIR}/name)
  cat > "$d/asgard-preflight.sh" <<EOF
#!/usr/bin/env bash
echo "preflight \$*" >> "$d/calls.log"; exit \${PREFLIGHT_EXIT:-0}
EOF
  cat > "$d/nightly-backup.sh" <<EOF
#!/usr/bin/env bash
echo "nightly-backup \$*" >> "$d/calls.log"; exit 0
EOF
  chmod +x "$d/asgard-preflight.sh" "$d/nightly-backup.sh"

  # a FRESH backup on the fake T7 by default → backup gate says "fresh enough"
  : > "$d/t7/asgard_medical.sql.gz"
  echo "$d"
}
make_stale() { touch -t 202001010000 "$1/t7/"*.sql.gz; }

# run the copied script in sandbox $1 with the rest as flags; echoes its exit code.
# fault vars (ORB_STOP_FAILS/OSA_FAILS/PREFLIGHT_EXIT) are inherited from the env.
exec_script() {
  local d="$1"; shift
  PATH="$d/bin:$PATH" T7_BASE="$d/t7" "$d/asgard-shutdown.sh" "$@" >"$d/out.log" 2>&1
  echo $?
}
fresh_env() { unset ORB_STOP_FAILS OSA_FAILS PREFLIGHT_EXIT; }

echo -e "${BLU}▶ test-asgard-shutdown — shimmed behavioral checks${NC}"

# ── S1: default (stop only), fresh backup ─────────────────────────────────
echo -e "\n${BLU}S1${NC} default  →  orb stop, no power-off, no backup"
fresh_env; D=$(make_sandbox); RC=$(exec_script "$D" -y)
want_rc   "$D" "$RC" 0          "exit clean"
want_call "$D" "preflight"      "preflight ran"
want_call "$D" "orb stop"       "stack stopped"
no_call   "$D" "osascript"      "did NOT power off"
no_call   "$D" "sudo shutdown"  "did NOT sudo-shutdown"
no_call   "$D" "launchctl bootout" "did NOT touch host services"
no_call   "$D" "nightly-backup" "no backup (already fresh)"

# ── S2: --poweroff (happy path) ───────────────────────────────────────────
echo -e "\n${BLU}S2${NC} --poweroff  →  orb stop THEN graceful Apple-Event shutdown"
fresh_env; D=$(make_sandbox); RC=$(exec_script "$D" --poweroff -y)
want_rc   "$D" "$RC" 0          "exit clean"
want_call "$D" "orb stop"       "stack stopped first"
want_call "$D" "osascript"      "Apple-Event shutdown issued"
no_call   "$D" "sudo shutdown"  "sudo fallback NOT used (osascript succeeded)"

# ── S3: --poweroff but orb stop FAILS → must abort, NOT power off ──────────
echo -e "\n${BLU}S3${NC} --poweroff + orb stop fails  →  abort, never power off"
fresh_env; export ORB_STOP_FAILS=1; D=$(make_sandbox); RC=$(exec_script "$D" --poweroff -y)
want_rc   "$D" "$RC" 1          "aborted (non-zero)"
want_call "$D" "orb stop"       "attempted stop"
no_call   "$D" "osascript"      "did NOT power off after failed stop"
no_call   "$D" "sudo shutdown"  "did NOT sudo-shutdown after failed stop"

# ── S4: --poweroff, osascript fails → sudo fallback ───────────────────────
echo -e "\n${BLU}S4${NC} --poweroff + Apple-Event fails  →  sudo shutdown fallback"
fresh_env; export OSA_FAILS=1; D=$(make_sandbox); RC=$(exec_script "$D" --poweroff -y)
want_rc   "$D" "$RC" 0          "exit clean"
want_call "$D" "osascript"      "tried Apple-Event first"
want_call "$D" "sudo shutdown"  "fell back to sudo shutdown"

# ── S5: --stop-host ───────────────────────────────────────────────────────
echo -e "\n${BLU}S5${NC} --stop-host  →  bootout heimdall services, no power-off"
fresh_env; D=$(make_sandbox); RC=$(exec_script "$D" --stop-host -y)
want_rc   "$D" "$RC" 0              "exit clean"
want_call "$D" "launchctl bootout" "stopped host services"
want_call "$D" "orb stop"          "stack stopped"
no_call   "$D" "osascript"         "did NOT power off"

# ── S6: stale backup + --skip-backup → no backup ──────────────────────────
echo -e "\n${BLU}S6${NC} stale backup + --skip-backup  →  backup skipped"
fresh_env; D=$(make_sandbox); make_stale "$D"; RC=$(exec_script "$D" --skip-backup -y)
want_rc   "$D" "$RC" 0          "exit clean"
no_call   "$D" "nightly-backup" "backup skipped despite staleness"
want_call "$D" "orb stop"       "stack still stopped"

# ── S7: stale backup, no skip → backup runs first ─────────────────────────
echo -e "\n${BLU}S7${NC} stale backup  →  fresh backup taken before stop"
fresh_env; D=$(make_sandbox); make_stale "$D"; RC=$(exec_script "$D" -y)
want_rc   "$D" "$RC" 0          "exit clean"
want_call "$D" "nightly-backup" "stale → backup ran"
want_call "$D" "orb stop"       "then stopped"

# ── S8: preflight FAIL but -y proceeds ────────────────────────────────────
echo -e "\n${BLU}S8${NC} preflight FAIL + -y  →  warns but proceeds"
fresh_env; export PREFLIGHT_EXIT=2; D=$(make_sandbox); RC=$(exec_script "$D" -y)
want_rc   "$D" "$RC" 0          "exit clean"
want_call "$D" "orb stop"       "proceeded past FAIL with -y"

# ── S9: no -y (no tty) → cancels before doing anything ────────────────────
echo -e "\n${BLU}S9${NC} interactive, no tty  →  cancels at confirm, touches nothing"
fresh_env; D=$(make_sandbox); RC=$(exec_script "$D")
want_rc   "$D" "$RC" 0          "clean cancel"
no_call   "$D" "preflight"      "cancelled before preflight"
no_call   "$D" "orb stop"       "never stopped anything"

# ── summary ───────────────────────────────────────────────────────────────
echo -e "\n═══════════════════════"
echo -e "Result: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
(( FAIL == 0 )) && exit 0 || exit 1
