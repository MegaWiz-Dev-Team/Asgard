#!/usr/bin/env bash
#
# asgard-build-guard — refuse heavy local docker builds while the host/cluster is
# in no shape for them. Two incidents trace back to building at the wrong time:
#   INC-2026-06-12: an 18GB build cache filled the node disk → DiskPressure →
#                   cluster-wide eviction.
#   INC-2026-06-15: builds during an already-flapping runtime helped tip it into
#                   a full containerd wedge.
#
# Use as a gate before a build:
#   asgard-build-guard.sh && GH_TOKEN=$(gh auth token) DOCKER_BUILDKIT=1 docker build ...
# Emergency override:  FORCE=1 asgard-build-guard.sh
#
# Exit 0 = safe to build, non-zero = blocked (reason on stderr).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFLIGHT="${PREFLIGHT:-$HERE/asgard-preflight.sh}"
MIN_FREE_GB="${MIN_FREE_GB:-15}"

if [[ "${FORCE:-0}" == "1" ]]; then
  echo "[build-guard] FORCE=1 — skipping checks" >&2
  exit 0
fi

# 1. Disk headroom on / (build cache + image layers land here).
AVAIL_GB=$(df -g / 2>/dev/null | awk 'NR==2{print $4}')
if [[ -n "${AVAIL_GB:-}" && "$AVAIL_GB" -lt "$MIN_FREE_GB" ]]; then
  echo "[build-guard] BLOCK: only ${AVAIL_GB}GB free on / (need >=${MIN_FREE_GB}GB)." >&2
  echo "             reclaim:  docker builder prune -f   (NOT image prune)" >&2
  exit 1
fi

# 2. Cluster health — don't add load to a degraded runtime.
if [[ -x "$PREFLIGHT" ]]; then
  "$PREFLIGHT" --json >/tmp/.build-guard-preflight.json 2>/dev/null || true
  CODE=$(python3 -c 'import json;print(json.load(open("/tmp/.build-guard-preflight.json")).get("code",0))' 2>/dev/null || echo 0)
  if [[ "${CODE:-0}" -ge 2 ]]; then
    echo "[build-guard] BLOCK: cluster is FAIL — a heavy build now risks tipping it." >&2
    python3 -c 'import json;d=json.load(open("/tmp/.build-guard-preflight.json"));[print("             •",f) for f in d.get("fail",[])[:6]]' 2>/dev/null || true
    echo "             override with FORCE=1 if you must build anyway." >&2
    exit 1
  fi
fi

echo "[build-guard] OK — ${AVAIL_GB:-?}GB free, cluster code=${CODE:-0}. Safe to build."
exit 0
