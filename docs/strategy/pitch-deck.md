# 🏰 Asgard — Pitch Deck (3-5 นาที)

> Self-Hosted AI Platform for Enterprise
> Updated: 2026-04-28

---

## Slide 1 — Title

**🏰 Asgard**
*Self-Hosted AI Platform for Enterprise*

- Zero cloud dependency
- Built on Apple Silicon & NVIDIA
- Open-core (AGPL-3.0 Community + Enterprise)

---

## Slide 2 — Problem

องค์กรในอุตสาหกรรม regulated (สุขภาพ, ประกัน, กฎหมาย, การเงิน, พลังงาน) เผชิญปัญหาเดียวกัน:

| Pain Point | ผลกระทบ |
|:--|:--|
| **Data Sovereignty** | ข้อมูลผู้ป่วย/ลูกค้าถูกส่งออก cloud |
| **Vendor Lock-in** | ขึ้นกับ OpenAI/Azure API โดยตรง |
| **Cost at Scale** | $0.01/token × volume = บิลสูงมาก |
| **PDPA/HIPAA Compliance** | ต้อง build from scratch หรือรับความเสี่ยง |
| **Integration Complexity** | ต้องต่อ 5-10 tools เข้าหากันเอง |

---

## Slide 3 — Solution

> **Asgard = Complete AI Stack ที่ run บน hardware ขององค์กรเอง**

```
LLM Gateway → RAG Pipeline → Agent Runtime → Computer Use → SIEM/Compliance
```

- **ไม่ต้องส่งข้อมูลออกไปไหนเลย** — 100% on-premise
- **OpenAI-compatible API** — ไม่ต้อง rewrite code เดิม
- **Modular** — เลือกใช้เฉพาะส่วนที่ต้องการ

---

## Slide 4 — Architecture

**3 Layer:**

| Layer | Components |
|:--|:--|
| **Interface** | Mimir Dashboard · Eir Chat UI · Asgard Portal |
| **Intelligence** | Bifrost (ReAct Agent) · Mimir (RAG + GraphRAG) · Fenrir (Computer Use) |
| **Infrastructure** | Heimdall (LLM Gateway) · Yggdrasil (Auth/SSO) · Týr (SIEM) · Fáfnir (Vault) |

**Protocols:** MCP (tool calls) + A2A (agent-to-agent task delegation)

**LLM Backends:** MLX (Apple Silicon) · vLLM (NVIDIA) — local inference เท่านั้น

---

## Slide 5 — Live Platform

> Sprint 38 delivered · v1.2-alpha · 2026-04-22

| Metric | Value |
|:--|:--|
| Pods running | **41 pods**, 0 failures |
| Microservices | **14 services** (ทุกตัวเขียนด้วย Rust) |
| Automated tests | **530+** ผ่านทั้งหมด |
| Default LLM | Qwen3.5-9B MLX 4-bit (run local) |
| Hardware | Mac Mini M4 Pro 64GB, 273 GB/s |
| Deployment | OrbStack K8s + Helm umbrella chart |

---

## Slide 6 — Key Differentiators vs Competitors

| Feature | **Asgard** | Dify | Open WebUI | AnythingLLM | OpenClaw |
|:--|:--|:--|:--|:--|:--|
| LLM Gateway (local) | ✅ Heimdall | ❌ | ❌ | ❌ | ❌ |
| Native Local Inference | ✅ MLX + vLLM | ❌ Cloud API | ⚠️ Ollama | ⚠️ Ollama | ⚠️ Ollama |
| RAG Pipeline | ✅ Mimir | ✅ | ⚠️ Basic | ✅ | ❌ |
| Agent Runtime | ✅ Bifrost | ✅ | ❌ | ❌ | ✅ (autonomous) |
| Computer Use | ✅ Fenrir (sandboxed) | ❌ | ❌ | ❌ | ✅ (unsafe) |
| Multi-Tenant | ✅ | ✅ | ⚠️ | ❌ | ❌ |
| SSO / SAML | ✅ Zitadel | ✅ | ⚠️ | ❌ | ❌ |
| SIEM / Audit Trail | ✅ Týr (Wazuh) | ❌ | ❌ | ❌ | ❌ |
| Enterprise Security | ✅ | ⚠️ | ⚠️ | ❌ | ❌ CVE-2026-25253 |
| Apple Silicon native | ✅ | ❌ | ⚠️ | ⚠️ | ⚠️ |
| NVIDIA GPU (vLLM) | ✅ | ❌ | ⚠️ | ⚠️ | ❌ |
| License | AGPL-3.0 | Apache 2.0 | MIT | MIT | MIT |

> **Position:** Asgard คือ **เดียวเท่านั้น** ที่รวม Gateway + RAG + Agent + Computer Use + SIEM ในที่เดียว พร้อม enterprise security ครบ
>
> OpenClaw — 347K GitHub stars แต่มี RCE CVE และ 42,900 exposed instances; ไม่เหมาะกับ regulated workloads

---

## Slide 7 — Target Market

### TAM → SAM → SOM

| Level | Market | Size (2026) |
|:--|:--|:--|
| **TAM** | Global AI Platform Market | $28B |
| **SAM** | Self-hosted AI — regulated industries | $4.2B |
| **SOM** | Thailand + SEA (healthcare, insurance, finance) | $42M |

### Segments (Priority × Purchasing Power)

| Tier | Segment | Annual WTP | Why Asgard |
|:--|:--|:--|:--|
| 1 | 🏥 Healthcare | $24K–60K | PDPA, FHIR R4 built-in |
| 1 | 🏦 Financial Services | $60K+ | Compliance, audit trail |
| 1 | ⚖️ Legal Firms | $24K–60K | Document confidentiality + RAG |
| 1 | 🎮 Game Studios SEA | $6K–24K | NPC AI, IP protection |
| 2 | 🛡️ Insurance | $120K–600K | Claims automation, OIC compliance |
| 2 | 📡 Telco | $600K–2.4M | Data residency, local LLM cost reduction |
| 2 | ⚡ Energy/Utilities | $600K–2.4M | Air-gapped ops, กกพ./EGAT compliance |
| 2 | 🏗️ Large Conglomerates | $240K–1.2M | Multi-BU multi-tenant, contract agents |
| 2 | 📊 Consulting / Big 4 | $60K–240K | Client data isolation, research agents |
| 3 | 🏭 Manufacturing | $60K–240K | Air-gapped, ISO 55001 |
| 3 | 🏛️ Government | $120K–600K | Sovereignty mandate |
| 3 | 🎓 University | $12K–60K | Multi-tenant, research RAG |

---

## Slide 8 — Business Model

**Open-core:**
- **Community** — AGPL-3.0 (ฟรี, self-host)
- **Enterprise** — Commercial License เริ่มต้น **$5,000/year/instance**

**Pricing Tiers:**

| Tier | Annual Price | Target |
|:--|:--|:--|
| Community | Free (AGPL-3.0) | Developers, startups |
| Starter Enterprise | $5,000/yr | Small teams (10-20 users) |
| Professional Enterprise | $20,000/yr | Mid-size orgs (20-50 users) |
| Custom Enterprise | $50K–200K/yr | Large enterprises |

**Hardware Bundles (pre-configured + Asgard):**

| Bundle | Hardware | Price | Users |
|:--|:--|:--|:--|
| Mini | Mac Mini M4 16GB | $2,500 | 1-5 |
| Pro | Mac Mini M4 Pro 64GB | $3,800 | 20-50 |
| Studio | Mac Studio M4 Ultra | $9,500 | 50-200 |
| GPU | NVIDIA DGX Spark | $6–15K | 50-200+ |

---

## Slide 9 — Roadmap 2026

| Phase | Timeline | Milestone |
|:--|:--|:--|
| **Shield Wall** | Q2 2026 (ปัจจุบัน) | ✅ K8s prod, ✅ ISO 27001 log pipeline, 🚧 AI Guardrails (Thai PII filter, kill switch) |
| **Developer Preview** | Q3 2026 | Visual Workflow Builder, GitHub public launch |
| **Community Launch** | Q4 2026 | v1.0, Product Hunt / HackerNews |
| **Enterprise Pilot** | Q1 2027 | 3-5 paying design partners |
| **Enterprise GA** | Q3 2027 | Sales team, channel partners, $100K ARR |

---

## Slide 10 — Ask

**สถานะปัจจุบัน:**
- Platform production-ready บน Mac Mini M4 Pro 64GB
- Bootstrapped — ยังไม่ได้รับ external funding
- 530+ tests · 14 microservices · v1.2-alpha running

**กำลังมองหา:**
- **3-5 Design Partners** สำหรับ pilot (โรงพยาบาล / ประกัน / FinTech / Telco)
- **$500K Seed Round** สำหรับ Year 2 expansion

**Contact:** paripol@megawiz.co · [MegaWiz Dev Team](https://github.com/MegaWiz-Dev-Team)

---

*📅 Updated: 2026-04-28 · See also: [competitor-analysis.md](competitor-analysis.md) · [business-plan.md](../business/business-plan.md)*
