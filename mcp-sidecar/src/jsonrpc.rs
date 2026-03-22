//! JSON-RPC 2.0 types and handler for MCP protocol.
//!
//! Implements request/response types, standard error codes,
//! and the MCP methods: `initialize`, `tools/list`, `tools/call`.

use serde::{Deserialize, Serialize};

// ─── Error Codes (JSON-RPC 2.0) ─────────────────────────────────────────

pub const CODE_PARSE_ERROR: i32 = -32700;
pub const CODE_INVALID_REQUEST: i32 = -32600;
pub const CODE_METHOD_NOT_FOUND: i32 = -32601;
pub const CODE_INVALID_PARAMS: i32 = -32602;
pub const CODE_INTERNAL_ERROR: i32 = -32603;

// ─── Types ───────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct Request {
    pub jsonrpc: String,
    pub method: String,
    #[serde(default)]
    pub params: serde_json::Value,
    #[serde(default)]
    pub id: serde_json::Value,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Response {
    pub jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
    pub id: serde_json::Value,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
}

/// Params for `tools/call`
#[derive(Debug, Deserialize)]
pub struct ToolCallParams {
    pub name: String,
    #[serde(default)]
    pub arguments: serde_json::Map<String, serde_json::Value>,
}

// ─── Constructors ────────────────────────────────────────────────────────

impl Response {
    pub fn success(id: serde_json::Value, result: serde_json::Value) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            result: Some(result),
            error: None,
            id,
        }
    }

    pub fn error(id: serde_json::Value, code: i32, message: impl Into<String>) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            result: None,
            error: Some(RpcError {
                code,
                message: message.into(),
            }),
            id,
        }
    }
}

// ─── Tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_code_constants() {
        assert_eq!(CODE_PARSE_ERROR, -32700);
        assert_eq!(CODE_INVALID_REQUEST, -32600);
        assert_eq!(CODE_METHOD_NOT_FOUND, -32601);
        assert_eq!(CODE_INVALID_PARAMS, -32602);
        assert_eq!(CODE_INTERNAL_ERROR, -32603);
    }

    #[test]
    fn test_response_success_serialization() {
        let resp = Response::success(
            serde_json::json!(1),
            serde_json::json!({"tools": []}),
        );
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["jsonrpc"], "2.0");
        assert!(json.get("error").is_none());
        assert_eq!(json["result"]["tools"], serde_json::json!([]));
    }

    #[test]
    fn test_response_error_serialization() {
        let resp = Response::error(
            serde_json::json!(1),
            CODE_METHOD_NOT_FOUND,
            "Method not found",
        );
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["error"]["code"], -32601);
        assert_eq!(json["error"]["message"], "Method not found");
        assert!(json.get("result").is_none());
    }

    #[test]
    fn test_request_deserialization() {
        let raw = r#"{"jsonrpc":"2.0","method":"tools/list","params":{},"id":1}"#;
        let req: Request = serde_json::from_str(raw).unwrap();
        assert_eq!(req.method, "tools/list");
        assert_eq!(req.jsonrpc, "2.0");
    }

    #[test]
    fn test_tool_call_params_deserialization() {
        let raw = r#"{"name":"validate_token","arguments":{"token":"abc123"}}"#;
        let params: ToolCallParams = serde_json::from_str(raw).unwrap();
        assert_eq!(params.name, "validate_token");
        assert_eq!(params.arguments["token"], "abc123");
    }
}
