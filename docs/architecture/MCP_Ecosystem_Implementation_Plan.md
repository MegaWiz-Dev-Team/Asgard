# Asgard MCP Ecosystem Implementation Plan

The objective is to refactor every service within the Asgard ecosystem to adhere to the Model Context Protocol (MCP) using a **Dual Layer Architecture** (REST for UI, MCP for Agent-to-Agent). To minimize memory footprint and maximize performance, we will strategically use Rust, Go, and lightweight Sidecars.

## 1. Core Services (Native High-Performance Servers)

These high-traffic services will have MCP embedded directly into their native runtimes to avoid network overhead.

### 🧠 Mimir (Knowledge Engine)
* **Language/Framework:** Rust (Axum)
* **MCP Implementation:** Introduce the `model-context-protocol` Rust crate.
* **Integration:** Add an SSE transport route (`/mcp/sse`) into `ro-ai-bridge/src/main.rs`.
* **Tools Exposed:** `search_knowledge`, `list_sources`, `get_document_chunk`.
* **Why:** Rust provides the lowest possible memory footprint (~30MB) and extreme concurrency, perfect for the core RAG engine.

### 🌳 Yggdrasil (Identity & Auth)
* **Language/Framework:** Go (Zitadel ecosystem)
* **MCP Implementation:** `mcp-golang` (github.com/metoro-io/mcp-golang).
* **Integration:** Build a minimal standalone Go process `yggdrasil-mcp` that securely interacts with Zitadel's gRPC/REST APIs using a machine user token.
* **Tools Exposed:** `validate_token`, `get_user_roles`, `assign_tenant_access`.
* **Why:** Go is extremely fast, compiles to a single small binary, and natively integrates well with Zitadel's architecture.

### 🐿️ Ratatoskr & Huginn/Muninn
* **Language/Framework:** Rust
* **MCP Implementation:** Similar to Mimir, embed the `model-context-protocol` crate locally.
* **Tools Exposed:** 
  * Ratatoskr: `crawl_url`, `screenshot_page`
  * Huginn/Muninn: `scan_vulnerability`, `generate_code_fix`

## 2. Universal Gateway Sidecars (The Pattern for Legacy/Heavy APIs)

Services that are difficult to modify or written in heavier legacy stacks will be frontlined by a unified, ultra-lightweight **Rust MCP Sidecar** (`Asgard/mcp-sidecar/`). 

### 🏥 Eir (OpenEMR)
* **Current Stack:** PHP (OpenEMR) + Python FastAPI Gateway.
* **MCP Implementation:** Deploy the Rust MCP Sidecar in front of Eir. The Sidecar translates MCP JSON-RPC tool calls into standard REST FHIR API calls to OpenEMR.
* **Tools Exposed:** `get_patient_medical_history`, `book_appointment`, `prescribe_medication`.
* **Why:** We avoid touching legacy PHP code and bypass the memory overhead of spinning up another Python MCP server.

### 🛡️ Heimdall (LLM Server)
* **Current Stack:** Python (vLLM / MLX)
* **MCP Implementation:** Rust MCP Sidecar. We do not want to add Python async MCP loop overhead to the machine already dedicating all its VRAM and CPU cycles to tensor operations.
* **Tools Exposed:** `get_model_benchmark`, `switch_active_model`, `get_gpu_vram_usage`.

## 3. Native Python Servers (For Specialized Python Libraries)

Services heavily relying on Python-only ecosystems (like browser automation or ML evaluations) will use the official Python MCP SDK, accepting the slightly higher memory cost.

### 🐺 Fenrir (Browser Agent)
* **Language/Framework:** Python (`browser-use`, Playwright)
* **MCP Implementation:** Official Python `mcp` SDK using SSE Transport in FastAPI.
* **Integration:** Fix the currently broken SSE endpoint in `fenrir/main.py`.
* **Tools Exposed:** `navigate_browser`, `click_element`, `extract_page_content`.

### ⚖️ Forseti (Testing) & 📑 PageIndex (Reasoning RAG)
* **Language/Framework:** Python
* **MCP Implementation:** Official Python `mcp` SDK.
* **Tools Exposed:** `run_test_suite`, `synthesize_document_page`.

## 4. The Orchestrator (Bifrost)

Asgard/Bifrost will act purely as the **Master MCP Client**.

* **Architecture:** In `bifrost/main.py`, the `_mcp_manager` will connect to all 11 SSE endpoints consecutively on startup. 
* **ADK Bridge:** A new engine module `bifrost/core/mcp_adapter.py` will dynamically pull the `list_tools()` payload from every single server and convert them into callable Python stub functions. These stubs are then injected dynamically into `tools=[...]` when instantiating the 12 `google-adk` `LlmAgent` instances.

---

> [!IMPORTANT]
> User Review Required
> This architecture uses a universal Rust Sidecar (`Asgard/mcp-sidecar/`) within the Asgard monorepo and heavily modifies `bifrost/main.py`. Approved and implemented in Sprint 33.
