# Sprint 37 Report — Production Deployment (K3s + Helm + CI/CD)

**Sprint Period:** 2026-03-24
**Status:** ✅ COMPLETE
**Asgard Version:** v0.37.0

## Objectives

Deploy ทั้ง 14+ Asgard services ขึ้น K3s cluster บน Mac Mini พร้อม CI/CD pipeline, observability stack, และ production-grade security infrastructure.

## Deliverables

| Part | Deliverables | Files | Status |
|:--|:--|:--|:--|
| A: K3s + K8s | OrbStack v2.0.5, 17 K8s manifests | `k8s/` | ✅ |
| B: Helm Charts | Umbrella chart + 11 sub-charts | `charts/asgard/` (26 files) | ✅ |
| C: CI/CD | 3 GitHub Actions workflows | `.github/workflows/` | ✅ |
| D: Observability | Prometheus+Grafana config, dashboards, alerts | `k8s/05-observability/` | ✅ |
| E: Security | TLS, Network Policies, Ingress | `k8s/04-security/` | ✅ |

## Key Decisions

1. **OrbStack over Colima** — Colima ดับเอง (macOS sleep/restart), OrbStack เสถียรกว่า + auto-start built-in
2. **Docker Compose → K8s gradual migration** — Docker Compose ยังใช้ run ได้ปกติ, K8s manifests พร้อม apply เมื่อเปิด OrbStack K8s
3. **Self-hosted GitHub Actions runner** — Deploy workflow รันบน Mac Mini เอง (GPU สำหรับ Heimdall)

## Commits

| Commit | Description |
|:--|:--|
| `c3a9792` | K8s manifests for 14+ services + OrbStack migration |
| `5502d7f` | Helm umbrella chart with 11 sub-charts |
| `978ca92` | CI/CD pipeline — 3 GitHub Actions workflows |
| `a959e7e` | Observability + Security infrastructure |

## Architecture

```
Mac Mini (Apple Silicon)
├── OrbStack (Docker + K8s runtime)
│   ├── docker-compose (current) → 16 containers running
│   └── K8s (ready to apply) → 3 namespaces, 14+ deployments
├── Heimdall (host — GPU/MLX)
├── Helm Charts → helm upgrade --install
├── GitHub Actions CI/CD
│   ├── Build & Push → ghcr.io
│   ├── Deploy → K3s
│   └── Integration Tests → Forseti
└── Observability
    ├── Prometheus → scrape /metrics
    └── Grafana → dashboards + alerts
```

## Next Steps

- Enable OrbStack K8s (GUI: Settings → Kubernetes → Enable)
- `kubectl apply -f k8s/` to migrate from Docker Compose to K8s
- Set up self-hosted GitHub Actions runner on Mac Mini
- Deploy Prometheus + Grafana (`helm install monitoring`)
