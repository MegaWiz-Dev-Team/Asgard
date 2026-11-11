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
if [ "$1" = save ]; then
    [ "${SAVE_FAILS:-0}" = 1 ] && exit 1
    echo "image $2"
fi
exit 0
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

# Image snapshots go here unless a case says otherwise, never to the real T7.
SNAP="$WORK/snap"
mkdir -p "$SNAP"

# deploy <args...> runs the script with fresh call logs; sets RC and OUT.
deploy() {
    export CALLS="$WORK/calls" APPLIED="$WORK/applied" UNDONE="$WORK/undone"
    rm -f "$CALLS" "$APPLIED" "$UNDONE"; touch "$CALLS" "$APPLIED"
    OUT=$(PATH="$WORK/bin:$PATH" DEV_DIR="$WORK/dev" DEPLOY_CHECK="$WORK/bin/gate" \
          BUILD_GUARD="$WORK/bin/build-guard" IMG_SNAPSHOT_DIR="${IMG_SNAPSHOT_DIR:-$SNAP}" \
          bash "$SCRIPT" "$@" 2>&1)
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
output_lacks() { ! grep -q -- "$1" <<< "$OUT"; }
# saved_before_apply: the first docker save comes before the first apply.
saved_before_apply() {
    local s a
    s=$(grep -nE '^docker save' "$CALLS" | head -1 | cut -d: -f1)
    a=$(grep -nE 'apply -f' "$CALLS" | head -1 | cut -d: -f1)
    [ -n "$s" ] && [ -n "$a" ] && [ "$s" -lt "$a" ]
}
# snapshot_in <dir> <regex>: a file named <regex> exists there and is a valid gzip.
snapshot_in() {
    local f
    f=$(ls "$1" 2>/dev/null | grep -E "^$2$" | head -1)
    [ -n "$f" ] && gzip -t "$1/$f"
}

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
check "api: saved the built image"                   called "^docker save $TAG_RE$"
check "api: saved it before applying it"             saved_before_apply
check "api: snapshot is a gzip named after the tag"  snapshot_in "$SNAP" "asgard-mimir-api_${MIMIR_SHA}-[0-9]{14}\.tar\.gz"

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
check "--no-build: saves nothing"                    not_called "^docker save"

deploy all --dry-run
check "--dry-run: exits 0"                           [ "$RC" = 0 ]
check "--dry-run: gates still run"                   called "^gate gate asgard-portal"
check "--dry-run: no build, apply or restart"        not_called "^docker|apply|rollout"
check "--dry-run: prints the tagged build"           grep -qE "\+ docker build .* -t $TAG_RE" <<< "$OUT"
check "--dry-run: does not claim a deploy"           output_lacks "Deploy Complete"
check "--dry-run: prints the snapshot step"          grep -qE "\+ docker save $TAG_RE \| gzip > $SNAP/" <<< "$OUT"

IMG_SNAPSHOT_DIR="$WORK/no-drive" deploy api --dry-run
check "--dry-run, no drive: still exits 0"           [ "$RC" = 0 ]
check "--dry-run, no drive: says the deploy would stop" grep -q "$WORK/no-drive not found" <<< "$OUT"

IMG_SNAPSHOT_DIR="$WORK/no-drive" deploy api
check "no drive: exits non-zero"                     [ "$RC" != 0 ]
check "no drive: stops before building"              not_called "^docker build"
check "no drive: nothing applied"                    not_called "apply"

NO_SNAPSHOT=1 IMG_SNAPSHOT_DIR="$WORK/no-drive" deploy api
check "NO_SNAPSHOT=1: deploys without a drive"       [ "$RC" = 0 ]
check "NO_SNAPSHOT=1: no docker save"                not_called "^docker save"
check "NO_SNAPSHOT=1: warns there is no copy"        grep -q "no off-node copy" <<< "$OUT"

SAVE_FAILS=1 deploy api
check "failed save: exits non-zero"                  [ "$RC" != 0 ]
check "failed save: nothing applied"                 not_called "apply"
check "failed save: no partial file left"            [ -z "$(ls "$SNAP" | grep -v '\.tar\.gz$')" ]

# Pruning: keep the newest IMG_SNAPSHOT_KEEP of the script's own files per
# image; never a file saved by hand, another image's, or one still running.
PR="$WORK/prune"; mkdir -p "$PR"
for s in 20200101000000 20200102000000 20200103000000 20200104000000; do
    echo x | gzip > "$PR/asgard-mimir-api_abc1234-$s.tar.gz"
done
echo x | gzip > "$PR/asgard-mimir-api_v1.11.0-20260930-011509.tar.gz"
echo x | gzip > "$PR/asgard-mimir-dashboard_abc1234-20200101000000.tar.gz"
kept()   { [ -e "$PR/$1.tar.gz" ]; }
pruned() { [ ! -e "$PR/$1.tar.gz" ]; }
IMG_SNAPSHOT_DIR="$PR" IMG_SNAPSHOT_KEEP=3 LIVE_IMAGE="asgard-mimir-api:abc1234-20200101000000" deploy api
check "prune: exits 0"                               [ "$RC" = 0 ]
check "prune: keeps the new snapshot"                snapshot_in "$PR" "asgard-mimir-api_${MIMIR_SHA}-[0-9]{14}\.tar\.gz"
check "prune: keeps the two newest older ones"       kept asgard-mimir-api_abc1234-20200104000000
check "prune: (second of them)"                      kept asgard-mimir-api_abc1234-20200103000000
check "prune: removes an old one nothing runs"       pruned asgard-mimir-api_abc1234-20200102000000
check "prune: keeps an old one a deployment runs"    kept asgard-mimir-api_abc1234-20200101000000
check "prune: keeps a file saved by hand"            kept asgard-mimir-api_v1.11.0-20260930-011509
check "prune: keeps another image's file"            kept asgard-mimir-dashboard_abc1234-20200101000000

echo x | gzip > "$PR/asgard-mimir-api_abc1234-20200102000000.tar.gz"
IMG_SNAPSHOT_DIR="$PR" IMG_SNAPSHOT_KEEP=1 deploy api
check "prune, running images unknown: exits 0"       [ "$RC" = 0 ]
check "prune, running images unknown: deletes nothing" kept asgard-mimir-api_abc1234-20200102000000

IMG_SNAPSHOT_KEEP=0 deploy api
check "IMG_SNAPSHOT_KEEP=0: refused"                 [ "$RC" != 0 ]
check "IMG_SNAPSHOT_KEEP=0: nothing built"           not_called "^docker build"

deploy tyr
check "tyr: exits 0"                                 [ "$RC" = 0 ]
check "tyr: deploy-check targets hermodr-wazuh"      called "^gate gate hermodr-wazuh NS=wazuh"
check "tyr: bridge applied with the built hermodr"   applied "image: asgard-hermodr:[0-9a-f]+-[0-9]{14}$"
check "tyr: hermodr image saved"                     called "^docker save asgard-hermodr:[0-9a-f]+-[0-9]{14}$"
check "tyr: wazuh manifests applied as they are"     called "apply -f $ROOT/k8s/04-security/tyr/03-wazuh-manager.yaml"

mkdir -p "$WORK/mimir-main"; git -C "$WORK/mimir-main" init -q
git -C "$WORK/mimir-main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m main
MAIN_SHA=$(git -C "$WORK/mimir-main" rev-parse --short HEAD)
MIMIR_DIR="$WORK/mimir-main" deploy api
check "MIMIR_DIR: gate checks that checkout"         called "^gate gate mimir-api NS=asgard REPO=$WORK/mimir-main "
check "MIMIR_DIR: tag comes from that checkout"      called "^docker build .* -t asgard-mimir-api:${MAIN_SHA}-[0-9]{14} "

deploy nonsense
check "unknown target: exits non-zero"               [ "$RC" != 0 ]
deploy api --bogus
check "unknown option: exits non-zero"               [ "$RC" != 0 ]

echo "$PASS passed, $FAILED failed"
[ "$FAILED" = 0 ]
