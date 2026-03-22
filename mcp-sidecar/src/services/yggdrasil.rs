//! Yggdrasil MCP tools — Zitadel IAM integration.

use crate::registry::ToolDefinition;

pub fn tools() -> Vec<ToolDefinition> {
    vec![
        ToolDefinition {
            name: "validate_token".into(),
            description: "Validate a JWT token via Zitadel introspection. Returns token claims including active status, subject, and organization.".into(),
            method: "POST".into(),
            path: "/oauth/v2/introspect".into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "token": {
                        "type": "string",
                        "description": "JWT token to validate"
                    }
                },
                "required": ["token"]
            }),
        },
        ToolDefinition {
            name: "get_user_roles".into(),
            description: "Get all roles/grants for a user within projects. Returns role keys, project IDs, and organization info.".into(),
            method: "POST".into(),
            path: "/management/v1/users/{user_id}/grants/_search".into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "user_id": {
                        "type": "string",
                        "description": "Zitadel user ID"
                    }
                },
                "required": ["user_id"]
            }),
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tool_count() {
        assert_eq!(tools().len(), 2);
    }

    #[test]
    fn test_validate_token_definition() {
        let t = tools().into_iter().find(|t| t.name == "validate_token").unwrap();
        assert_eq!(t.method, "POST");
        assert_eq!(t.path, "/oauth/v2/introspect");
        assert!(!t.description.is_empty());
    }

    #[test]
    fn test_get_user_roles_definition() {
        let t = tools().into_iter().find(|t| t.name == "get_user_roles").unwrap();
        assert_eq!(t.method, "POST");
        assert!(t.path.contains("{user_id}"));
    }
}
