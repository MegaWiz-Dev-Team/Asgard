//! MCP Sidecar — Universal REST→JSON-RPC 2.0 bridge for Asgard AI Platform.
//!
//! Wraps any REST service and exposes its endpoints as MCP tools.
//! Uses `SERVICE_NAME` env var to load service-specific tool definitions.
//!
//! Part of the Asgard AI Platform (Sprint 33).

mod jsonrpc;
mod path;
mod proxy;
mod registry;
mod services;

use std::sync::Arc;
use axum::{extract::State, http::HeaderMap, routing::{get, post}, Json, Router};
use tracing_subscriber::EnvFilter;

use crate::jsonrpc::{
    Request, Response, ToolCallParams, CODE_INVALID_PARAMS,
    CODE_METHOD_NOT_FOUND, CODE_PARSE_ERROR,
};
use crate::path::{expand_path, extract_body_args};
use crate::proxy::Proxy;
use crate::registry::ToolRegistry;

// ─── Shared State ────────────────────────────────────────────────────────

struct AppState {
    registry: ToolRegistry,
    proxy: Proxy,
    service_name: String,
}

// ─── Handlers ────────────────────────────────────────────────────────────

async fn rpc_handler(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    body: String,
) -> Json<Response> {
    // Parse JSON-RPC request
    let req: Request = match serde_json::from_str(&body) {
        Ok(r) => r,
        Err(_) => {
            return Json(Response::error(
                serde_json::Value::Null,
                CODE_PARSE_ERROR,
                "Parse error: invalid JSON",
            ));
        }
    };

    let id = req.id.clone();

    match req.method.as_str() {
        "initialize" => Json(Response::success(
            id,
            serde_json::json!({
                "protocolVersion": "2024-11-05",
                "serverInfo": {
                    "name": &state.service_name,
                    "version": env!("CARGO_PKG_VERSION"),
                },
                "capabilities": { "tools": {} }
            }),
        )),

        "tools/list" => Json(Response::success(
            id,
            serde_json::json!({ "tools": state.registry.mcp_tool_list() }),
        )),

        "tools/call" => {
            let params: ToolCallParams = match serde_json::from_value(req.params) {
                Ok(p) => p,
                Err(e) => {
                    return Json(Response::error(id, CODE_INVALID_PARAMS, format!("Invalid params: {}", e)));
                }
            };

            // Find tool
            let tool = match state.registry.get(&params.name) {
                Some(t) => t,
                None => {
                    return Json(Response::error(
                        id,
                        CODE_METHOD_NOT_FOUND,
                        format!("tool not found: {}", params.name),
                    ));
                }
            };

            // Expand path + extract body
            let expanded = expand_path(&tool.path, &params.arguments);
            let body_args = extract_body_args(&tool.path, &params.arguments);
            let body_value = body_args.map(|m| serde_json::Value::Object(m));

            // Forward headers
            let mut fwd_headers = Vec::new();
            if let Some(auth) = headers.get("authorization").and_then(|v| v.to_str().ok()) {
                fwd_headers.push(("Authorization".to_string(), auth.to_string()));
            }
            if let Some(tenant) = headers.get("x-tenant-id").and_then(|v| v.to_str().ok()) {
                fwd_headers.push(("X-Tenant-Id".to_string(), tenant.to_string()));
            }

            // Call upstream
            match state.proxy.call(&tool.method, &expanded, body_value.as_ref(), &fwd_headers).await {
                Ok(result) => {
                    let text = serde_json::to_string(&result).unwrap_or_default();
                    Json(Response::success(
                        id,
                        serde_json::json!({
                            "content": [{ "type": "text", "text": text }]
                        }),
                    ))
                }
                Err(rpc_err) => Json(Response::error(id, rpc_err.code, rpc_err.message)),
            }
        }

        _ => Json(Response::error(id, CODE_METHOD_NOT_FOUND, format!("method not found: {}", req.method))),
    }
}

async fn health_handler(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "healthy",
        "service": &state.service_name,
        "tools": state.registry.count(),
    }))
}

// ─── App Builder ─────────────────────────────────────────────────────────

pub fn build_app(service_name: &str, upstream_url: &str) -> Router {
    let registry = ToolRegistry::new();

    // Load tools based on service name
    let name_lower = service_name.to_lowercase();
    if name_lower.contains("yggdrasil") {
        for tool in services::yggdrasil::tools() {
            tracing::info!("  ✅ registered tool: {}", tool.name);
            registry.register(tool);
        }
    }
    if name_lower.contains("eir") {
        for tool in services::eir::tools() {
            tracing::info!("  ✅ registered tool: {}", tool.name);
            registry.register(tool);
        }
    }

    if registry.count() == 0 {
        tracing::warn!("⚠️ No built-in tools for service {service_name}");
    }

    let state = Arc::new(AppState {
        registry,
        proxy: Proxy::new(upstream_url),
        service_name: service_name.to_string(),
    });

    Router::new()
        .route("/rpc", post(rpc_handler))
        .route("/health", get(health_handler))
        .with_state(state)
}

// ─── Main ────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let service_name = std::env::var("SERVICE_NAME").unwrap_or_else(|_| "mcp-sidecar".into());
    let upstream_url = std::env::var("UPSTREAM_URL").unwrap_or_else(|_| "http://localhost:8080".into());
    let port = std::env::var("PORT").unwrap_or_else(|_| "8090".into());
    let addr = format!("0.0.0.0:{}", port);

    tracing::info!(service = %service_name, upstream = %upstream_url, addr = %addr, "Starting MCP Sidecar");

    let app = build_app(&service_name, &upstream_url);

    let listener = tokio::net::TcpListener::bind(&addr).await.expect("Failed to bind");
    tracing::info!("MCP Sidecar listening on {addr}");

    axum::serve(listener, app).await.expect("Server error");
}

// ─── Integration Tests ───────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request as HttpRequest, StatusCode};
    use axum::routing::post as axum_post;
    use tower::ServiceExt;
    use crate::jsonrpc::CODE_INTERNAL_ERROR;

    fn test_app() -> Router {
        let registry = ToolRegistry::new();
        for tool in services::yggdrasil::tools() {
            registry.register(tool);
        }
        for tool in services::eir::tools() {
            registry.register(tool);
        }

        // We use a mock upstream URL (tests won't actually call it for these tests)
        let state = Arc::new(AppState {
            registry,
            proxy: Proxy::new("http://localhost:99999"),
            service_name: "test-sidecar".into(),
        });

        Router::new()
            .route("/rpc", axum_post(rpc_handler))
            .route("/health", get(health_handler))
            .with_state(state)
    }

    async fn rpc_request(app: &Router, body: &str) -> Response {
        let req = HttpRequest::builder()
            .method("POST")
            .uri("/rpc")
            .header("content-type", "application/json")
            .body(Body::from(body.to_string()))
            .unwrap();

        let resp = app.clone().oneshot(req).await.unwrap();
        let body = axum::body::to_bytes(resp.into_body(), usize::MAX).await.unwrap();
        serde_json::from_slice(&body).unwrap()
    }

    #[tokio::test]
    async fn test_health_endpoint() {
        let app = test_app();
        let req = HttpRequest::builder()
            .uri("/health")
            .body(Body::empty())
            .unwrap();
        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn test_initialize() {
        let app = test_app();
        let resp = rpc_request(&app, r#"{"jsonrpc":"2.0","method":"initialize","params":{},"id":1}"#).await;
        assert!(resp.result.is_some());
        let result = resp.result.unwrap();
        assert_eq!(result["serverInfo"]["name"], "test-sidecar");
    }

    #[tokio::test]
    async fn test_tools_list_returns_4_tools() {
        let app = test_app();
        let resp = rpc_request(&app, r#"{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}"#).await;
        let result = resp.result.unwrap();
        let tools = result["tools"].as_array().unwrap();
        assert_eq!(tools.len(), 8); // 2 yggdrasil + 6 eir
    }

    #[tokio::test]
    async fn test_malformed_json_returns_parse_error() {
        let app = test_app();
        let resp = rpc_request(&app, r#"not json"#).await;
        assert_eq!(resp.error.unwrap().code, CODE_PARSE_ERROR);
    }

    #[tokio::test]
    async fn test_unknown_method_returns_method_not_found() {
        let app = test_app();
        let resp = rpc_request(&app, r#"{"jsonrpc":"2.0","method":"foo/bar","params":{},"id":1}"#).await;
        assert_eq!(resp.error.unwrap().code, CODE_METHOD_NOT_FOUND);
    }

    #[tokio::test]
    async fn test_unknown_tool_returns_method_not_found() {
        let app = test_app();
        let resp = rpc_request(
            &app,
            r#"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"nonexistent"},"id":1}"#,
        ).await;
        assert_eq!(resp.error.unwrap().code, CODE_METHOD_NOT_FOUND);
    }
}
