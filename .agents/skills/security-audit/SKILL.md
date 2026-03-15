---
name: security-audit
description: "Perform security audits, threat modeling (STRIDE), HIPAA/PDPA compliance checks, dependency scanning, and Docker hardening for Asgard components."
---

# Security Audit

> "Security is not a feature — it's a requirement."

## Purpose

Conduct structured security reviews across Asgard components. Especially critical for Eir (medical data, HIPAA/PDPA) and Yggdrasil (authentication).

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/architecture.md` | System boundaries and data flows |
| `docker-compose.yml` | Service exposure and networking |
| `docs/strategy/platform-review.md` | Compliance requirements |

---

## Process

### 1️⃣ Threat Modeling (STRIDE)

For each component, evaluate:

| Threat | Question |
|--------|----------|
| **S**poofing | Can an attacker impersonate a user or service? |
| **T**ampering | Can data be modified in transit or at rest? |
| **R**epudiation | Can actions be denied without audit trail? |
| **I**nformation Disclosure | Can sensitive data leak? |
| **D**enial of Service | Can the service be overwhelmed? |
| **E**levation of Privilege | Can a user gain unauthorized access? |

### 2️⃣ HIPAA/PDPA Compliance Checklist

For Eir and any component handling medical/personal data:

```markdown
## Data Protection
- [ ] PHI encrypted at rest (database-level encryption)
- [ ] PHI encrypted in transit (TLS 1.2+)
- [ ] Minimum necessary access principle applied
- [ ] Data retention policy defined and enforced
- [ ] Audit logging for all PHI access

## Access Controls
- [ ] Role-based access control (RBAC) via Yggdrasil
- [ ] Session timeout configured
- [ ] Multi-factor authentication available (Enterprise)
- [ ] Password policy enforcement

## Operational
- [ ] Incident response plan documented
- [ ] Breach notification procedure defined
- [ ] Business Associate Agreement (BAA) template ready
- [ ] Annual security training plan
```

### 3️⃣ OWASP API Security Top 10

Review each API service against:
1. Broken Object Level Authorization (BOLA)
2. Broken Authentication
3. Broken Object Property Level Authorization
4. Unrestricted Resource Consumption
5. Broken Function Level Authorization
6. Unrestricted Access to Sensitive Business Flows
7. Server-Side Request Forgery (SSRF)
8. Security Misconfiguration
9. Improper Inventory Management
10. Unsafe Consumption of APIs

### 4️⃣ Dependency Audit

```bash
# Rust projects (Heimdall, Mimir, Eir, Vardr)
cargo audit

# Python projects (Bifrost, Fenrir, Yggdrasil)
pip-audit

# Node.js (Mimir Dashboard)
npm audit
```

### 5️⃣ Docker Security

- [ ] Non-root user in all Dockerfiles
- [ ] No secrets in Docker images or layers
- [ ] Read-only filesystem where possible
- [ ] Resource limits set (CPU, memory)
- [ ] Health checks defined
- [ ] Network isolation between services
- [ ] No `--privileged` flag usage

### 6️⃣ Output

Write findings to `docs/technical/security-audit-YYYY-MM.md`:
```
# Security Audit — [Month Year]
## Scope
## Findings (Critical / High / Medium / Low)
## Compliance Status
## Remediation Plan
## Next Review Date
```

---

## Key Principles
- Assume breach — design for detection, not just prevention
- Medical data gets the highest protection tier
- Automate what you can (cargo audit in CI)
- Review quarterly at minimum, after every major change

## When to Use
Before public launch, after adding a new service, quarterly review, or when handling a new data type.
