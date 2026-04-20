# Advanced LLM Observability & MLOps Stack

## 1. Executive Summary
Asgard requires deep observability for its Agentic Engine (**Bifrost**) and API bridge (**Mimir**). In order to achieve a secure, high-performance, and standard-compliant tracing hierarchy, Asgard implements a decoupled **OpenTelemetry (OTel)** topology that pushes real-time analytical traces into **Laminar (lmnr)**, while safely mirroring text logs for threat hunting to **Týr (Wazuh SIEM)**.

## 2. Infrastructure Architecture (K3s native)

The following components are deployed via Asgard's primary Helm structure (`charts/asgard`):

### 2.1 The OpenTelemetry (OTel) Collector
- **Role:** The central nervous system for telemetry within the cluster.
- **Why:** Prevents vendor lock-in. Applications do not need specific Laminar SDKs; they simply export OTLP standards.
- **Topology:**
    - **Receivers:** `0.0.0.0:4317` (gRPC), `0.0.0.0:4318` (HTTP)
    - **Exporters:** 
        - Generates tracing payload towards Laminar's `8001` backend port.
        - Streams specific log data to Týr (Wazuh) for immediate prompt-injection and PII leak detection.

### 2.2 Connected LLM Trace Producers
Any service making decisions via LLMs or handling context must funnel spans directly to the OTel Collector. This forms an unbroken, full-stack trace in Laminar.
- **Heimdall:** Emits literal Inference Latency, Token Usage, and Hardware wait times.
- **Mimir:** Emits RAG (Vector Search) latency and context-assembly spans.
- **Bifrost:** Emits precise ReAct "Tree of Thought" loops (Reasoning vs. Action).
- **Hermóðr:** (MCP Sidecar) Emits routing decisions and tool-call contexts sent between Agents and MCP servers.
- **Fenrir:** Emits Browser-use and shell interaction steps governed by the LLM.
- **Eir Gateway:** Emits Agent-to-Agent (A2A) task delegation checkpoints.

### 2.2 Laminar (`lmnr-ai/lmnr`)
Laminar is deployed as an infrastructure sub-chart (`charts/asgard/charts/laminar`):
- **App Service:** A High-performance Rust-backend trace ingester and UI dashboard.
- **PostgreSQL Database:** Dedicated OLTP database storing UI-level states, user configurations, and API keys.
- **ClickHouse Cluster:** Dedicated OLAP database storing trace steps and high-volume spans efficiently.
- **RabbitMQ:** Temporary buffer to prevent packet loss during massive inbound LLM tracing requests.

## 3. Rust Native Instrumentation Strategy

Applications within Asgard do NOT require closed-source or vendor SDKs. They rely strictly on **`opentelemetry-otlp`** and **`tracing-opentelemetry`**.

### 3.1 Initializing the Telemetry Pipeline
All microservices (Heimdall, Mimir, Bifrost) inject the following OTel pipeline during `main()` bootstrap:

```rust
let tracer = opentelemetry_otlp::new_pipeline()
    .tracing()
    .with_exporter(opentelemetry_otlp::new_exporter().tonic().with_endpoint("http://otel-collector.infra.svc:4317"))
    .install_batch(opentelemetry_sdk::runtime::Tokio)
    .expect("Failed to initialize OTLP Tracer");

let telemetry = tracing_opentelemetry::layer().with_tracer(tracer);

tracing_subscriber::registry()
    .with(tracing_subscriber::EnvFilter::from_default_env())
    .with(telemetry)
    .init();
```

### 3.2 Spanning Business Logic
To record the inner "Tree of Thoughts" of a ReAct Agent, we decorate asynchronous polling functions with specific hierarchical spans. Trace IDs are automatically propagated.

```rust
#[tracing::instrument(skip(self, session_context), fields(tenant_id = %session.tenant_id))]
pub async fn execute_agent_loop(&self, session_context: &Context) -> Result<String, Error> {
    // Engine spans will route through OTel -> Laminar
}
```

## 4. Operational Maintenance & Scale
- Trace data stored in ClickHouse inherently scales horizontally.
- To prevent storage exhaustion, specific Time-to-Live (TTL) policies should be applied in ClickHouse to prune spans older than 14-days unless specifically pinned for MLOps Evaluation.
