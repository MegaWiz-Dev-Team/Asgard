//! Eir MCP tools — OpenEMR FHIR R4 integration via Eir Gateway.

use crate::registry::ToolDefinition;

pub fn tools() -> Vec<ToolDefinition> {
    vec![
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
}
