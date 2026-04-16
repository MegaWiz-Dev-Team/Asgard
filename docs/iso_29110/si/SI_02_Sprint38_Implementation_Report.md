# ISO/IEC 29110 Software Implementation Report
## SI_02: Component Verification and Architetural Standardization
**Sprint:** 38
**Date:** 2026-04-16
**Author:** Asgard Platform Engineering

### 1. Objective
To document the architectural standardization of the native macOS Host environment, ensuring compliance with ISO 27001 (Log Retention & Auditing) and streamlining the container runtime dependency by migrating to OrbStack. This report details the removal of deprecated services and the introduction of new security and logging handlers.

### 2. Implementation Summary

#### 2.1 Deprecation and Removal of Legacy Services
- **Colima Container Runtime**: Removed `com.asgard.colima.plist` as the internal cluster is now fully stabilized on **OrbStack**.
- **llama.cpp Host Daemon**: Unloaded and removed `com.asgard.heimdall-llama.plist`. The legacy GGUF infrastructure proved highly unstable with external symlinks traversing to the T7 Shield.
- **Python Embedding Server**: Removed `com.asgard.heimdall-embedding.plist`. Embedding requests are now natively handled by the Heimdall Gateway `fastembed` ONNX execution engine without requiring a secondary process.

#### 2.2 Introduction of Optimized Native Services
The macOS launchd host environment has been simplified to run three primary active components:
1. **Heimdall API Gateway (`:8080`)**: Native Rust processing for API orchestration, tenant validation, and built-in ONNX fast-embedding operations.
2. **MLX Backend (`:8081`)**: Standalone `mlx_lm.server` for running Metal-optimized Large Language Models (LLM) serving generative text outputs.
3. **Vardr Agent (`:9091`)**: Host telemetry metrics collector exposing Docker and Host metrics.

#### 2.3 Compliance and Log Management (ISO 27001 Application)
To satisfy Information Security Management System (ISMS) logging requirements regarding traceablity and audit protection (ISO 27001 Annex A.12.4.1, A.12.4.3):

* **Log Shipper Automation**: Implemented a new daemon (`com.asgard.heimdall-logshipper.plist`) configured to persistently `tail` both Heimdall and MLX standard outputs and stream them using bulk NDJSON directly to the internal Kubernetes **Wazuh Indexer (Tyr)**.
* **Log Archive Policy (T7 Shield)**: Implemented `$PROJECT_DIR/scripts/log_archiver.sh` scheduled via launchd (`com.asgard.log-archiver.plist`) at exactly `00:00` daily. 
   - Utilizes `copytruncate` to safely back up logs to `/Volumes/T7 Shield/Asgard-Archives/Heimdall-Logs/` without dropping I/O streams.
   - Archives older than 365 days are automatically pruned, satisfying both local storage limitations and 12-month ISO auditing requirements.

### 3. Verification & Testing
- ✅ Verified `launchd` loaded daemons via `launchctl list | grep asgard` (Returns Gateway, MLX, Vardr, Log Shipper).
- ✅ Validated NDJSON payload arrival in Wazuh Indexer OpenSearch indices `heimdall-logs-YYYY.MM.DD`.
- ✅ E2E Pipeline connectivity: `mimir-api` explicitly routes embedding and vector operations to the native Heimdall ONNX endpoint with success (Tested across Megacare Tenant context).

### 4. Conclusion
The environment is stabilized, and ISO 27001 Log Auditing standards are actively satisfied for the host layer. Legacy architectural diagrams have been correctly redrawn in the central Asgard `architecture.md`.
