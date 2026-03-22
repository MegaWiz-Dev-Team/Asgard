//! Path template expansion for dynamic REST endpoints.
//!
//! Replaces `{param}` placeholders in paths with actual argument values
//! and extracts remaining args for the request body.

/// Expand path template with arguments.
/// e.g. `/users/{user_id}/roles` + `{"user_id": "123"}` → `/users/123/roles`
pub fn expand_path(template: &str, args: &serde_json::Map<String, serde_json::Value>) -> String {
    let mut result = template.to_string();
    for (key, value) in args {
        let placeholder = format!("{{{}}}", key);
        let replacement = match value {
            serde_json::Value::String(s) => s.clone(),
            serde_json::Value::Number(n) => n.to_string(),
            other => other.to_string(),
        };
        result = result.replace(&placeholder, &replacement);
    }
    result
}

/// Extract arguments that are NOT consumed by path template.
/// Returns None if all args were consumed (GET with no body needed).
pub fn extract_body_args(
    template: &str,
    args: &serde_json::Map<String, serde_json::Value>,
) -> Option<serde_json::Map<String, serde_json::Value>> {
    let body_args: serde_json::Map<String, serde_json::Value> = args
        .iter()
        .filter(|(key, _)| {
            let placeholder = format!("{{{}}}", key);
            !template.contains(&placeholder)
        })
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();

    if body_args.is_empty() {
        None
    } else {
        Some(body_args)
    }
}

// ─── Tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn make_args(pairs: &[(&str, serde_json::Value)]) -> serde_json::Map<String, serde_json::Value> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.clone())).collect()
    }

    #[test]
    fn test_expand_no_params() {
        let args = make_args(&[]);
        assert_eq!(expand_path("/api/test", &args), "/api/test");
    }

    #[test]
    fn test_expand_single_param() {
        let args = make_args(&[("user_id", json!("u-123"))]);
        assert_eq!(expand_path("/users/{user_id}/roles", &args), "/users/u-123/roles");
    }

    #[test]
    fn test_expand_multiple_params() {
        let args = make_args(&[
            ("org_id", json!("org-1")),
            ("user_id", json!("u-2")),
        ]);
        assert_eq!(
            expand_path("/orgs/{org_id}/users/{user_id}", &args),
            "/orgs/org-1/users/u-2"
        );
    }

    #[test]
    fn test_expand_integer_param() {
        let args = make_args(&[("id", json!(42))]);
        assert_eq!(expand_path("/items/{id}", &args), "/items/42");
    }

    #[test]
    fn test_extract_body_removes_path_params() {
        let args = make_args(&[
            ("user_id", json!("u-1")),
            ("query", json!("hello")),
        ]);
        let body = extract_body_args("/users/{user_id}", &args).unwrap();
        assert_eq!(body.len(), 1);
        assert_eq!(body["query"], json!("hello"));
        assert!(!body.contains_key("user_id"));
    }

    #[test]
    fn test_extract_body_all_consumed() {
        let args = make_args(&[("user_id", json!("u-1"))]);
        assert!(extract_body_args("/users/{user_id}", &args).is_none());
    }

    #[test]
    fn test_extract_body_empty_args() {
        let args = make_args(&[]);
        assert!(extract_body_args("/api/test", &args).is_none());
    }
}
