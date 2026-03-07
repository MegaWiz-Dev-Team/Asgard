# 🌳 Yggdrasil — Auth Platform Selection

> Comparison of Open Source Auth Platforms for use as Yggdrasil (Centralized Auth Service) in Asgard.

---

## Selection Criteria

| # | Criterion | Why it matters |
|:--|:--|:--|
| 1 | Docker + ARM64 | Must run on Apple Silicon + DGX Spark |
| 2 | Multi-Tenancy | Mimir already has multi-tenant |
| 3 | OIDC / OAuth2 | Standard protocol for all components |
| 4 | SAML / LDAP | Enterprise SSO |
| 5 | Lightweight | SMEs don't have large DevOps teams |
| 6 | API-First | Integrate with Rust + Python |
| 7 | Self-Hosted License | OSS that allows commercial use |
| 8 | UI Console | Admin manages users/tenants |

---

## Comparison of 6 Options

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

| Reason | Details |
|:--|:--|
| **Native Multi-Tenancy** | Built for B2B SaaS → matches Mimir's architecture |
| **Go → Lightweight + Fast** | ~200MB RAM, fast startup, single binary |
| **Event-Sourced Audit** | Enterprise compliance out of the box |
| **gRPC + REST API** | Rust (Heimdall) calls gRPC, Python (Bifrost) uses REST |
| **OIDC + SAML + LDAP** | Complete enterprise protocol coverage |
| **Apache 2.0** | Compatible with commercial use |
| **ARM64 Native** | Docker image for Apple Silicon available |

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

### Migration Path from Mimir IAM

| Step | Action | Impact |
|:--|:--|:--|
| 1 | Deploy Zitadel in Docker Compose | No impact on Mimir |
| 2 | Create Organizations matching Mimir tenants | Parallel run |
| 3 | Migrate users → Zitadel import API | Data migration |
| 4 | Heimdall → validate Zitadel JWT | Replace static API key |
| 5 | Mimir → delegate login (OIDC) | Remove auth code |
| 6 | Bifrost → validate Zitadel JWT | Add middleware |
| 7 | Remove Mimir IAM code | Cleanup |

### Docker Compose

```yaml
yggdrasil:
  image: ghcr.io/zitadel/zitadel:latest
  platform: linux/arm64
  ports:
    - "8085:8080"
  environment:
    ZITADEL_DATABASE_POSTGRES_HOST: yggdrasil-db
    ZITADEL_EXTERNALDOMAIN: auth.asgardai.dev
  depends_on:
    - yggdrasil-db

yggdrasil-db:
  image: postgres:16-alpine
  volumes:
    - yggdrasil-data:/var/lib/postgresql/data
```

---

## 📊 Impact on Gap Mapping

| Original Gap | Changes to |
|:--|:--|
| Heimdall JWT validation | → Validate Zitadel JWT |
| Mimir SSO support | → ❌ Not needed — Zitadel provides it |
| Mimir Audit Log | → ❌ Not needed — Zitadel has event-sourced audit |
| Mimir IAM code | → Reduced — delegated to Zitadel |

> Choosing Zitadel → Mimir becomes significantly lighter, and many Enterprise features come for free.

---

*📅 Last updated: March 2026*
