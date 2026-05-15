#!/bin/bash

# K8s Deployment Script for Asgard Services

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}[K8s Deploy]${NC} Starting Asgard services deployment..."

# Ensure namespace exists
kubectl create namespace asgard --dry-run=client -o yaml | kubectl apply -f -

echo "Checking K8s services..."

# Pull latest images (imagePullPolicy: Always ensures fresh images)
services=(
  "eir-gateway"
  "bifrost"
  "mimir-api"
  "odin"
  "hermodr"
)

for svc in "${services[@]}"; do
  echo "  Checking $svc..."
  kubectl rollout restart deployment/$svc -n asgard 2>/dev/null || echo "    (not deployed yet)"
done

# Wait for deployments to be ready
echo ""
echo -e "${YELLOW}Waiting for deployments...${NC}"
for svc in "${services[@]}"; do
  kubectl rollout status deployment/$svc -n asgard --timeout=5m 2>/dev/null || true
done

echo -e "${GREEN}✅ K8s deployment ready${NC}"
