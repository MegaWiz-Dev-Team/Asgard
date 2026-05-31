//! Handler implementations for Loki security testing tools

pub mod api_injection;
pub mod prompt_injection;
pub mod data_exfiltration;
pub mod tyr_validation;
pub mod enumerate;

// Re-export for convenience
pub use api_injection::handle as handle_api_injection;
pub use prompt_injection::handle as handle_prompt_injection;
pub use data_exfiltration::handle as handle_data_exfiltration;
pub use tyr_validation::handle as handle_tyr_validation;
pub use enumerate::handle as handle_enumerate;
