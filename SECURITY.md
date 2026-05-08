# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in any Asgard AI Platform component, please email **paripol@megawiz.co** instead of opening a public GitHub issue, pull request, or discussion.

We aim to:

- **Acknowledge** your report within **48 hours**.
- Provide a **fix or mitigation timeline** within **7 days** of acknowledgement.
- Allow **up to 90 days** for coordinated disclosure before details are published.

## Scope

This policy covers all repositories under the [MegaWiz-Dev-Team](https://github.com/MegaWiz-Dev-Team) organization that are part of the Asgard AI Platform:

- 🏰 **Asgard** — Platform orchestration & infrastructure
- 🛡️ **Heimdall** — LLM gateway
- 🧠 **Mimir** — RAG + Agent Builder
- ⚡ **Bifrost** — Agent runtime
- 🌳 **Yggdrasil** — Auth (Zitadel-based)
- 🐺 **Fenrir** — Computer-use agent
- 📨 **Hermóðr** — Universal MCP sidecar

## Out of Scope

- Issues affecting unsupported / archived branches.
- Third-party dependencies (please report upstream first; we will track via Dependabot/security advisories).
- Self-reported reproductions in non-default configurations (e.g. running services with disabled authentication).

## Supported Versions

The latest commit on `main` of each repository is the only supported version. We do not backport security fixes to older releases.
