//! API Injection Test Handler

use axum::{extract::State, http::StatusCode, Json};
use chrono::Utc;
use uuid::Uuid;
use std::sync::Arc;
use std::time::Instant;

use crate::{
    models::{ApiInjectionRequest, ApiInjectionResult, Detection, TestStatus},
    AppState, LokiError, Result,
};

/// Handle API injection test requests
pub async fn handle(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ApiInjectionRequest>,
) -> Result<(StatusCode, Json<ApiInjectionResult>)> {
    let start = Instant::now();
    let test_id = Uuid::new_v4().to_string();

    tracing::info!(
        test_id = %test_id,
        endpoint = %req.target_endpoint,
        test_type = %req.test_type,
        "Starting API injection test"
    );

    // Validate request
    if req.target_endpoint.is_empty() {
        return Err(LokiError::InvalidRequest("target_endpoint required".into()));
    }

    // Build payloads based on test type
    let payloads = match req.test_type.as_str() {
        "sql_injection" => vec![
            r#"" OR "1"="1"#,
            r#""; DROP TABLE users; --"#,
            r#"" UNION SELECT null, version() --"#,
        ],
        "parameter_tampering" => vec![
            r#"{"tenant_id": "asgard_medical"}"#,
            r#"{"admin": true}"#,
        ],
        "jwt_manipulation" => vec![
            "eyJhbGciOiJub25lIn0.payload.signature",
            "eyJhbGciOiJIUzI1NiJ9.payload.signature",
        ],
        "authorization_bypass" => vec![
            r#"{"skip_auth": true}"#,
            r#"{"role": "admin"}"#,
        ],
        "all" => {
            let mut all = vec![];
            all.extend(vec![r#"" OR "1"="1"#, r#""; DROP TABLE users; --"#]);
            all.extend(vec![r#"{"tenant_id": "asgard_medical"}"#]);
            all.extend(vec!["eyJhbGciOiJub25lIn0.payload.signature"]);
            all
        }
        _ => return Err(LokiError::InvalidRequest("Invalid test_type".into())),
    };

    let mut detections = Vec::new();

    // Execute each payload
    for (idx, payload) in payloads.iter().enumerate() {
        tracing::debug!(
            test_id = %test_id,
            payload_idx = idx,
            payload = %payload,
            "Testing payload"
        );

        // Try to send to target endpoint
        match test_endpoint(&state, &req.target_endpoint, payload, &test_id).await {
            Ok(status) => {
                // Any 200-299 status might indicate vulnerability
                if status >= 400 {
                    detections.push(Detection {
                        pattern: format!("SQL injection attempt rejected at {}", req.target_endpoint),
                        severity: "INFO".into(),
                        message: format!("Payload blocked: status {}", status),
                    });
                }
            }
            Err(e) => {
                // Connection error = blocked by firewall/policy
                tracing::debug!(
                    test_id = %test_id,
                    error = %e,
                    "Payload blocked by network policy or service"
                );
                detections.push(Detection {
                    pattern: "Network policy enforced".into(),
                    severity: "INFO".into(),
                    message: format!("Payload blocked: {}", e),
                });
            }
        }
    }

    let duration = start.elapsed();

    let result = ApiInjectionResult {
        test_id: test_id.clone(),
        target: req.target_endpoint.clone(),
        test_type: req.test_type.clone(),
        timestamp: Utc::now(),
        payloads_sent: payloads.len(),
        detections: detections.clone(),
        status: if detections.is_empty() {
            TestStatus::Passed
        } else {
            TestStatus::Partial
        },
        duration_ms: duration.as_millis() as u64,
    };

    tracing::info!(
        test_id = %test_id,
        detections = result.detections.len(),
        duration_ms = result.duration_ms,
        "API injection test completed"
    );

    Ok((StatusCode::OK, Json(result)))
}

/// Test endpoint with a specific payload
async fn test_endpoint(
    state: &AppState,
    endpoint: &str,
    payload: &str,
    test_id: &str,
) -> Result<u16> {
    let url = format!("{}{}", state.bifrost_url, endpoint);

    let client = reqwest::Client::new();
    let response = client
        .post(&url)
        .header("X-Loki-Test", "true")
        .header("X-Tenant-Id", &state.tenant_id)
        .header("Content-Type", "application/json")
        .body(payload.to_string())
        .send()
        .await
        .map_err(|e| LokiError::TargetUnreachable(e.to_string()))?;

    Ok(response.status().as_u16())
}
