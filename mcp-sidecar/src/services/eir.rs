//! Eir MCP tools — OpenEMR FHIR R4 + custom REST integration via Eir Gateway.
//!
//! Sprint 6: Added search_patients, get_patient_summary, create_encounter, get_sleep_reports.

use crate::registry::ToolDefinition;

pub fn tools() -> Vec<ToolDefinition> {
    vec![
        // ── Sprint 33 FHIR tools ──
        ToolDefinition {
            name: "get_patient_medical_history".into(),
            description: "Retrieve comprehensive medical history for a patient via FHIR R4 $everything. Returns a Bundle with conditions, medications, observations, procedures, allergies, immunizations, and encounters.".into(),
            method: "GET".into(),
            path: "/fhir/r4/Patient/{patient_id}/$everything".into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "patient_id": {
                        "type": "string",
                        "description": "FHIR Patient resource ID"
                    }
                },
                "required": ["patient_id"]
            }),
        },
        ToolDefinition {
            name: "book_appointment".into(),
            description: "Book a medical appointment in OpenEMR via FHIR R4. Creates an Appointment resource with patient, practitioner, and time slot.".into(),
            method: "POST".into(),
            path: "/fhir/r4/Appointment".into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "patient_id": {
                        "type": "string",
                        "description": "FHIR Patient resource ID"
                    },
                    "practitioner_id": {
                        "type": "string",
                        "description": "FHIR Practitioner resource ID"
                    },
                    "start": {
                        "type": "string",
                        "description": "Appointment start (ISO 8601)"
                    },
                    "end": {
                        "type": "string",
                        "description": "Appointment end (ISO 8601)"
                    },
                    "description": {
                        "type": "string",
                        "description": "Reason for appointment"
                    }
                },
                "required": ["patient_id", "practitioner_id", "start", "end"]
            }),
        },

        // ── Sprint 6 CPAP/Sleep tools ──
        ToolDefinition {
            name: "search_patients".into(),
            description: "Search patients by name, DOB, or patient ID. Returns matching patient records with demographics (PID, name, DOB, sex, phone).".into(),
            method: "GET".into(),
            path: "/api/patients?query={query}".into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query: patient name (Thai or English), DOB (YYYY-MM-DD), or PID number"
                    }
                },
                "required": ["query"]
            }),
        },
        ToolDefinition {
            name: "get_patient_summary".into(),
            description: "Get comprehensive patient summary including demographics, CPAP prescription details, and latest sleep therapy data with triage status (green/yellow/red).".into(),
            method: "GET".into(),
            path: "/api/patients/{patient_id}/summary".into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "patient_id": {
                        "type": "integer",
                        "description": "OpenEMR patient PID"
                    }
                },
                "required": ["patient_id"]
            }),
        },
        ToolDefinition {
            name: "create_encounter".into(),
            description: "Create a new clinical encounter for a patient. Use for scheduling follow-ups or recording visits. Returns the new encounter ID.".into(),
            method: "POST".into(),
            path: "/api/patients/{patient_id}/encounters".into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "patient_id": {
                        "type": "integer",
                        "description": "OpenEMR patient PID"
                    },
                    "type": {
                        "type": "string",
                        "description": "Encounter type: follow_up, urgent, initial, data_review"
                    }
                },
                "required": ["patient_id", "type"]
            }),
        },
        ToolDefinition {
            name: "get_sleep_reports".into(),
            description: "Get sleep therapy reports for a patient over a specified period. Shows usage hours, AHI, leak rates, pressure data, and triage status (green/yellow/red).".into(),
            method: "GET".into(),
            path: "/api/patients/{patient_id}/sleep-reports?days={days}".into(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "patient_id": {
                        "type": "integer",
                        "description": "OpenEMR patient PID"
                    },
                    "days": {
                        "type": "integer",
                        "description": "Number of days to look back (default: 30)"
                    }
                },
                "required": ["patient_id"]
            }),
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tool_count() {
        assert_eq!(tools().len(), 6);
    }

    #[test]
    fn test_get_patient_medical_history() {
        let t = tools().into_iter().find(|t| t.name == "get_patient_medical_history").unwrap();
        assert_eq!(t.method, "GET");
        assert!(t.path.contains("{patient_id}"));
        assert!(t.path.contains("$everything"));
    }

    #[test]
    fn test_book_appointment() {
        let t = tools().into_iter().find(|t| t.name == "book_appointment").unwrap();
        assert_eq!(t.method, "POST");
        assert_eq!(t.path, "/fhir/r4/Appointment");
        let required = t.input_schema["required"].as_array().unwrap();
        assert_eq!(required.len(), 4);
    }

    #[test]
    fn test_search_patients() {
        let t = tools().into_iter().find(|t| t.name == "search_patients").unwrap();
        assert_eq!(t.method, "GET");
        assert!(t.path.contains("query={query}"));
    }

    #[test]
    fn test_get_patient_summary() {
        let t = tools().into_iter().find(|t| t.name == "get_patient_summary").unwrap();
        assert_eq!(t.method, "GET");
        assert!(t.path.contains("{patient_id}"));
        assert!(t.path.contains("summary"));
    }

    #[test]
    fn test_create_encounter() {
        let t = tools().into_iter().find(|t| t.name == "create_encounter").unwrap();
        assert_eq!(t.method, "POST");
        assert!(t.path.contains("encounters"));
    }

    #[test]
    fn test_get_sleep_reports() {
        let t = tools().into_iter().find(|t| t.name == "get_sleep_reports").unwrap();
        assert_eq!(t.method, "GET");
        assert!(t.path.contains("sleep-reports"));
    }
}
