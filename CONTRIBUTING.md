# Contributing to Asgard AI Platform

Thank you for your interest in contributing to Asgard! 🏰

## How to Contribute

### 🐛 Bug Reports

Please [open an issue](https://github.com/megacare-dev/Asgard/issues/new) with:
- Clear description of the bug
- Steps to reproduce
- Expected vs actual behavior
- System info (OS, hardware, Docker version)

### 💡 Feature Requests

[Open an issue](https://github.com/megacare-dev/Asgard/issues/new) with:
- Description of the feature
- Use case / why it's needed
- Which component it affects (Heimdall, Mimir, Bifrost, Fenrir, Yggdrasil)

### 🔧 Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Write/update tests if applicable
5. Commit with [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, etc.
6. Push to your fork and open a PR

### 📝 Documentation

Documentation improvements are always welcome! See `docs/` for existing docs.

## Development Setup

```bash
# Clone the repo
git clone https://github.com/megacare-dev/Asgard.git
cd Asgard

# Start infrastructure
docker compose up -d

# See individual component READMEs for setup:
# - Heimdall: https://github.com/megacare-dev/Heimdall
# - Mimir: https://github.com/megacare-dev/Mimir
# - Bifrost: https://github.com/megacare-dev/Bifrost
```

## Component Repositories

| Component | Repo | Language |
|:--|:--|:--|
| 🛡️ Heimdall | [megacare-dev/Heimdall](https://github.com/megacare-dev/Heimdall) | Rust |
| 🧠 Mimir | [megacare-dev/Mimir](https://github.com/megacare-dev/Mimir) | Rust + Next.js |
| ⚡ Bifrost | [megacare-dev/Bifrost](https://github.com/megacare-dev/Bifrost) | Python |
| 🐺 Fenrir | [megacare-dev/Fenrir](https://github.com/megacare-dev/Fenrir) | Python |

## Contributor License Agreement (CLA)

By submitting a pull request, you agree to our [CLA](CLA.md). Your first PR serves as your electronic signature.

## Code of Conduct

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## Questions?

- Open a [GitHub Discussion](https://github.com/megacare-dev/Asgard/discussions)
- Email: paripol@megawiz.co

---

Thank you for helping build Asgard! ⚡
