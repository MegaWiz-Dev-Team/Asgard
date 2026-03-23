# Asgard Ecosystem: Multi-Agent Evolution (Sprint 35-37)

> ขยายจาก Master Sprint Plan S31-S34 — ผลจากการ research [alibaba/hiclaw](https://github.com/alibaba/hiclaw) + [bytedance/deer-flow](https://github.com/bytedance/deer-flow)

---

### 🛡️ Global Rules (กฎเหล็กประจำทุก Sprint)
- **[Action - TDD]:** ทำ TDD 100% (เขียน Test ให้ Fail ก่อนเขียนโค้ดเสมอ)
- **[Action - Testing Workflow]:** รัน Unit/E2E Test + push ผลเข้า Forseti ทุกครั้งที่ปิด Sprint
- **[Action - Security Review]:** ส่งโค้ดสแกน Huginn (Semgrep/Trivy) ก่อนปิด Sprint
- **[Action - Release & ISO Closing]:** อัปเดต ISO 29110 docs + Tag Release Version

---

### 🧠 Sprint 35: Agent Intelligence Foundation ✅ COMPLETE
เป้าหมาย: เพิ่ม "ความจำ" และ "ทักษะ" ให้ Asgard agents — เปลี่ยนจาก stateless MCP tools เป็น intelligent agents

> **Completed:** 2026-03-23 | **Bifrost:** `v0.10.0` | **Asgard:** `v0.35.0` | **Tests:** 47 pass | **Semgrep:** Clean

- **[Skills System — ต้นแบบ: DeerFlow] ✅**
  - ✅ สร้าง `Asgard/skills/{public,custom}/` directory structure
  - ✅ กำหนด `SKILL.md` format (YAML frontmatter + markdown) — compatible กับ DeerFlow ecosystem
  - ✅ เขียน built-in skills: medical-research, patient-summary, iso-doc-generator, security-audit, deployment
  - ✅ สร้าง Bifrost `skills/` module — models.py (parser), loader.py (scan, progressive loading)
  - ✅ Integrate skills เข้า agent executor system prompt (`<skills>` block injection)

- **[Long-Term Agent Memory — ต้นแบบ: DeerFlow] ✅**
  - ✅ สร้าง Bifrost `memory/` module: schema.py, store.py, updater.py
  - ✅ Memory schema: 4 categories (fact, context, medical, preference)
  - ✅ **Multi-tenant isolation**: memory per `tenant_id` + dedup index
  - ✅ Memory injection: top 15 facts → `<memory>` block ใน system prompt
  - ✅ LLM-based extraction: conversations → JSON facts → dedup → SQLite

- **[Context Engineering — ต้นแบบ: DeerFlow] ✅**
  - ✅ สร้าง Bifrost `context/` module: summarizer.py, middleware.py
  - ✅ Configurable triggers: max_messages=20, max_tokens=6000
  - ✅ เก็บ recent messages verbatim, สรุป older messages via LLM

- **[Shared Storage Service] — ⏳ Deferred to Sprint 36**
  - ย้าย **RustFS** จาก `Mimir/docker-compose.yml` → `Asgard/docker-compose.yml` เป็น shared service
  - Bucket structure: `tasks/`, `skills/`, `memory/`, `artifacts/`, `knowledge/`
  - สร้าง Bifrost `storage.py` — S3-compatible client wrapper (ใช้ endpoint เดียวกับ Mimir)
  - กำหนด Task Spec Format (HiClaw pattern): `meta.json` + `spec.md` + `progress/` + `result.md`

---

### ⚔️ Sprint 36: Multi-Agent Orchestration (Odin)
เป้าหมาย: สร้าง "Odin" Agent Coordinator ที่ spawn sub-agents, delegate tasks, synthesize results

- **[Odin Agent Coordinator — ต้นแบบ: DeerFlow Lead Agent + HiClaw Manager]**
  - สร้าง Bifrost `agents/odin/` module: coordinator, planner, registry, executor
  - Task decomposition: Odin วิเคราะห์ request → แตก sub-tasks → spawn sub-agents
  - Sub-agent execution: max 3 concurrent, 15-min timeout, structured result reporting
  - Sub-agent types: general-purpose, researcher, coder, medical, devops
  - Integrate memory + skills + context engineering จาก Sprint 35

- **[Per-Agent Credential Isolation — ต้นแบบ: HiClaw]**
  - เพิ่ม consumer token endpoint ใน Yggdrasil: `POST /api/v1/agents/token`
  - Scoped tokens per sub-agent: `agent_id`, `tenant_id`, `allowed_tools[]`, `ttl`
  - Sub-agents ไม่เห็น credentials จริง — ผ่าน Yggdrasil proxy เท่านั้น

- **[IM Channel Integration — ต้นแบบ: DeerFlow]**
  - เพิ่ม channel modules ใน Ratatoskr: Telegram (long-polling), Slack (Socket Mode), LINE
  - Message bus: async pub/sub + channel:chat → thread mapping
  - Commands: `/new`, `/status`, `/models`, `/health`, `/help`

- **[Sandbox Execution — ต้นแบบ: DeerFlow]**
  - เพิ่ม sandbox mode ใน Fenrir: Docker container per-task
  - Virtual filesystem: `/mnt/user-data/{workspace,uploads,outputs}`
  - MCP tools: `execute_sandbox_command`, `read_sandbox_file`, `write_sandbox_file`

---

### 🚀 Sprint 37: Production Deployment (K3s + Helm + CI/CD)
เป้าหมาย: Deploy ทั้ง 14+ services ขึ้น K3s cluster พร้อม CI/CD pipeline และ observability stack

- **[K3s Cluster Setup]**
  - ติดตั้ง K3s บน Mac Mini (single-node) พร้อม Traefik Ingress
  - สร้าง `Asgard/k8s/` directory structure: namespaces, deployments, services, configmaps, secrets
  - Migrate docker-compose services → K8s Deployment + Service manifests ทั้ง 14 services

- **[Helm Charts]**
  - สร้าง `Asgard/charts/asgard/` umbrella Helm chart
  - Sub-charts per service: mimir, bifrost, heimdall, eir, fenrir, ratatoskr, huginn, muninn, mjolnir, forseti, odin, vardr, yggdrasil, hermodr
  - `values-dev.yaml` vs `values-prod.yaml` สำหรับแยก environment

- **[CI/CD Pipeline — GitHub Actions]**
  - `.github/workflows/build-and-push.yml` — build Docker images → push to `ghcr.io`
  - `.github/workflows/deploy.yml` — auto-deploy to K3s on merge to main
  - `.github/workflows/integration-test.yml` — run E2E tests post-deploy
  - Implement **GitOps**: ArgoCD หรือ Flux สำหรับ declarative deployment

- **[Observability Stack]**
  - Deploy **Prometheus + Grafana** บน K3s (kube-prometheus-stack Helm chart)
  - Grafana dashboards: Heimdall GPU metrics, Mimir RAG latency, Bifrost agent throughput
  - Alerting rules: service down, high error rate, GPU memory > 90%

- **[Security & Networking]**
  - cert-manager + Let's Encrypt สำหรับ TLS certificates
  - Network Policies: isolate namespaces, restrict inter-service communication
  - Secrets management: `.env` → K8s Secrets (sealed-secrets หรือ external-secrets)
