//! REST proxy — forwards MCP tool calls to upstream services.
//!
//! HTTP 4xx/5xx responses are wrapped as JSON-RPC -32603 errors
//! to prevent LLM hallucination.

use crate::jsonrpc::{RpcError, CODE_INTERNAL_ERROR};

/// REST proxy client for upstream services.
#[derive(Clone)]
pub struct Proxy {
    upstream_url: String,
    client: reqwest::Client,
}

impl Proxy {
    pub fn new(upstream_url: &str) -> Self {
        Self {
            upstream_url: upstream_url.trim_end_matches('/').to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Call the upstream REST endpoint.
    /// On success, returns the response body as serde_json::Value.
    /// On HTTP error, returns an RpcError with code -32603.
    pub async fn call(
        &self,
        method: &str,
        path: &str,
        body: Option<&serde_json::Value>,
        headers: &[(String, String)],
    ) -> Result<serde_json::Value, RpcError> {
        let url = format!("{}{}", self.upstream_url, path);

        let mut req = match method.to_uppercase().as_str() {
            "GET" => self.client.get(&url),
            "POST" => self.client.post(&url),
            "PUT" => self.client.put(&url),
            "DELETE" => self.client.delete(&url),
            "PATCH" => self.client.patch(&url),
            _ => self.client.get(&url),
        };

        // Forward headers
        for (key, value) in headers {
            req = req.header(key, value);
        }

        // Set content type and body
        req = req.header("Content-Type", "application/json");
        if let Some(b) = body {
            req = req.json(b);
        }

        let response = req.send().await.map_err(|e| RpcError {
            code: CODE_INTERNAL_ERROR,
            message: format!("upstream request failed: {}", e),
        })?;

        let status = response.status();
        let resp_body = response.text().await.map_err(|e| RpcError {
            code: CODE_INTERNAL_ERROR,
            message: format!("upstream read error: {}", e),
        })?;

        // Wrap HTTP errors as JSON-RPC -32603
        if status.is_client_error() || status.is_server_error() {
            return Err(RpcError {
                code: CODE_INTERNAL_ERROR,
                message: format!("upstream HTTP {}: {}", status.as_u16(), truncate(&resp_body, 500)),
            });
        }

        // Try to parse as JSON, fallback to raw string
        match serde_json::from_str::<serde_json::Value>(&resp_body) {
            Ok(v) => Ok(v),
            Err(_) => Ok(serde_json::json!({ "raw": resp_body })),
        }
    }
}

fn truncate(s: &str, max: usize) -> &str {
    if s.len() > max { &s[..max] } else { s }
}

// ─── Tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{routing::get, routing::post, Router};

    async fn start_mock(app: Router) -> String {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        format!("http://{}", addr)
    }

    #[tokio::test]
    async fn test_proxy_get_success() {
        let app = Router::new().route("/api/test", get(|| async {
            axum::Json(serde_json::json!({"status": "ok"}))
        }));
        let url = start_mock(app).await;

        let proxy = Proxy::new(&url);
        let result = proxy.call("GET", "/api/test", None, &[]).await.unwrap();
        assert_eq!(result["status"], "ok");
    }

    #[tokio::test]
    async fn test_proxy_post_success() {
        let app = Router::new().route("/api/create", post(|body: axum::Json<serde_json::Value>| async move {
            axum::Json(serde_json::json!({"received": body.0}))
        }));
        let url = start_mock(app).await;

        let proxy = Proxy::new(&url);
        let body = serde_json::json!({"name": "test"});
        let result = proxy.call("POST", "/api/create", Some(&body), &[]).await.unwrap();
        assert_eq!(result["received"]["name"], "test");
    }

    #[tokio::test]
    async fn test_proxy_http_500_wraps_as_internal_error() {
        let app = Router::new().route("/api/fail", get(|| async {
            (axum::http::StatusCode::INTERNAL_SERVER_ERROR, "server broke")
        }));
        let url = start_mock(app).await;

        let proxy = Proxy::new(&url);
        let err = proxy.call("GET", "/api/fail", None, &[]).await.unwrap_err();
        assert_eq!(err.code, CODE_INTERNAL_ERROR);
        assert!(err.message.contains("500"));
    }

    #[tokio::test]
    async fn test_proxy_http_404_wraps_as_internal_error() {
        let app = Router::new().route("/api/exists", get(|| async { "hi" }));
        let url = start_mock(app).await;

        let proxy = Proxy::new(&url);
        let err = proxy.call("GET", "/api/missing", None, &[]).await.unwrap_err();
        assert_eq!(err.code, CODE_INTERNAL_ERROR);
        assert!(err.message.contains("404"));
    }

    #[tokio::test]
    async fn test_proxy_header_forwarding() {
        let app = Router::new().route("/api/check", get(|headers: axum::http::HeaderMap| async move {
            let auth = headers.get("authorization").and_then(|v| v.to_str().ok()).unwrap_or("");
            axum::Json(serde_json::json!({"auth": auth}))
        }));
        let url = start_mock(app).await;

        let proxy = Proxy::new(&url);
        let headers = vec![("Authorization".to_string(), "Bearer my-token".to_string())];
        let result = proxy.call("GET", "/api/check", None, &headers).await.unwrap();
        assert_eq!(result["auth"], "Bearer my-token");
    }
}
