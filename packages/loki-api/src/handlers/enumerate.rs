//! Target Enumeration Handler

use axum::{extract::State, http::StatusCode, Json};
use chrono::Utc;
use std::sync::Arc;

use crate::{
    models::{EnumerationRequest, EnumerationResult, EndpointInfo},
    AppState, Result,
};

pub async fn handle(
    State(state): State<Arc<AppState>>,
    Json(req): Json<EnumerationRequest>,
) -> Result<(StatusCode, Json<EnumerationResult>)> {
    tracing::info!(
        target_service = %req.target_service,
        depth = %req.depth,
        "Enumerating target service"
    );

    let endpoints = match req.target_service.as_str() {
        "bifrost" => bifrost_endpoints(&req),
        "heimdall" => heimdall_endpoints(&req),
        "mimir" => mimir_endpoints(&req),
        "syn" => syn_endpoints(&req),
        "all" => {
            let mut all = bifrost_endpoints(&req);
            all.extend(heimdall_endpoints(&req));
            all.extend(mimir_endpoints(&req));
            all.extend(syn_endpoints(&req));
            all
        }
        _ => vec![],
    };

    let result = EnumerationResult {
        service: req.target_service.clone(),
        total_endpoints: endpoints.len(),
        endpoints,
        timestamp: Utc::now(),
    };

    tracing::info!(
        service = %req.target_service,
        endpoint_count = result.total_endpoints,
        "Enumeration completed"
    );

    Ok((StatusCode::OK, Json(result)))
}

fn bifrost_endpoints(req: &crate::models::EnumerationRequest) -> Vec<EndpointInfo> {
    vec![
        EndpointInfo {
            path: "/api/v1/knowledge/search".into(),
            method: "POST".into(),
            description: "Search knowledge base (RAG retrieval)".into(),
            auth_required: true,
            auth_methods: vec!["JWT Bearer".into()],
            example_request: if req.include_examples {
                Some(r#"{"query": "What is CPAP?"}"#.into())
            } else {
                None
            },
            example_response: None,
        },
        EndpointInfo {
            path: "/api/v1/agents/query".into(),
            method: "POST".into(),
            description: "Query specific agent".into(),
            auth_required: true,
            auth_methods: vec!["JWT Bearer".into()],
            example_request: None,
            example_response: None,
        },
        EndpointInfo {
            path: "/api/v1/user/profile".into(),
            method: "GET".into(),
            description: "Get current user profile".into(),
            auth_required: true,
            auth_methods: vec!["JWT Bearer".into()],
            example_request: None,
            example_response: None,
        },
    ]
}

fn heimdall_endpoints(req: &crate::models::EnumerationRequest) -> Vec<EndpointInfo> {
    vec![
        EndpointInfo {
            path: "/api/v1/chat".into(),
            method: "POST".into(),
            description: "Send message to LLM gateway".into(),
            auth_required: true,
            auth_methods: vec!["JWT Bearer".into(), "X-API-Key".into()],
            example_request: if req.include_examples {
                Some(r#"{"messages": [{"role":"user","content":"Hello"}]}"#.into())
            } else {
                None
            },
            example_response: None,
        },
        EndpointInfo {
            path: "/api/v1/models".into(),
            method: "GET".into(),
            description: "List available LLM models".into(),
            auth_required: false,
            auth_methods: vec![],
            example_request: None,
            example_response: None,
        },
    ]
}

fn mimir_endpoints(req: &crate::models::EnumerationRequest) -> Vec<EndpointInfo> {
    vec![
        EndpointInfo {
            path: "/api/v1/knowledge/list".into(),
            method: "GET".into(),
            description: "List knowledge bases".into(),
            auth_required: true,
            auth_methods: vec!["JWT Bearer".into()],
            example_request: None,
            example_response: None,
        },
        EndpointInfo {
            path: "/api/v1/evaluations".into(),
            method: "GET".into(),
            description: "List evaluation runs".into(),
            auth_required: true,
            auth_methods: vec!["JWT Bearer".into()],
            example_request: None,
            example_response: None,
        },
    ]
}

fn syn_endpoints(req: &crate::models::EnumerationRequest) -> Vec<EndpointInfo> {
    vec![
        EndpointInfo {
            path: "/api/v1/ocr/extract".into(),
            method: "POST".into(),
            description: "Extract text from image via OCR".into(),
            auth_required: true,
            auth_methods: vec!["JWT Bearer".into()],
            example_request: if req.include_examples {
                Some(r#"{"image_base64":"base64content...","filename":"doc.pdf"}"#.into())
            } else {
                None
            },
            example_response: None,
        },
    ]
}
