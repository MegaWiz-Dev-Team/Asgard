#!/usr/bin/env bash
# Behaviour tests for scripts/k3s-deploy.sh against fake docker, kubectl and
# gate scripts. Nothing here touches a real cluster or docker daemon.
#
#   bash tests/k3s_deploy_test.sh
set -uo pipefail

# Fail closed: even if a real kubectl or docker is reached instead of a fake,
# it has no cluster and no daemon to talk to. (2026-10-04: the script once
# prepended /opt/homebrew/bin to PATH, the real kubectl won, and a --no-build
# case restarted the live asgard-portal.)
DEAD_KUBECONFIG="$(mktemp)"
cat > "$DEAD_KUBECONFIG" <<'EOF'
apiVersion: v1
kind: Config
clusters: [{name: dead, cluster: {server: "https://127.0.0.1:1"}}]
contexts: [{name: dead, context: {cluster: dead, user: dead}}]
users: [{name: dead, user: {token: dead}}]
current-context: dead
EOF
export KUBECONFIG="$DEAD_KUBECONFIG" DOCKER_HOST=unix:///nonexistent/docker.sock

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/k3s-deploy.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$DEAD_KUBECONFIG"' EXIT
PASS=0; FAILED=0

# Fake sibling checkouts (DEV_DIR), each a git repo with one commit.
for repo in Mimir Bifrost Hermodr Tyr; do
    mkdir -p "$WORK/dev/$repo"
    git -C "$WORK/dev/$repo" init -q
    git -C "$WORK/dev/$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
done
mkdir -p "$WORK/dev/Mimir/ro-ai-dashboard" "$WORK/dev/Tyr/rules" "$WORK/dev/Tyr/decoders"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$CALLS"
EOF
cat > "$WORK/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "kubectl $*" >> "$CALLS"
case "$*" in
    "cluster-info") exit 0 ;;
    get\ deployment*) [ -n "${LIVE_IMAGE:-}" ] && printf '%s' "$LIVE_IMAGE" && exit 0; exit 1 ;;
    "apply -f -") cat >> "$APPLIED" ;;
    rollout\ status*) [ "${ROLLOUT_FAILS:-0}" = 1 ] && [ ! -e "$UNDONE" ] && exit 1; exit 0 ;;
    rollout\ undo*) touch "$UNDONE" ;;
    exec*) echo '{"status":"ok"}' ;;
    create\ configmap*) echo "kind: ConfigMap" ;;
esac
exit 0
EOF
cat > "$WORK/bin/gate" <<'EOF'
#!/usr/bin/env bash
echo "gate $(basename "$0") $* NS=$NS REPO=$REPO MIG_DIR=$MIG_DIR" >> "$CALLS"
exit "${GATE_RC:-0}"
EOF
cat > "$WORK/bin/build-guard" <<'EOF'
#!/usr/bin/env bash
echo "gate build-guard" >> "$CALLS"
exit "${GUARD_RC:-0}"
EOF
chmod +x "$WORK/bin/"*

# deploy <args...> runs the script with fresh call logs; sets RC and OUT.
deploy() {
    export CALLS="$WORK/calls" APPLIED="$WORK/applied" UNDONE="$WORK/undone"
    rm -f "$CALLS" "$APPLIED" "$UNDONE"; touch "$CALLS" "$APPLIED"
    OUT=$(PATH="$WORK/bin:$PATH" DEV_DIR="$WORK/dev" DEPLOY_CHECK="$WORK/bin/gate" \
          BUILD_GUARD="$WORK/bin/build-guard" bash "$SCRIPT" "$@" 2>&1)
    RC=$?
    if grep -q "Preflight OK" <<< "$OUT" && ! grep -q "^kubectl cluster-info" "$CALLS"; then
        echo "ABORT: the fake kubectl was not used for: $*" >&2
        exit 2
    fi
}

check() {
    local name="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); echo "ok   $name"
    else FAILED=$((FAILED + 1)); echo "FAIL $name"; echo "$OUT" | tail -5 | sed 's/^/     /'; fi
}
called()     { grep -qE -- "$1" "$CALLS"; }
not_called() { ! grep -qE -- "$1" "$CALLS"; }
applied()    { grep -qE -- "$1" "$APPLIED"; }

MIMIR_SHA=$(git -C "$WORK/dev/Mimir" rev-parse --short HEAD)
TAG_RE="asgard-mimir-api:${MIMIR_SHA}-[0-9]{14}"

deploy api
check "api: exits 0"                                 [ "$RC" = 0 ]
check "api: build guard ran"                         called "^gate build-guard"
check "api: deploy-check got the sqlx migrations dir" called "^gate gate mimir-api NS=asgard REPO=$WORK/dev/Mimir MIG_DIR=ro-ai-bridge/mimir-core-ai/migrations"
check "api: built a distinct <sha>-<stamp> tag"      called "^docker build .* -t $TAG_RE "
check "api: never builds :latest"                    not_called ":latest"
check "api: applied manifest carries the new tag"    applied "image: $TAG_RE$"
check "api: no restart when the image changed"       not_called "rollout restart"
check "api: waited for the rollout"                  called "rollout status deployment/mimir-api"

GATE_RC=2 deploy api
check "FAIL gate: exits non-zero"                    [ "$RC" != 0 ]
check "FAIL gate: nothing built"                     not_called "^docker build"
check "FAIL gate: nothing applied"                   not_called "apply"

GUARD_RC=1 deploy api
check "build guard blocks: exits non-zero"           [ "$RC" != 0 ]
check "build guard blocks: no deploy-check, no build" not_called "^(gate gate|docker)"

GATE_RC=1 deploy bifrost
check "WARN gate: stops without --accept-warn"       [ "$RC" != 0 ]
check "WARN gate: nothing built"                     not_called "^docker build"
GATE_RC=1 deploy bifrost --accept-warn
check "WARN gate: --accept-warn proceeds"            [ "$RC" = 0 ]
check "WARN gate: bifrost built from DEV_DIR"        called "^docker build -t asgard-bifrost:[0-9a-f]+-[0-9]{14} -f Bifrost/Dockerfile"

ROLLOUT_FAILS=1 LIVE_IMAGE="asgard-mimir-dashboard:v1.6.0" deploy dashboard
check "failed rollout: exits non-zero"               [ "$RC" != 0 ]
check "failed rollout: rollout undone"               called "rollout undo deployment/mimir-dashboard"
check "failed rollout: names the previous image"     grep -q "asgard-mimir-dashboard:v1.6.0" <<< "$OUT"

LIVE_IMAGE="asgard-portal:csp-20260618" deploy portal --no-build
check "--no-build: exits 0"                          [ "$RC" = 0 ]
check "--no-build: no gates, no build"               not_called "^(gate|docker)"
check "--no-build: re-applies the running image"     applied "image: asgard-portal:csp-20260618$"
check "--no-build: restarts"                         called "rollout restart deployment/asgard-portal"

deploy all --dry-run
check "--dry-run: exits 0"                           [ "$RC" = 0 ]
check "--dry-run: gates still run"                   called "^gate gate asgard-portal"
check "--dry-run: no build, apply or restart"        not_called "^docker|apply|rollout"
check "--dry-run: prints the tagged build"           grep -qE "\+ docker build .* -t $TAG_RE" <<< "$OUT"

deploy tyr
check "tyr: exits 0"                                 [ "$RC" = 0 ]
check "tyr: deploy-check targets hermodr-wazuh"      called "^gate gate hermodr-wazuh NS=wazuh"
check "tyr: bridge applied with the built hermodr"   applied "image: asgard-hermodr:[0-9a-f]+-[0-9]{14}$"
check "tyr: wazuh manifests applied as they are"     called "apply -f $ROOT/k8s/04-security/tyr/03-wazuh-manager.yaml"

deploy nonsense
check "unknown target: exits non-zero"               [ "$RC" != 0 ]
deploy api --bogus
check "unknown option: exits non-zero"               [ "$RC" != 0 ]

echo "$PASS passed, $FAILED failed"
[ "$FAILED" = 0 ]
