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
