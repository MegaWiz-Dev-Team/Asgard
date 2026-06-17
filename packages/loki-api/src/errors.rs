//! Error handling for Loki API

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum LokiError {
    #[error("Invalid request: {0}")]
    InvalidRequest(String),

    #[error("Target service unreachable: {0}")]
    TargetUnreachable(String),

    #[error("Request timeout")]
    Timeout,

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Test execution failed: {0}")]
    TestFailed(String),

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),
}

impl IntoResponse for LokiError {
    fn into_response(self) -> Response {
        let error_msg = self.to_string();
        let (status, message) = match &self {
            LokiError::InvalidRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            LokiError::TargetUnreachable(msg) => (StatusCode::BAD_GATEWAY, msg.clone()),
            LokiError::Timeout => (StatusCode::GATEWAY_TIMEOUT, "Request timeout".to_string()),
            LokiError::Unauthorized(msg) => (StatusCode::UNAUTHORIZED, msg.clone()),
            LokiError::TestFailed(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            LokiError::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
            LokiError::ConfigError(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.clone()),
        };

        (
            status,
            Json(json!({
                "error": error_msg,
                "message": message,
                "status": status.as_u16(),
            })),
        )
            .into_response()
    }
}

pub type Result<T> = std::result::Result<T, LokiError>;
