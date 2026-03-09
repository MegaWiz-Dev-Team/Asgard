# 🏰 Asgard AI Platform — Commercial Licensing

## Open Source License

The Asgard AI Platform is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

This means you can freely:
- ✅ Use Asgard for any purpose (internal, personal, educational)
- ✅ Modify the source code
- ✅ Distribute copies
- ✅ Self-host for your organization

**Conditions:**
- You must make your modifications available under AGPL-3.0 if you distribute modified versions or provide them as a network service.
- You must include the original copyright notice and license.

> The full license text is available in the [LICENSE](LICENSE) file in each repository.

---

## Enterprise License

For organizations that need additional features, support, or licensing flexibility beyond what AGPL-3.0 offers, we provide a **Commercial Enterprise License**.

### Who Needs a Commercial License?

| Scenario | AGPL-3.0 (Free) | Enterprise License |
|:--|:--|:--|
| Self-hosted internal use | ✅ | ✅ |
| Modify source code (keep modifications open) | ✅ | ✅ |
| Modify source code (keep modifications private) | ❌ | ✅ |
| Offer as a managed/hosted service to third parties | ❌ | ✅ |
| Embed in proprietary product | ❌ | ✅ |
| OEM / White-label distribution | ❌ | ✅ |

### Enterprise Features

The Enterprise Edition includes all Community features plus:

| Feature | Description |
|:--|:--|
| 🔐 **SSO Integration** | SAML, OIDC, LDAP via Zitadel |
| 👥 **Advanced RBAC** | Organization → Team → Project hierarchy |
| 📊 **Usage Analytics** | Cost tracking, usage reporting, billing dashboard |
| 📋 **Audit Logging** | Full event trail for compliance (SOC 2, HIPAA) |
| 🔄 **HA Clustering** | Multi-node high availability deployment |
| 🏷️ **White-Label** | Custom branding for your organization |
| 🤖 **Advanced Agents** | Multi-agent collaboration, advanced orchestration |
| 🆘 **Priority Support** | SLA-backed support with guaranteed response times |

### Pricing

| Tier | Annual Price |
|:--|:--|
| **Starter Enterprise** | $5,000/yr (฿175,000/yr) |
| **Professional Enterprise** | $20,000/yr (฿700,000/yr) |
| **Custom Enterprise** | Contact us |

We also offer **Hardware Bundles** (Asgard pre-installed on Mac Mini / Mac Studio / DGX Spark / NVIDIA GPU). See [pricing-strategy.md](docs/business/pricing-strategy.md) for details.

- 📧 **Email:** paripol@megawiz.co
- 🌐 **Website:** asgardai.dev (coming soon)

---

## Components

All components of the Asgard AI Platform are covered under the same licensing terms:

| Component | Repository | Description |
|:--|:--|:--|
| 🏰 **Asgard** | [megacare-dev/Asgard](https://github.com/megacare-dev/Asgard) | Platform orchestration |
| 🛡️ **Heimdall** | [megacare-dev/Heimdall](https://github.com/megacare-dev/Heimdall) | LLM Gateway (Rust) |
| 🧠 **Mimir** | [megacare-dev/Mimir](https://github.com/megacare-dev/Mimir) | RAG + Agent Builder (Rust/Next.js) |
| ⚡ **Bifrost** | [megacare-dev/Bifrost](https://github.com/megacare-dev/Bifrost) | Agent Runtime (Python) |
| 🐺 **Fenrir** | [megacare-dev/Fenrir](https://github.com/megacare-dev/Fenrir) | Computer Use (Python) |
| 🏥 **Eir** | OpenEMR | Clinic Management (PHP, GPL v3) |
| 🌳 **Yggdrasil** | [megacare-dev/Yggdrasil](https://github.com/megacare-dev/Yggdrasil) | Auth Service (Zitadel) |

---

## FAQ

### Can I use Asgard for free?
Yes! The Community Edition under AGPL-3.0 is free for any use, including commercial internal use. You only need a commercial license if you want to keep modifications private or offer Asgard as a service.

### Can I use Asgard at my company?
Absolutely. Self-hosting Asgard for your company's internal use is fully permitted under AGPL-3.0 at no cost.

### What if I modify the code?
Under AGPL-3.0, if you modify Asgard and provide it as a network service to users, you must make the source code of your modifications available. If you need to keep modifications private, a commercial license is required.

### Do I need a license for each server?
No. The commercial license is per-organization, not per-server. Deploy on as many nodes as you need.

---

© 2026 MegaWiz. All rights reserved.
