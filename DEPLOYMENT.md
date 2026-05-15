# 📖 Asgard Platform — Complete Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)
7. [Scaling](#scaling)
8. [Updates](#updates)

---

## Overview

Asgard is an open medical platform with 20+ microservices:

### K8s Services (15+)
- **Core:** Bifrost, Eir, Mimir, Odin, Hermodr
- **Indexing:** Qdrant, Neo4j
- **Data:** MariaDB, PostgreSQL
- **Infra:** Tyr (SIEM), Forseti (testing), Vault

### Heimdall Services (5, native)
- MLX gateway (port 8080)
- LLM models q4 & q8 (ports 8082-8083)
- Log shipper → Tyr

---

## Prerequisites

### System Requirements
- **OS:** macOS (OrbStack) or Linux
- **RAM:** 32GB+ (16GB minimum for Heimdall + K8s)
- **Disk:** 500GB+ SSD
- **CPU:** 8+ cores

### Software
- **Docker:** 20.10+
- **Kubernetes:** OrbStack K8s or local K3s
- **kubectl:** 1.24+
- **Rust:** 1.75+ (for local builds)
- **Python:** 3.10+ (Heimdall)

### Authentication
- **GitHub:** PAT token for GHCR (ghcr.io)
- **Docker:** Credentials in ~/.docker/config.json

### Environment

```bash
export GHCR_USERNAME=your-github-username
export GHCR_TOKEN=ghp_xxxxxxxxxxxx  # GitHub PAT

# K8s context (OrbStack)
kubectl config use-context orbstack
```

---

## Installation

### 1. Clone Repositories

```bash
cd /Users/mimir/Developer

# Core repositories (should already exist)
ls -d Bifrost Eir Mimir Heimdall Hermodr Odin

# Create Asgard meta-directory (if needed)
mkdir -p Asgard/scripts
```

### 2. Run Master Deploy Script

```bash
cd Asgard

# Full deployment (K8s + Heimdall)
./scripts/deploy-all.sh

# Or choose what to deploy
SKIP_HEIMDALL=true ./scripts/deploy-all.sh  # K8s only
SKIP_K8S=true ./scripts/deploy-all.sh       # Heimdall only
```

### 3. Verify Deployment

```bash
# Check K8s pods
kubectl get pods -n asgard -w

# Check Heimdall services
cd Heimdall
./scripts/manage-heimdall.sh status
```

---

## Configuration

### K8s Service Configuration

Each service has K8s manifests in `k8s/` directory:

```yaml
# Environment variables
env:
- name: SYN_URL
  value: http://syn-api.asgard.svc:8080
- name: MIMIR_URL
  value: http://mimir-api.asgard.svc:3100
- name: BIFROST_URL
  value: http://bifrost:8000

# Resource limits
resources:
  limits:
    memory: "4Gi"
    cpu: "2"
  requests:
    memory: "2Gi"
    cpu: "1"

# Image pull policy (always pull latest)
imagePullPolicy: Always
```

### Heimdall Configuration

Configure MLX models and resources:

```bash
# Edit Heimdall config
cd Heimdall
nano ~/.asgard/config.yaml

# Key settings:
# - model_name: Specify which LLM to run
# - quant: q4 (4-bit) or q8 (8-bit)
# - max_tokens: Response length limit
# - temperature: 0.7 (default)
```

### Environment Variables

Create `.env` in each service directory:

```bash
# Eir Gateway
export SYN_URL=http://syn-api.asgard.svc:8080
export MIMIR_URL=http://mimir-api.asgard.svc:3100
export BIFROST_URL=http://bifrost:8000

# Bifrost
export MIMIR_URL=http://mimir-api.asgard.svc:3100
export DB_URL=mysql://mimir:password@mariadb:3306/mimir

# Heimdall
export MODEL_PATH=/models
export CACHE_DIR=/tmp/mlx-cache
export LOG_LEVEL=INFO
```

---

## Verification

### Health Checks

```bash
#!/bin/bash
# Save as: asgard-health-check.sh

echo "🏥 Asgard Health Check"
echo ""

# K8s services
echo "K8s Services:"
kubectl get deployment -n asgard --no-headers | awk '{print $1, $2}'

# Endpoints
echo ""
echo "Endpoints:"
curl -s http://bifrost:8000/health | jq '.status' && echo "✅ Bifrost"
curl -s http://eir-gateway:3000/chat.html | grep -q "Eir" && echo "✅ Eir"
curl -s http://mimir-api:3100/health | jq '.status' && echo "✅ Mimir"
curl -s http://localhost:8080/health | jq '.status' && echo "✅ Heimdall"

# Database connectivity
echo ""
echo "Databases:"
kubectl exec -n asgard deployment/mimir-api -- \
  curl http://mariadb:3306 && echo "✅ MariaDB" || echo "❌ MariaDB"
```

### Test Workflows

```bash
# Test document upload (Eir integration)
cd /Users/mimir/Developer
npm install
./run-ui-tests.sh --headed

# Test Bifrost agent
./test_bifrost_agent_integration.sh

# Test end-to-end
./integration_test_e2e.sh
```

---

## Troubleshooting

### Common Issues

#### 1. K8s Pod CrashLoopBackOff

**Symptoms:**
```
mimir-api-xxxx   0/1     CrashLoopBackOff
```

**Solution:**
```bash
# Check logs
kubectl logs -n asgard deployment/mimir-api --tail=50

# Common causes:
# - Database migration error → Reset DB
# - Missing environment variable → Check ConfigMap
# - Port already in use → Change port in deployment

# Rollback to previous version
kubectl rollout undo deployment/mimir-api -n asgard
```

#### 2. ImagePullBackOff

**Symptoms:**
```
ImagePullBackOff (image not found in registry)
```

**Solution:**
```bash
# Verify image exists in GHCR
gh api repos/MegaWiz-Dev-Team/Bifrost/packages?package_type=container

# Force rebuild and push
cd Bifrost
git push origin main  # Triggers GitHub Actions build

# Or manually build locally
docker build -t ghcr.io/megawiz-dev-team/bifrost:latest .
docker push ghcr.io/megawiz-dev-team/bifrost:latest
kubectl rollout restart deployment/bifrost -n asgard
```

#### 3. Heimdall MLX Model Fails to Load

**Symptoms:**
```
Error: Model not found or corrupted
```

**Solution:**
```bash
# Check available models
ls -la ~/.cache/huggingface/hub/

# Clear cache and re-download
rm -rf ~/.cache/huggingface/hub/
cd Heimdall
./scripts/manage-heimdall.sh restart

# Check model compatibility
python3 -c "from mlx_lm import load; load('Qwen2.5-7B-Instruct')"
```

#### 4. Port Already in Use

**Solution:**
```bash
# Find process using port
lsof -i :8080  # For Heimdall gateway
lsof -i :8000  # For Bifrost

# Kill the process
kill -9 <PID>

# Or change port in manifest
kubectl edit deployment bifrost -n asgard
```

---

## Scaling

### Horizontal Scaling (K8s)

```bash
# Scale deployment to 3 replicas
kubectl scale deployment/bifrost -n asgard --replicas=3

# Check replicas
kubectl get deployment bifrost -n asgard

# Auto-scale based on CPU
kubectl autoscale deployment bifrost \
  --min=2 --max=5 --cpu-percent=80 -n asgard
```

### Vertical Scaling (Resources)

```bash
# Edit deployment resource limits
kubectl edit deployment bifrost -n asgard

# Change:
resources:
  limits:
    memory: "8Gi"     # Increase from 4Gi
    cpu: "4"          # Increase from 2
```

### Database Scaling

```bash
# MariaDB replication
kubectl exec -n asgard-infra deployment/mariadb -- \
  mysql -u root -p$MARIADB_ROOT_PASSWORD \
  -e "SHOW MASTER STATUS;"

# Enable read replicas in connection string
MIMIR_DB_URL="mysql+replica://user:pass@primary:3306,replica:3306/mimir"
```

---

## Updates

### Rolling Updates (Zero Downtime)

```bash
# Trigger rebuild on GitHub
git push origin main  # Automatically rebuilds and pushes to GHCR

# K8s will gradually roll out new pods
kubectl rollout status deployment/bifrost -n asgard

# Monitor during rollout
watch kubectl get pods -n asgard
```

### Canary Deployment

```bash
# Deploy to 10% of traffic first
kubectl set image deployment/bifrost \
  bifrost=ghcr.io/megawiz-dev-team/bifrost:v1.2 \
  --record -n asgard

# Monitor metrics
kubectl top pod -n asgard
kubectl logs -n asgard -l app=bifrost -f

# If successful, roll out to 100%
kubectl rollout resume deployment/bifrost -n asgard

# If issues, rollback
kubectl rollout undo deployment/bifrost -n asgard
```

### Version Management

```bash
# Tag specific versions
git tag v1.0.0 -m "Asgard Platform v1.0.0"
git push origin v1.0.0

# Deploy specific version
IMAGE_TAG="v1.0.0" ./scripts/deploy-all.sh
```

---

## Monitoring & Logging

### Prometheus Metrics

```bash
# Port-forward Prometheus
kubectl port-forward -n asgard svc/prometheus 9090:9090

# Access at http://localhost:9090
# Query examples:
# - rate(http_requests_total[5m])
# - container_memory_usage_bytes{pod_name=~"bifrost.*"}
```

### Logs

```bash
# Stream logs from all services
kubectl logs -n asgard -l app=bifrost -f

# Get logs from specific pod
kubectl logs -n asgard mimir-api-xxxx --tail=100

# Export logs for analysis
kubectl logs -n asgard -l app=bifrost --timestamps=true > bifrost-logs.txt
```

### Tyr SIEM (Threat Detection)

```bash
# Access Wazuh dashboard
curl https://localhost:5601

# Check Tyr alerts
kubectl logs -n asgard deployment/tyr --tail=50

# View security events
kubectl exec -n asgard deployment/wazuh -- \
  tail -f /var/ossec/logs/alerts/alerts.log
```

---

## Support & Resources

- **Documentation:** `QUICK_START.md`, `IMPLEMENTATION_SUMMARY.md`
- **Troubleshooting:** `/Users/mimir/Developer/TROUBLESHOOTING_GUIDE.md`
- **Testing:** `/Users/mimir/Developer/UI_TESTING_GUIDE.md`
- **Architecture:** See individual service READMEs

---

**Last Updated:** 2026-05-14  
**Version:** 1.0
