# 🚀 Asgard Platform — Quick Start

## Deploy Everything (60 seconds)

```bash
cd /Users/mimir/Developer/Asgard
./scripts/deploy-all.sh
```

**First run:** 5-15 min (Docker builds, K8s rollouts)  
**Subsequent runs:** 2-5 min (image pull, restart)

---

## Deploy Only What You Need

### K8s Only (Bifrost, Eir, Mimir, Odin, Hermodr, etc.)
```bash
SKIP_HEIMDALL=true ./scripts/deploy-all.sh
```

### Heimdall Only (MLX Gateway + LLM Services)
```bash
SKIP_K8S=true ./scripts/deploy-all.sh
```

---

## Quick Verification

### K8s Services
```bash
kubectl get pods -n asgard -w
kubectl logs -n asgard -l app=bifrost --tail=50
```

### Heimdall Services
```bash
cd /Users/mimir/Developer/Heimdall
./scripts/manage-heimdall.sh status
```

### Test Endpoints
```bash
# Bifrost health
curl http://bifrost:8000/health

# Eir chat
curl http://eir-gateway:3000/chat.html

# Heimdall gateway
curl http://localhost:8080/health
```

---

## Common Issues

### K8s Pods Stuck in Pending
```bash
# Check resource availability
kubectl describe node

# Check pod events
kubectl describe pod <pod-name> -n asgard
```

### Image Pull Errors
```bash
# Force re-pull with latest digest
kubectl rollout restart deployment/bifrost -n asgard
```

### Heimdall Services Not Starting
```bash
# Check logs
tail -f ~/.asgard-logs/heimdall-gateway.log
tail -f ~/.asgard-logs/heimdall-mlx.log

# Restart
./scripts/manage-heimdall.sh restart
```

---

## Architecture Overview

```
OpenEMR
  ↓
Eir Gateway (3000)
  ├─→ Syn (OCR)
  ├─→ Mimir (RAG storage)
  ├─→ Bifrost (agent orchestration)
  │   └─→ Heimdall Gateway (8080)
  │       ├─→ MLX (8081)
  │       ├─→ VLM q4 (8082)
  │       └─→ VLM q8 (8083)
  └─→ OpenEMR FHIR API

Tyr (Security)
  ├─→ Wazuh (threat detection)
  └─→ Muninn (auto-response)
```

---

## Next Steps

- **Full setup:** See `DEPLOYMENT.md`
- **Troubleshooting:** See `/Users/mimir/Developer/TROUBLESHOOTING_GUIDE.md`
- **Test suite:** See `/Users/mimir/Developer/UI_TESTING_GUIDE.md`

---

**Questions?** Check DEPLOYMENT.md or run:
```bash
./scripts/deploy-all.sh --help
```
