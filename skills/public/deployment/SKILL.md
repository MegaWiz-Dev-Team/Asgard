---
name: deployment
description: Use for deploying Asgard services, managing Docker containers, docker-compose operations, CI/CD pipeline tasks, and environment management. Trigger on deploy, release, build, or infrastructure requests.
version: "1.0"
author: asgard-team
tags: [devops, deployment, docker, CI/CD, infrastructure]
tools: [fenrir_execute, docker_compose]
---

# Deployment

## Overview
Service deployment and infrastructure management skill for the Asgard ecosystem. Handles Docker-based deployments, environment configuration, and CI/CD pipeline operations.

## When to Use
- Deploying new service versions
- Docker container management (build, push, restart)
- docker-compose operations
- Environment variable configuration
- Health check verification post-deploy
- Rollback operations

## Instructions
1. **Pre-deployment checks**:
   - Verify all tests pass (check Forseti)
   - Verify security scan clean (check Huginn)
   - Confirm target environment and version
2. **Build phase**:
   - Build Docker images with version tags
   - Tag with both version and `latest`
   - Push to container registry
3. **Deploy phase**:
   - Update docker-compose.yml with new image tags
   - Run `docker-compose up -d` for target services
   - Wait for health checks to pass
4. **Post-deployment verification**:
   - Hit health endpoints for all deployed services
   - Verify API responses are correct
   - Check logs for startup errors
5. **Rollback plan**:
   - If health checks fail, revert to previous image tag
   - Document failure reason

## Asgard Services Reference

| Service | Port | Health Endpoint |
|---|---|---|
| Mimir | 3000 | `/health` |
| Bifrost | 8100 | `/health` |
| Heimdall | 8080 | `/health` |
| Eir | 8300 | `/api/health` |
| Fenrir | 8200 | `/health` |
| Yggdrasil | 8085 | `/health` |
| Ratatoskr | 8400 | `/health` |

## Quality Bar
- Zero-downtime deployment when possible
- All health checks must pass before declaring success
- Deployment log must be recorded
- Version tag must match git tag
