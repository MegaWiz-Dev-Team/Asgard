//! Loki Security Testing API
//!
//! Provides REST endpoints for Hermodr MCP tool handlers.
//! All endpoints:
//! - Require X-Loki-Test header
//! - Use asgard_platform tenant context
//! - Log to Tyr SIEM
//! - Respect NetworkPolicy restrictions

mod handlers;
mod models;
mod errors;

use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use std::sync::Arc;
use tracing_subscriber::EnvFilter;

pub use handlers::*;
pub use models::*;
pub use errors::*;

// ─── Application State ───────────────────────────────────────────────────

pub struct AppState {
    pub bifrost_url: String,
    pub heimdall_url: String,
    pub mimir_url: String,
    pub syn_url: String,
    pub qdrant_url: String,
    pub mariadb_host: String,
    pub tenant_id: String,
}

// ─── Health Check ────────────────────────────────────────────────────────

async fn health() -> (StatusCode, Json<serde_json::Value>) {
    (
        StatusCode::OK,
        Json(serde_json::json!({
            "status": "healthy",
            "service": "loki-api",
            "version": env!("CARGO_PKG_VERSION"),
        })),
    )
}

// ─── Main Router ─────────────────────────────────────────────────────────

fn build_app(state: Arc<AppState>) -> Router {
    Router::new()
        // Health check
        .route("/health", get(health))

        // API Injection Testing
        .route(
            "/api/v1/loki/test/api-injection",
            post(handlers::api_injection::handle),
        )

        // Prompt Injection Testing
        .route(
            "/api/v1/loki/test/prompt-injection",
            post(handlers::prompt_injection::handle),
        )

        // Data Exfiltration Testing
        .route(
            "/api/v1/loki/test/data-exfiltration",
            post(handlers::data_exfiltration::handle),
        )

        // Tyr Detection Validation
        .route(
            "/api/v1/loki/test/validate-tyr",
            post(handlers::tyr_validation::handle),
        )

        // Target Enumeration
        .route("/api/v1/loki/enumerate", post(handlers::enumerate::handle))

        .with_state(state)
}

// ─── Main ────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let bifrost_url =
        std::env::var("BIFROST_URL").unwrap_or_else(|_| "http://bifrost:8000".into());
    let heimdall_url =
        std::env::var("HEIMDALL_URL").unwrap_or_else(|_| "http://heimdall:8080".into());
    let mimir_url =
        std::env::var("MIMIR_URL").unwrap_or_else(|_| "http://mimir-api:8090".into());
    let syn_url = std::env::var("SYN_URL").unwrap_or_else(|_| "http://syn:8000".into());
    let qdrant_url =
        std::env::var("QDRANT_URL").unwrap_or_else(|_| "http://qdrant:6333".into());
    let mariadb_host = std::env::var("MARIADB_HOST").unwrap_or_else(|_| "mariadb".into());
    let tenant_id = std::env::var("TENANT_ID").unwrap_or_else(|_| "asgard_platform".into());
    let port = std::env::var("PORT").unwrap_or_else(|_| "8000".into());
    let addr = format!("0.0.0.0:{}", port);

    tracing::info!(
        bifrost = %bifrost_url,
        heimdall = %heimdall_url,
        mimir = %mimir_url,
        tenant = %tenant_id,
        addr = %addr,
        "Starting Loki Security Testing API"
    );

    let state = Arc::new(AppState {
        bifrost_url,
        heimdall_url,
        mimir_url,
        syn_url,
        qdrant_url,
        mariadb_host,
        tenant_id,
    });

    let app = build_app(state);

    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .expect("Failed to bind");

    tracing::info!("Loki API listening on {addr}");

    axum::serve(listener, app)
        .await
        .expect("Server error");
}
