#!/bin/bash
# 🏰 Asgard — Health Check (K8s-aware)
#
# Services run as OrbStack Kubernetes pods (ns `asgard` + `asgard-infra`), NOT as
# host-localhost processes or docker-compose containers. The previous version of this
# script probed http://localhost:<port> and `docker inspect asgard_mariadb`, which no
# longer match reality (NodePorts aren't bound to host localhost under OrbStack, and the
# compose containers are gone) — so it reported ~11/12 "down" while the cluster was green.
#
# Authoritative signals used here:
#   • node Ready
#   • pod readiness  (most core deploys have httpGet readiness probes → Ready == /health responds)
#   • deployment available == desired  (replicas=0 is treated as intentionally-off, not a failure)
# Plus the genuinely host-native pieces: Heimdall LLM gateway (:8080) and the Cloudflare tunnel.
#
# Usage: scripts/health.sh            # ns defaults to "asgard"
set -uo pipefail

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
PASS=0; FAIL=0; WARN=0
ok()   { echo -e "  ${G}✅ $1${N}"; PASS=$((PASS+1)); }
bad()  { echo -e "  ${R}❌ $1${N}"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${Y}⚠️  $1${N}"; WARN=$((WARN+1)); }
# ready "<name>" "<got/desired>"  → ok if got==desired and desired>0
ready(){ echo "$2" | awk -F/ '{exit !($1==$2 && $2+0>0)}' && ok "$1 ($2)" || bad "$1 ($2)"; }

NS="${1:-asgard}"

echo ""
echo "🏰 Asgard Health Check  ($(date '+%F %T'))"
echo "═══════════════════════════════════════════"

# 1) Cluster / node
echo ""; echo "🧱 Cluster:"
if ! kubectl get nodes >/dev/null 2>&1; then
  bad "kubectl unreachable — is OrbStack running? (orb status)"; echo ""; exit 1
fi
notready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"{print $1}')
[ -z "$notready" ] && ok "node(s) Ready" || bad "node(s) NotReady: $notready"

# 2) Pod readiness (asgard + asgard-infra)
echo ""; echo "📦 Pods (readiness):"
for ns in asgard asgard-infra; do
  # single-namespace `get pods` columns: NAME READY STATUS RESTARTS AGE → STATUS is $3
  nr=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '
    $3=="Running"{split($2,a,"/"); if(a[1]!=a[2]) print $1}
    $3!="Running" && $3!="Completed" && $3!="Succeeded"{print $1"("$3")"}')
  running=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '$3=="Running"' | wc -l | tr -d ' ')
  if [ -z "$nr" ]; then ok "$ns — all $running running pods ready"
  else bad "$ns — not ready: $(echo "$nr" | tr '\n' ' ')"; fi
done

# 3) Deployments: available == desired (replicas=0 == intentionally off)
echo ""; echo "🚀 Deployments (available == desired):"
issues=$(kubectl get deploy -n "$NS" --no-headers 2>/dev/null | awk '{split($2,a,"/"); if(a[2]+0>0 && a[1]!=a[2]) print $1" ("$2")"}')
if [ -z "$issues" ]; then ok "all scaled deployments fully available"
else echo "$issues" | while read -r l; do echo -e "  ${R}❌ $l${N}"; done; FAIL=$((FAIL+1)); fi
off=$(kubectl get deploy -n "$NS" --no-headers 2>/dev/null | awk '$2=="0/0"{print $1}' | tr '\n' ' ')
[ -n "$off" ] && echo -e "  ${B}ℹ️  scaled to 0 (intentional/off):${N} $off"

# 4) Core services — readiness-probe backed (Ready => probe passing => service responds)
echo ""; echo "🩺 Core services:"
for d in yggdrasil mimir-api bifrost eir eir-gateway embla askr underwriter iris vor odin muninn huginn; do
  st=$(kubectl get deploy -n "$NS" "$d" --no-headers 2>/dev/null | awk '{print $2}')
  [ -z "$st" ] && { warn "$d — not found"; continue; }
  ready "$d" "$st"
done

# 5) Data plane
echo ""; echo "💾 Data plane:"
for d in mariadb postgres qdrant redis; do
  st=$(kubectl get deploy -n "$NS" "$d" --no-headers 2>/dev/null | awk '{print $2}')
  [ -n "$st" ] && ready "$d" "$st"
done
for d in mariadb postgres qdrant neo4j minio; do
  st=$(kubectl get deploy -n asgard-infra "$d" --no-headers 2>/dev/null | awk '{print $2}')
  [ -n "$st" ] && ready "infra/$d" "$st"
done
vault=$(kubectl get statefulset -n "$NS" fafnir-vault --no-headers 2>/dev/null | awk '{print $2}')
[ -n "$vault" ] && ready "fafnir-vault" "$vault"

# 6) Host-native: Heimdall LLM gateway + Cloudflare tunnel
echo ""; echo "🖥️  Host-native:"
if curl -sf --max-time 4 http://localhost:8080/health >/dev/null 2>&1; then ok "Heimdall LLM gateway (:8080)"; else bad "Heimdall LLM gateway (:8080)"; fi
if pgrep -f "cloudflared tunnel run" >/dev/null 2>&1; then ok "Cloudflare tunnel (cloudflared running)"; else warn "Cloudflare tunnel not running"; fi

# 7) Backups — most recent backup job should be Completed
echo ""; echo "💽 Backups:"
lastbk=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '/backup/ && /Completed/{print $1}' | tail -1)
[ -n "$lastbk" ] && ok "last backup job Completed ($lastbk)" || warn "no recent Completed backup job found"

# Summary
echo ""
echo "═══════════════════════════════════════════"
echo -e "Results: ${G}$PASS ok${N} · ${Y}$WARN warn${N} · ${R}$FAIL fail${N}"
[ "$FAIL" -eq 0 ] && echo -e "${G}🏰 Asgard healthy${N}" || echo -e "${R}⚠️  attention needed — see ❌ above${N}"
echo ""
[ "$FAIL" -eq 0 ]
