# 🏰 Asgard — System Architecture

> A self-hosted AI platform running entirely on Apple Silicon & NVIDIA GPU.

## High-Level Overview

```mermaid
graph TB
    subgraph client["👤 Clients"]
        Dashboard["🖥️ Dashboard<br/>(Next.js)"]
        API["📡 External API<br/>(REST/SSE)"]
        Chat["💬 Chat Interface"]
    end

    subgraph asgard["🏰 Asgard AI Platform"]

        subgraph mimir["🧠 Mimir — Knowledge & Agent Builder"]
            RAG["📚 RAG Pipeline<br/>Ingest → Chunk → Embed → Search"]
            AgentBuilder["🤖 Agent Builder<br/>CRUD · Templates · Publish"]
            KB["💾 Knowledge Base<br/>(MariaDB + Qdrant)"]
            RAG --> KB
            AgentBuilder --> |"deploy agent"| BifrostLink["→ Bifrost"]
        end

        subgraph bifrost["⚡ Bifrost — Agent Runtime"]
            Executor["🔄 Agent Executor<br/>(ReAct Loop)"]
            Tools["🔧 Tool Registry<br/>(MCP Client)"]
            Sessions["💾 Session Manager<br/>Short-term + Long-term"]
            Router["🔀 Agent Router<br/>Multi-agent Handoff"]
            Executor --> Tools
            Executor --> Sessions
            Executor --> Router
        end

        subgraph heimdall["🛡️ Heimdall — LLM Gateway"]
            Proxy["🔄 Proxy Layer<br/>(Rust/Axum)"]
            Auth["🔐 Auth<br/>JWT / OIDC (Zitadel)"]
            Metrics["📊 Metrics<br/>(Prometheus)"]
            Proxy --> Auth
            Proxy --> Metrics
        end

        subgraph fenrir["🐺 Fenrir — Computer Use"]
            Browser["🌐 Browser Use<br/>Navigate · Extract · Fill"]
            FHIRClient["🏥 FHIR Client<br/>API-first"]
            Shell["💻 Shell Executor<br/>Commands · Scripts"]
            Files["📁 File Manager<br/>Read · Write · Search"]
        end

        subgraph eir["🏥 Eir — Clinic Management"]
            OpenEMR["📋 OpenEMR<br/>Patient · Encounter · Rx"]
            FHIRAPI["🔗 FHIR R4 API<br/>REST + OAuth2"]
            OpenEMR --> FHIRAPI
        end

        subgraph yggdrasil["🌳 Yggdrasil — Auth"]
            Zitadel["🔐 Zitadel<br/>OIDC · SAML · LDAP"]
            AuditLog["📋 Audit Trail<br/>Event-sourced"]
        end
    end

    subgraph backends["⚙️ LLM Backends"]
        MLX["🍎 MLX<br/>mlx_lm · mlx_vlm"]
        Llama["🦙 llama.cpp<br/>GGUF Models"]
        Ollama["🐫 Ollama<br/>Managed Models"]
        VLLM["🟢 vLLM<br/>NVIDIA CUDA"]
    end

    Dashboard --> mimir
    API --> bifrost
    Chat --> bifrost

    bifrost --> |"LLM calls"| heimdall
    bifrost --> |"RAG search<br/>(MCP)"| mimir
    bifrost --> |"Computer use<br/>(MCP)"| fenrir
    FHIRClient --> |"FHIR R4"| FHIRAPI
    Browser --> |"Browser"| OpenEMR

    heimdall --> MLX
    heimdall --> Llama
    heimdall --> Ollama
    heimdall --> VLLM

    yggdrasil -.-> |"JWT"| heimdall
    yggdrasil -.-> |"OIDC"| mimir
    yggdrasil -.-> |"JWT"| bifrost

    style asgard fill:transparent,stroke:#6366f1,stroke-width:3px
    style mimir fill:#1e1b4b,stroke:#818cf8,color:#c7d2fe
    style bifrost fill:#451a03,stroke:#f59e0b,color:#fef3c7
    style heimdall fill:#052e16,stroke:#4ade80,color:#bbf7d0
    style fenrir fill:#1c1917,stroke:#a8a29e,color:#e7e5e4
    style eir fill:#4a1942,stroke:#e879f9,color:#fae8ff
    style yggdrasil fill:#14532d,stroke:#86efac,color:#bbf7d0
    style backends fill:#0c0a09,stroke:#78716c
    style client fill:transparent,stroke:#94a3b8
```

---

## Data Flow

### Agent Execution Flow

```mermaid
sequenceDiagram
    actor User
    participant M as 🧠 Mimir
    participant B as ⚡ Bifrost
    participant H as 🛡️ Heimdall
    participant F as 🐺 Fenrir
    participant LLM as 🍎 MLX/llama.cpp

    User->>M: Create Agent (system prompt, model, tools)
    M->>M: Save to MariaDB
    M-->>User: Agent ID + API Key

    Note over User, LLM: === Agent Execution ===

    User->>B: POST /v1/agents/42/run
    B->>B: Load agent config + tools
    B->>H: Chat completion (with tools array)
    H->>LLM: Forward to MLX/llama.cpp
    LLM-->>H: tool_call: search_knowledge
    H-->>B: tool_call response

    B->>M: MCP: search_knowledge("query")
    M-->>B: Search results (3 documents)

    B->>H: Chat completion (with tool result)
    H->>LLM: Forward with context
    LLM-->>H: tool_call: browser_navigate
    H-->>B: tool_call response

    B->>F: MCP: browser_navigate(url)
    F->>F: Playwright → load page
    F-->>B: Page content extracted

    B->>H: Chat completion (final)
    H->>LLM: Forward with all context
    LLM-->>H: Final answer
    H-->>B: Response text

    B->>B: Save to session + log usage
    B-->>User: Final answer + execution trace
```

---

## Component Details

### 🧠 Mimir — Knowledge & Agent Builder

```mermaid
graph LR
    subgraph ingestion["📥 Document Ingestion"]
        Upload["Upload Files"]
        Crawl["Web Crawler"]
        DB["DB Connector"]
    end

    subgraph pipeline["⚙️ Processing Pipeline"]
        Extract["Extract Text"]
        Chunk["Smart Chunking"]
        Embed["Embedding<br/>(MLX)"]
        Dedup["Deduplication"]
    end

    subgraph storage["💾 Storage"]
        MariaDB["MariaDB<br/>(Relational)"]
        Vectors["Vector Store<br/>(Embeddings)"]
    end

    subgraph api["🔌 APIs"]
        Search["Semantic Search"]
        AgentAPI["Agent CRUD"]
        DashAPI["Dashboard API"]
    end

    ingestion --> pipeline --> storage
    storage --> api

    style ingestion fill:#312e81,stroke:#818cf8
    style pipeline fill:#312e81,stroke:#818cf8
    style storage fill:#1e1b4b,stroke:#6366f1
    style api fill:#1e1b4b,stroke:#6366f1
```

| Feature | Description |
|:--|:--|
| **Stack** | Rust (Axum + Rig.rs) + Next.js 14 + MariaDB + Qdrant |
| **Port** | `3000` (API) / `3001` (Dashboard) |
| **Repo** | [megacare-dev/Mimir](https://github.com/megacare-dev/Mimir) |

---

### 🛡️ Heimdall — LLM Gateway

```mermaid
graph LR
    Client["Client Request<br/>/v1/chat/completions"] --> Auth["🔐 Auth<br/>Bearer Token"]
    Auth --> Router["🔄 Router<br/>Model → Backend"]
    Router --> MLX["🍎 mlx_lm<br/>:8081"]
    Router --> VLM["👁️ mlx_vlm<br/>:8082"]
    Router --> LC["🦙 llama.cpp<br/>:8083"]
    Router --> OL["🐫 Ollama<br/>:11434"]
    Router --> VL["🟢 vLLM<br/>:8084"]

    MLX --> Response["📤 Response<br/>(SSE Stream)"]
    VLM --> Response
    LC --> Response
    OL --> Response
    VL --> Response

    Response --> Metrics["📊 Prometheus<br/>Metrics"]

    style Auth fill:#052e16,stroke:#4ade80
    style Router fill:#052e16,stroke:#4ade80
    style Metrics fill:#052e16,stroke:#4ade80
```

| Feature | Description |
|:--|:--|
| **Stack** | Rust (Axum + Tokio) |
| **Port** | `8080` |
| **Protocol** | OpenAI-compatible API |
| **Backends** | MLX, mlx_vlm, llama.cpp, Ollama, vLLM |
| **Repo** | [megacare-dev/Heimdall](https://github.com/megacare-dev/Heimdall) |

---

### ⚡ Bifrost — Agent Runtime

```mermaid
graph TB
    Input["📩 User Message"] --> Context["📋 Build Context<br/>System Prompt + History + Tools"]
    Context --> LLM["🤖 Call LLM<br/>(via Heimdall)"]
    LLM --> Decision{Response Type?}

    Decision --> |"tool_call"| Execute["🔧 Execute Tool<br/>(MCP)"]
    Execute --> Append["📝 Append Result"]
    Append --> LLM

    Decision --> |"text"| Final["✅ Final Answer"]
    Final --> Log["📊 Log Trace + Usage"]
    Log --> Return["📤 Return to User"]

    style Input fill:#451a03,stroke:#f59e0b
    style LLM fill:#451a03,stroke:#f59e0b
    style Execute fill:#451a03,stroke:#f59e0b
    style Final fill:#422006,stroke:#fbbf24
```

| Feature | Description |
|:--|:--|
| **Stack** | Python (FastAPI + Uvicorn) |
| **Port** | `8100` |
| **Protocol** | REST + SSE + MCP Client |
| **Repo** | [megacare-dev/Bifrost](https://github.com/megacare-dev/Bifrost) |

---

### 🐺 Fenrir — Computer Use

```mermaid
graph LR
    MCP["📡 MCP Server<br/>(Python)"] --> Browser["🌐 Browser Use<br/>Playwright"]
    MCP --> FHIR["🏥 FHIR R4<br/>OpenEMR API"]
    MCP --> Shell["💻 Shell<br/>Sandboxed"]
    MCP --> FileOps["📁 Files<br/>Scoped"]

    Browser --> Web["Navigate · Extract · Fill · Screenshot"]
    FHIR --> EMR["Patient · Encounter · Observation"]
    Shell --> Cmd["Run commands · Execute scripts"]
    FileOps --> FS["Read · Write · Search"]

    style MCP fill:#1c1917,stroke:#a8a29e
    style Browser fill:#292524,stroke:#78716c
    style FHIR fill:#292524,stroke:#78716c
    style Shell fill:#292524,stroke:#78716c
    style FileOps fill:#292524,stroke:#78716c
```

| Feature | Description |
|:--|:--|
| **Stack** | Python (Browser Use + FHIR Client) |
| **Port** | `8200` (localhost only) |
| **Protocol** | MCP Server |
| **Browser** | Browser Use (Playwright-based, natural language) |
| **API** | FHIR R4 Client for OpenEMR (API-first approach) |
| **Security** | Sandbox, localhost-only, no external LLM for patient data |
| **Repo** | [megacare-dev/Fenrir](https://github.com/megacare-dev/Fenrir) |

---

## Network Map

```mermaid
graph LR
    subgraph exposed["🌐 External Access"]
        P3000["Mimir API<br/>:3000"]
        P3001["Dashboard<br/>:3001"]
        P8080["Heimdall<br/>:8080"]
        P8085["Yggdrasil<br/>:8085"]
        P8100["Bifrost<br/>:8100"]
    end

    subgraph internal["🔒 Internal Only"]
        P8081["mlx_lm<br/>:8081"]
        P8082["mlx_vlm<br/>:8082"]
        P8083["llama.cpp<br/>:8083"]
        P8084["vLLM<br/>:8084"]
        P11434["Ollama<br/>:11434"]
        P8200["Fenrir<br/>:8200"]
        P80["Eir (OpenEMR)<br/>:80"]
    end

    P8080 --> P8081
    P8080 --> P8082
    P8080 --> P8083
    P8080 --> P8084
    P8080 --> P11434
    P8100 --> P8200

    style exposed fill:#1e293b,stroke:#60a5fa
    style internal fill:#1e293b,stroke:#ef4444
```

---

## Tech Stack Summary

| Layer | Technology | Why |
|:--|:--|:--|
| **LLM Inference** | MLX, llama.cpp, Ollama, vLLM | Apple Silicon + NVIDIA optimized |
| **Gateway** | Rust (Axum + Tokio) | Zero-cost abstractions, async |
| **RAG Backend** | Rust (Axum) + MariaDB + Qdrant | Type-safe, fast, scalable |
| **Dashboard** | Next.js + React | Modern, SSR, component-based |
| **Agent Runtime** | Python (FastAPI) | Rich AI ecosystem (MCP, LangGraph) |
| **Computer Use** | Python (Browser Use + FHIR) | Natural language browser control, OpenEMR integration |
| **Protocol** | MCP (Model Context Protocol) | Standard tool interface |
| **Hardware** | Mac Mini M4 Pro, 64GB | Unified memory, 273 GB/s bandwidth |
