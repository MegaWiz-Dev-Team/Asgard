---
name: security-audit
description: Trigger for code security scanning, vulnerability assessment, SAST/DAST analysis, and compliance checks. Use when asked to audit code, scan for vulnerabilities, review dependencies, or prepare security reports.
version: "1.0"
author: asgard-team
tags: [security, audit, vulnerability, compliance, scanning]
tools: [huginn_scan, fenrir_execute]
---

# Security Audit

## Overview
Comprehensive security scanning and vulnerability assessment skill. Integrates with Huginn (Semgrep + Trivy) for SAST, container scanning, and dependency auditing across the Asgard ecosystem.

## When to Use
- Pre-release security gate (Sprint closing requirement)
- Code review with security focus
- Dependency vulnerability scanning
- Container image scanning
- Compliance audit preparation

## Instructions
1. **Identify scan scope** — determine which services/repos to scan
2. **Run SAST scan** — use `huginn_scan` with Semgrep rules for:
   - SQL injection patterns
   - Hardcoded secrets
   - Insecure deserialization
   - Path traversal
   - XSS vulnerabilities
3. **Run dependency scan** — use Trivy for:
   - Known CVEs in dependencies
   - Outdated packages with security patches
   - License compliance issues
4. **Run container scan** — if Dockerfiles present:
   - Base image vulnerabilities
   - Unnecessary privileges
   - Exposed ports
5. **Generate report** with:
   - Finding severity (Critical/High/Medium/Low)
   - Affected files and line numbers
   - Remediation recommendations
   - Compliance status (pass/fail)

## Quality Bar
- All Critical and High findings must have remediation steps
- False positives must be documented with justification
- Scan timestamp and tool versions must be recorded
- Results must be pushed to Forseti for tracking

## Common Mistakes to Avoid
- Do NOT ignore Medium-severity findings without review
- Do NOT assume container base images are safe
- Do NOT skip dependency scanning for Rust/Go (cargo-audit, govulncheck)
