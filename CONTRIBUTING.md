# Contributing to Asgard AI Platform

Thank you for your interest in contributing to Asgard! 🏰

## How to Contribute

### 🐛 Bug Reports

Please [open an issue](https://github.com/MegaWiz-Dev-Team/Asgard/issues/new) with:
- Clear description of the bug
- Steps to reproduce
- Expected vs actual behavior
- System info (OS, hardware, Docker version)

### 💡 Feature Requests

[Open an issue](https://github.com/MegaWiz-Dev-Team/Asgard/issues/new) with:
- Description of the feature
- Use case / why it's needed
- Which component it affects (Heimdall, Mimir, Bifrost, Fenrir, Yggdrasil)

### 🔧 Pull Requests

1. Fork the repository
2. Create a branch with the right prefix (see [Branching Strategy](#branching-strategy) below)
3. Make your changes
4. Write/update tests if applicable
5. Commit with [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, etc.
6. Push to your fork and open a PR
7. Wait for CI (Build and Push) to pass + 1 maintainer approval (see [CODEOWNERS](.github/CODEOWNERS))

## Branching Strategy

Asgard uses **GitHub Flow + Release Trunk** (hybrid).

### Day-to-day development

```
main            ← always-deployable, latest stable
  ↑
  PR with required CI passing + 1 approval
  ↑
feat/<short>    ← new feature
fix/<short>     ← bug fix
chore/<short>   ← tooling/refactor (no behavior change)
docs/<short>    ← docs-only
revert/<orig>   ← explicit revert
```

| Prefix | Use for | Example |
|---|---|---|
| `feat/` | New feature, user-visible behavior | `feat/multi-tenant-rbac` |
| `fix/` | Bug fix, no API change | `fix/oidc-issuer-internal-url` |
| `chore/` | Tooling, deps, refactor | `chore/upgrade-rust-1.88` |
| `docs/` | Docs-only changes | `docs/sprint-51d-retro` |
| `hotfix/` | Urgent fix to a release branch | `hotfix/v1.0.x-cve-2026-12345` |
| `release/` | LTS release branch (maintainer-only) | `release/v1.0` |
| `revert/` | Explicit revert of a prior change | `revert/pr-19-split-arch` |

### Release branches (LTS)

Once Asgard hits Enterprise GA (Q3 2027), each minor version gets a long-lived `release/v<major>.<minor>` branch:

```
release/v1.0    ← LTS, 12-month support window
release/v1.1    ← current, will become LTS when v1.2 ships
main            ← v1.2-dev (next release)
```

**Backport policy:**
- Bug fix lands on `main` first → cherry-pick to `release/v1.0`, `release/v1.1` if applicable
- Security fixes (CVE) → backport to all supported release branches
- Features stay on `main` only — never backport to LTS

### Image / version tagging

| Source | Image tag pushed to ghcr.io |
|---|---|
| `main` push | `:sha-<commit>` + `:edge` |
| Tag `v1.1.0` | `:v1.1.0` (immutable) + `:1.1` (rolling within minor) |
| `:latest` | latest stable release (default for community) |

Enterprise customers should pin to specific `:v1.X` (LTS) per their support contract.

### Branch protection rules (enforced)

`main` and `release/*` branches require:
- ✅ Pull Request with at least **1 maintainer approval** (per [CODEOWNERS](.github/CODEOWNERS))
- ✅ Status check: **Build and Push** workflow must pass
- ✅ Branch must be up-to-date with target before merging
- ✅ **Linear history** — squash or rebase merge only (no merge commits)
- ❌ No force-push, no branch deletion
- ❌ No bypass except for documented emergencies (audit-logged)

### Hotfix flow (security/critical)

1. Branch from `release/v1.0` → `hotfix/v1.0.x-<short>`
2. Fix + add regression test
3. Open PR to `release/v1.0` (require security review for CVEs)
4. Tag `v1.0.x` once merged → CI builds + ships hotfix image
5. Cherry-pick to `main` and other supported release branches
6. Publish [GitHub Security Advisory](https://github.com/MegaWiz-Dev-Team/Asgard/security/advisories) for CVEs

### 📝 Documentation

Documentation improvements are always welcome! See `docs/` for existing docs.

## Development Setup

```bash
# Clone the repo
git clone https://github.com/MegaWiz-Dev-Team/Asgard.git
cd Asgard

# Start infrastructure
docker compose up -d

# See individual component READMEs for setup:
# - Heimdall: https://github.com/MegaWiz-Dev-Team/Heimdall
# - Mimir: https://github.com/MegaWiz-Dev-Team/Mimir
# - Bifrost: https://github.com/MegaWiz-Dev-Team/Bifrost
```

## Component Repositories

| Component | Repo | Language |
|:--|:--|:--|
| 🛡️ Heimdall | [MegaWiz-Dev-Team/Heimdall](https://github.com/MegaWiz-Dev-Team/Heimdall) | Rust |
| 🧠 Mimir | [MegaWiz-Dev-Team/Mimir](https://github.com/MegaWiz-Dev-Team/Mimir) | Rust + Next.js |
| ⚡ Bifrost | [MegaWiz-Dev-Team/Bifrost](https://github.com/MegaWiz-Dev-Team/Bifrost) | Python |
| 🐺 Fenrir | [MegaWiz-Dev-Team/Fenrir](https://github.com/MegaWiz-Dev-Team/Fenrir) | Python |

## Contributor License Agreement (CLA)

By submitting a pull request, you agree to our [CLA](CLA.md). Your first PR serves as your electronic signature.

## Code of Conduct

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## Questions?

- Open a [GitHub Discussion](https://github.com/MegaWiz-Dev-Team/Asgard/discussions)
- Email: paripol@megawiz.co

---

Thank you for helping build Asgard! ⚡
