# 🌳 Yggdrasil — Auth Platform Selection

> เปรียบเทียบ Open Source Auth Platform สำหรับใช้เป็น Yggdrasil (Centralized Auth Service) ใน Asgard

---

## เกณฑ์การเลือก

| # | เกณฑ์ | ทำไมสำคัญ |
|:--|:--|:--|
| 1 | Docker + ARM64 | ต้องรันบน Apple Silicon + DGX Spark |
| 2 | Multi-Tenancy | Mimir มี multi-tenant อยู่แล้ว |
| 3 | OIDC / OAuth2 | Standard protocol สำหรับทุก component |
| 4 | SAML / LDAP | Enterprise SSO |
| 5 | Lightweight | SME ไม่มี DevOps team ใหญ่ |
| 6 | API-First | Integrate กับ Rust + Python |
| 7 | Self-Hosted License | OSS ที่ใช้ commercial ได้ |
| 8 | UI Console | Admin จัดการ user/tenant |

---

## เปรียบเทียบ 6 ตัวเลือก

| Feature | 🏆 Zitadel | Authentik | Keycloak | Ory | Authelia | SuperTokens |
|:--|:--|:--|:--|:--|:--|:--|
| **Language** | Go | Python | Java | Go | Go | Node.js |
| **Docker ARM64** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Multi-Tenancy** | ✅ Built-in | ⚠️ Basic | ✅ Realms | ⚠️ Manual | ❌ | ⚠️ Basic |
| **OIDC/OAuth2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **SAML** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **LDAP** | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **RAM Usage** | ~200MB | ~500MB | ~1GB+ | ~100MB | ~50MB | ~200MB |
| **Admin UI** | ✅ Modern | ✅ Beautiful | ✅ Classic | ❌ API only | ❌ | ✅ Simple |
| **Audit Trail** | ✅ Event-sourced | ⚠️ Basic | ✅ | ✅ | ⚠️ | ❌ |
| **API-First** | ✅ gRPC + REST | REST | REST | ✅ REST | ❌ | REST |
| **License** | Apache 2.0 | MIT | Apache 2.0 | Apache 2.0 | Apache 2.0 | Apache 2.0 |

---

## 🏆 Decision: Zitadel

| เหตุผล | รายละเอียด |
|:--|:--|
| **Multi-Tenancy Native** | สร้างมาเพื่อ B2B SaaS → match กับ Mimir |
| **Go → เบา + เร็ว** | ~200MB RAM, startup เร็ว, binary เดียว |
| **Event-Sourced Audit** | Enterprise compliance ได้เลย |
| **gRPC + REST API** | Rust (Heimdall) เรียก gRPC, Python (Bifrost) ใช้ REST |
| **OIDC + SAML + LDAP** | ครบ enterprise protocols |
| **Apache 2.0** | ใช้ commercial ได้เลย |
| **ARM64 Native** | Docker image สำหรับ Apple Silicon มีพร้อม |

---

## 🔧 Integration Architecture

```
                    ┌──────────────────────┐
                    │  🌳 Yggdrasil        │
                    │  (Zitadel)           │
                    │                      │
                    │  • User Management   │
                    │  • Tenant/Org        │
                    │  • OIDC Provider     │
                    │  • SAML/LDAP Bridge  │
                    │  • Audit Trail       │
                    └──────────┬───────────┘
                               │ OIDC / JWT
              ┌────────────────┼────────────────┐
              │                │                │
     ┌────────▼──────┐ ┌──────▼───────┐ ┌──────▼───────┐
     │ 🛡️ Heimdall   │ │ 🧠 Mimir     │ │ ⚡ Bifrost   │
     │ validate JWT  │ │ validate JWT │ │ validate JWT │
     └───────────────┘ └──────────────┘ └──────────────┘
```

### Migration Path จาก Mimir IAM

| Step | Action | Impact |
|:--|:--|:--|
| 1 | Deploy Zitadel ใน Docker Compose | ไม่กระทบ Mimir |
| 2 | สร้าง Organizations ตาม Mimir tenants | Parallel run |
| 3 | Migrate users → Zitadel import API | Data migration |
| 4 | Heimdall → validate Zitadel JWT | แทน static API key |
| 5 | Mimir → delegate login (OIDC) | ลบ auth code |
| 6 | Bifrost → validate Zitadel JWT | เพิ่ม middleware |
| 7 | ลบ Mimir IAM code | Cleanup |

### Docker Compose

```yaml
yggdrasil:
  image: ghcr.io/zitadel/zitadel:latest
  platform: linux/arm64
  ports:
    - "8085:8080"
  environment:
    ZITADEL_DATABASE_POSTGRES_HOST: yggdrasil-db
    ZITADEL_EXTERNALDOMAIN: auth.asgard.local
  depends_on:
    - yggdrasil-db

yggdrasil-db:
  image: postgres:16-alpine
  volumes:
    - yggdrasil-data:/var/lib/postgresql/data
```

---

## 📊 Impact on Gap Mapping

| Gap เดิม | เปลี่ยนไป |
|:--|:--|
| Heimdall JWT validation | → validate Zitadel JWT |
| Mimir SSO support | → ❌ ไม่ต้องทำ — Zitadel มี |
| Mimir Audit Log | → ❌ ไม่ต้องทำ — Zitadel มี event-sourced |
| Mimir IAM code | → ลดลง — delegate ไป Zitadel |

> เลือก Zitadel → Mimir จะเบาลงมาก และ Enterprise features หลายตัวได้มาฟรี

---

*📅 Last updated: March 2026*
