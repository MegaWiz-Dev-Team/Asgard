//! Data models for Loki security testing

use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

// ─── API Injection ───────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct ApiInjectionRequest {
    pub target_endpoint: String,
    pub test_type: String,
    #[serde(default)]
    pub verbose: bool,
    #[serde(default = "default_timeout")]
    pub timeout_seconds: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ApiInjectionResult {
    pub test_id: String,
    pub target: String,
    pub test_type: String,
    pub timestamp: DateTime<Utc>,
    pub payloads_sent: usize,
    pub detections: Vec<Detection>,
    pub status: TestStatus,
    pub duration_ms: u64,
}

// ─── Prompt Injection ────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct PromptInjectionRequest {
    pub injection_type: String,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub payload: Option<String>,
    #[serde(default = "default_true")]
    pub check_skuggi: bool,
    #[serde(default)]
    pub verbose: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PromptInjectionResult {
    pub test_id: String,
    pub injection_type: String,
    pub timestamp: DateTime<Utc>,
    pub model_tested: String,
    pub payload_sent: String,
    pub llm_response: String,
    pub skuggi_detection: Option<SkuggiDetection>,
    pub risk_score: f32,
    pub status: TestStatus,
    pub duration_ms: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SkuggiDetection {
    pub detected: bool,
    pub pii_categories: Vec<String>,
    pub confidence: f32,
    pub action: String,
}

// ─── Data Exfiltration ──────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct DataExfiltrationRequest {
    pub target: String,
    pub exfiltration_method: String,
    #[serde(default)]
    pub sample_doc: Option<String>,
    #[serde(default)]
    pub verbose: bool,
    #[serde(default = "default_true")]
    pub expect_failure: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DataExfiltrationResult {
    pub test_id: String,
    pub target: String,
    pub method: String,
    pub timestamp: DateTime<Utc>,
    pub access_attempts: usize,
    pub successful_accesses: usize,
    pub blocked_accesses: usize,
    pub findings: Vec<ExfiltrationFinding>,
    pub status: TestStatus,
    pub duration_ms: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ExfiltrationFinding {
    pub category: String,
    pub description: String,
    pub severity: String,
    pub remediation: String,
}

// ─── Tyr Detection Validation ────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct TyrValidationRequest {
    pub check_type: String,
    #[serde(default = "default_lookback")]
    pub lookback_minutes: u32,
    #[serde(default)]
    pub expected_detections: Vec<String>,
    #[serde(default = "default_true")]
    pub verify_suppression: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TyrValidationResult {
    pub test_id: String,
    pub check_type: String,
    pub timestamp: DateTime<Utc>,
    pub pod_ip: String,
    pub pod_name: String,
    pub lookback_period: String,
    pub detections_found: Vec<TyrDetection>,
    pub alerts_suppressed: usize,
    pub compliance_status: String,
    pub findings: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TyrDetection {
    pub rule: String,
    pub signature: String,
    pub timestamp: DateTime<Utc>,
    pub severity: String,
    pub data: String,
}

// ─── Target Enumeration ──────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct EnumerationRequest {
    pub target_service: String,
    #[serde(default)]
    pub depth: String,
    #[serde(default = "default_true")]
    pub include_auth_methods: bool,
    #[serde(default)]
    pub include_examples: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EnumerationResult {
    pub service: String,
    pub endpoints: Vec<EndpointInfo>,
    pub total_endpoints: usize,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EndpointInfo {
    pub path: String,
    pub method: String,
    pub description: String,
    pub auth_required: bool,
    pub auth_methods: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub example_request: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub example_response: Option<String>,
}

// ─── Common Types ────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize, Clone, Copy)]
pub enum TestStatus {
    #[serde(rename = "passed")]
    Passed,
    #[serde(rename = "failed")]
    Failed,
    #[serde(rename = "partial")]
    Partial,
    #[serde(rename = "error")]
    Error,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Detection {
    pub pattern: String,
    pub severity: String,
    pub message: String,
}

// ─── Helper Functions ────────────────────────────────────────────────────

fn default_timeout() -> u32 {
    30
}

fn default_true() -> bool {
    true
}

fn default_lookback() -> u32 {
    60
}
