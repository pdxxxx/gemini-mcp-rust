//! Error types for the Gemini MCP server.

use thiserror::Error;

#[derive(Error, Debug)]
pub enum GeminiError {
    #[error("Workspace directory does not exist: {0}")]
    WorkspaceNotFound(String),

    #[error("Failed to find gemini executable in PATH")]
    GeminiNotFound,

    #[error("Failed to spawn gemini process: {0}")]
    ProcessSpawnError(#[from] std::io::Error),

    #[error("Failed to parse JSON output: {0}")]
    JsonParseError(#[from] serde_json::Error),

    #[error("Failed to get SESSION_ID from gemini session")]
    NoSessionId,

    #[error("Failed to retrieve agent_messages from gemini session: {0}")]
    NoAgentMessages(String),

    #[error("Process timeout")]
    ProcessTimeout,

    #[error("{0}")]
    Other(String),
}

pub type Result<T> = std::result::Result<T, GeminiError>;
