//! MCP Server implementation for Gemini.

use crate::gemini::{execute_gemini, GeminiResult};
use rmcp::handler::server::router::tool::ToolRouter;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::*;
use rmcp::schemars::{self, JsonSchema};
use rmcp::{tool, tool_handler, tool_router, ErrorData as McpError, ServiceExt};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Input parameters for the gemini tool.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[schemars(description = "Parameters for invoking the Gemini CLI")]
pub struct GeminiToolInput {
    /// Instruction for the task to send to gemini.
    #[schemars(description = "The prompt/instruction to send to Gemini")]
    #[serde(rename = "PROMPT")]
    pub prompt: String,

    /// Set the workspace root for gemini before executing the task.
    #[schemars(description = "Working directory for Gemini to execute in")]
    pub cd: PathBuf,

    /// Run in sandbox mode. Defaults to `false`.
    #[schemars(description = "Run in sandbox mode (default: false)")]
    #[serde(default)]
    pub sandbox: bool,

    /// Resume the specified session of the gemini.
    #[schemars(description = "Session ID to resume a previous conversation")]
    #[serde(rename = "SESSION_ID", default)]
    pub session_id: String,

    /// Return all messages from the gemini session.
    #[schemars(description = "Return all messages including reasoning and tool calls (default: false)")]
    #[serde(default)]
    pub return_all_messages: bool,

    /// The model to use for the gemini session.
    #[schemars(description = "Model to use (only specify if user explicitly requests)")]
    #[serde(default)]
    pub model: String,
}

/// The Gemini MCP Server.
#[derive(Clone)]
pub struct GeminiServer {
    tool_router: ToolRouter<Self>,
}

#[tool_router]
impl GeminiServer {
    pub fn new() -> Self {
        Self {
            tool_router: Self::tool_router(),
        }
    }

    #[tool(
        name = "gemini",
        description = "Invokes the Gemini CLI to execute AI-driven tasks, returning structured JSON events and a session identifier for conversation continuity.

**Return structure:**
- `success`: boolean indicating execution status
- `SESSION_ID`: unique identifier for resuming this conversation in future calls
- `agent_messages`: concatenated assistant response text
- `all_messages`: (optional) complete array of JSON events when `return_all_messages=True`
- `error`: error description when `success=False`

**Best practices:**
- Always capture and reuse `SESSION_ID` for multi-turn interactions
- Enable `sandbox` mode when file modifications should be isolated
- Use `return_all_messages` only when detailed execution traces are necessary (increases payload size)
- Only pass `model` when the user has explicitly requested a specific model"
    )]
    async fn gemini(
        &self,
        Parameters(input): Parameters<GeminiToolInput>,
    ) -> Result<CallToolResult, McpError> {
        let session_id = if input.session_id.is_empty() {
            None
        } else {
            Some(input.session_id.as_str())
        };

        let model = if input.model.is_empty() {
            None
        } else {
            Some(input.model.as_str())
        };

        let result = execute_gemini(
            &input.prompt,
            &input.cd,
            input.sandbox,
            session_id,
            model,
            input.return_all_messages,
        )
        .await;

        let json_str = match result {
            Ok(gemini_result) => serde_json::to_string(&gemini_result).unwrap_or_else(|e| {
                // Use serde_json to ensure proper escaping
                serde_json::to_string(&GeminiResult {
                    success: false,
                    session_id: None,
                    agent_messages: None,
                    all_messages: None,
                    error: Some(format!("JSON serialization error: {}", e)),
                })
                .unwrap_or_else(|_| r#"{"success":false,"error":"Unknown error"}"#.to_string())
            }),
            Err(e) => {
                let error_result = GeminiResult {
                    success: false,
                    session_id: None,
                    agent_messages: None,
                    all_messages: None,
                    error: Some(e.to_string()),
                };
                serde_json::to_string(&error_result)
                    .unwrap_or_else(|_| r#"{"success":false,"error":"Unknown error"}"#.to_string())
            }
        };

        Ok(CallToolResult::success(vec![Content::text(json_str)]))
    }
}

impl Default for GeminiServer {
    fn default() -> Self {
        Self::new()
    }
}

#[tool_handler]
impl rmcp::ServerHandler for GeminiServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            instructions: Some(
                "Gemini MCP Server - Wraps Gemini CLI as a standard MCP protocol interface".into(),
            ),
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            ..Default::default()
        }
    }
}

/// Create and run the MCP server over stdio transport.
pub async fn run_server() -> anyhow::Result<()> {
    tracing::info!("Starting Gemini MCP Server...");

    let server = GeminiServer::new();
    let service = server.serve(rmcp::transport::stdio()).await?;

    tracing::info!("Gemini MCP Server is running");

    service.waiting().await?;

    tracing::info!("Gemini MCP Server shutting down");
    Ok(())
}
