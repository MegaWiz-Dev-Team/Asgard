//! Tool registry — manages MCP tool definitions.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::RwLock;

/// A tool definition mapping an MCP tool name to a REST endpoint.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolDefinition {
    pub name: String,
    pub description: String,
    pub method: String,
    pub path: String,
    #[serde(rename = "inputSchema")]
    pub input_schema: serde_json::Value,
}

/// Thread-safe registry of tool definitions.
pub struct ToolRegistry {
    tools: RwLock<HashMap<String, ToolDefinition>>,
}

impl ToolRegistry {
    pub fn new() -> Self {
        Self {
            tools: RwLock::new(HashMap::new()),
        }
    }

    pub fn register(&self, tool: ToolDefinition) {
        self.tools.write().unwrap().insert(tool.name.clone(), tool);
    }

    pub fn get(&self, name: &str) -> Option<ToolDefinition> {
        self.tools.read().unwrap().get(name).cloned()
    }

    pub fn list(&self) -> Vec<ToolDefinition> {
        self.tools.read().unwrap().values().cloned().collect()
    }

    pub fn count(&self) -> usize {
        self.tools.read().unwrap().len()
    }

    /// Format tools for MCP `tools/list` response.
    pub fn mcp_tool_list(&self) -> Vec<serde_json::Value> {
        self.list()
            .into_iter()
            .map(|t| {
                serde_json::json!({
                    "name": t.name,
                    "description": t.description,
                    "inputSchema": t.input_schema,
                })
            })
            .collect()
    }
}

// ─── Tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_tool() -> ToolDefinition {
        ToolDefinition {
            name: "test_tool".into(),
            description: "A test tool".into(),
            method: "POST".into(),
            path: "/api/test".into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": { "query": { "type": "string" } },
                "required": ["query"]
            }),
        }
    }

    #[test]
    fn test_register_and_get() {
        let reg = ToolRegistry::new();
        reg.register(sample_tool());
        let got = reg.get("test_tool").unwrap();
        assert_eq!(got.name, "test_tool");
        assert_eq!(got.method, "POST");
    }

    #[test]
    fn test_get_unknown_returns_none() {
        let reg = ToolRegistry::new();
        assert!(reg.get("nonexistent").is_none());
    }

    #[test]
    fn test_list_and_count() {
        let reg = ToolRegistry::new();
        assert_eq!(reg.count(), 0);
        reg.register(sample_tool());
        assert_eq!(reg.count(), 1);
        assert_eq!(reg.list().len(), 1);
    }

    #[test]
    fn test_mcp_tool_list_format() {
        let reg = ToolRegistry::new();
        reg.register(sample_tool());
        let list = reg.mcp_tool_list();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0]["name"], "test_tool");
        assert!(list[0].get("inputSchema").is_some());
        // Should NOT include method/path (internal only)
        assert!(list[0].get("method").is_none());
    }
}
