//! Gemini CLI execution module.

use crate::error::{GeminiError, Result};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::path::Path;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::time::{timeout, Duration};

const GRACEFUL_SHUTDOWN_DELAY_MS: u64 = 300;
const PROCESS_TIMEOUT_SECS: u64 = 300;
const WAIT_TIMEOUT_SECS: u64 = 5;

/// A single JSON event from the Gemini CLI output stream.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeminiEvent {
    #[serde(rename = "type")]
    pub event_type: Option<String>,
    pub role: Option<String>,
    pub content: Option<String>,
    pub session_id: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

/// Result of a Gemini CLI execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeminiResult {
    pub success: bool,
    #[serde(rename = "SESSION_ID", skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent_messages: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub all_messages: Option<Vec<serde_json::Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Escape special characters for Windows command line.
#[cfg(windows)]
fn windows_escape(prompt: &str) -> String {
    prompt
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
        .replace('\x08', "\\b")
        .replace('\x0C', "\\f")
        .replace('\'', "\\'")
}

#[cfg(not(windows))]
fn windows_escape(prompt: &str) -> String {
    prompt.to_string()
}

/// Find the gemini executable path.
fn find_gemini_executable() -> Result<String> {
    which::which("gemini")
        .map(|p| p.to_string_lossy().to_string())
        .map_err(|_| GeminiError::GeminiNotFound)
}

/// Check if the event indicates turn completion.
fn is_turn_completed(event: &GeminiEvent) -> bool {
    event.event_type.as_deref() == Some("turn.completed")
}

/// Deprecated prompt warning to filter out.
const DEPRECATED_PROMPT_WARNING: &str = "The --prompt (-p) flag has been deprecated";

/// Execute the Gemini CLI and stream its output.
pub async fn execute_gemini(
    prompt: &str,
    cwd: &Path,
    sandbox: bool,
    session_id: Option<&str>,
    model: Option<&str>,
    return_all_messages: bool,
) -> Result<GeminiResult> {
    // Validate workspace directory
    if !cwd.exists() {
        return Err(GeminiError::WorkspaceNotFound(
            cwd.to_string_lossy().to_string(),
        ));
    }

    // Find gemini executable
    let gemini_path = find_gemini_executable()?;

    // Escape prompt on Windows
    #[cfg(windows)]
    let prompt = windows_escape(prompt);
    #[cfg(not(windows))]
    let prompt = prompt.to_string();

    // Build command arguments
    let mut args = vec![
        "--prompt".to_string(),
        prompt,
        "-o".to_string(),
        "stream-json".to_string(),
    ];

    if sandbox {
        args.push("--sandbox".to_string());
    }

    if let Some(m) = model {
        if !m.is_empty() {
            args.push("--model".to_string());
            args.push(m.to_string());
        }
    }

    if let Some(sid) = session_id {
        if !sid.is_empty() {
            args.push("--resume".to_string());
            args.push(sid.to_string());
        }
    }

    // Spawn the process - use Stdio::null() for stderr to avoid deadlock
    // when stderr buffer fills up
    let mut child = Command::new(&gemini_path)
        .args(&args)
        .current_dir(cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null()) // Avoid deadlock by not piping stderr
        .spawn()?;

    let stdout = child.stdout.take().expect("Failed to capture stdout");
    let mut reader = BufReader::new(stdout).lines();

    // Only collect all_messages when needed to save memory
    let mut all_messages: Option<Vec<serde_json::Value>> = if return_all_messages {
        Some(Vec::new())
    } else {
        None
    };
    let mut agent_messages = String::new();
    let mut session_id_result: Option<String> = None;
    let mut error_messages: VecDeque<String> = VecDeque::new();

    // Read output with timeout
    let read_result = timeout(Duration::from_secs(PROCESS_TIMEOUT_SECS), async {
        loop {
            match reader.next_line().await {
                Ok(Some(line)) => {
                    let line = line.trim().to_string();
                    if line.is_empty() {
                        continue;
                    }

                    // Try to parse as JSON
                    match serde_json::from_str::<GeminiEvent>(&line) {
                        Ok(event) => {
                            // Store raw value if needed
                            if let Some(ref mut messages) = all_messages {
                                if let Ok(value) = serde_json::from_str::<serde_json::Value>(&line)
                                {
                                    messages.push(value);
                                }
                            }

                            // Extract session_id
                            if event.session_id.is_some() {
                                session_id_result = event.session_id.clone();
                            }

                            // Extract assistant messages
                            if event.event_type.as_deref() == Some("message")
                                && event.role.as_deref() == Some("assistant")
                            {
                                if let Some(content) = &event.content {
                                    if !content.contains(DEPRECATED_PROMPT_WARNING) {
                                        agent_messages.push_str(content);
                                    }
                                }
                            }

                            // Check for turn completion
                            if is_turn_completed(&event) {
                                tokio::time::sleep(Duration::from_millis(
                                    GRACEFUL_SHUTDOWN_DELAY_MS,
                                ))
                                .await;
                                break;
                            }
                        }
                        Err(e) => {
                            error_messages
                                .push_back(format!("[json decode error] {}: {}", e, line));
                            // Keep only last 10 error messages
                            if error_messages.len() > 10 {
                                error_messages.pop_front();
                            }
                        }
                    }
                }
                Ok(None) => {
                    // EOF reached
                    break;
                }
                Err(e) => {
                    // IO error - log it and break
                    error_messages.push_back(format!("[io error] {}", e));
                    break;
                }
            }
        }
    })
    .await;

    // Graceful process termination: wait first, then kill if necessary
    let wait_result = timeout(Duration::from_secs(WAIT_TIMEOUT_SECS), child.wait()).await;
    if wait_result.is_err() {
        // Process didn't exit in time, force kill
        let _ = child.kill().await;
        let _ = child.wait().await;
    }

    // Build result
    let mut result = GeminiResult {
        success: true,
        session_id: session_id_result.clone(),
        agent_messages: None,
        all_messages: None,
        error: None,
    };

    // Check for errors
    let error_suffix: String = error_messages.into_iter().collect::<Vec<_>>().join("\n");

    if read_result.is_err() {
        result.success = false;
        result.error = Some(format!("Process timeout. {}", error_suffix));
    } else if session_id_result.is_none() {
        result.success = false;
        result.error = Some(format!(
            "Failed to get `SESSION_ID` from the gemini session.\n\n{}",
            error_suffix
        ));
    } else if agent_messages.is_empty() {
        result.success = false;
        result.error = Some(format!(
            "Failed to retrieve `agent_messages` data from the Gemini session. \
            This might be due to Gemini performing a tool call. \
            You can continue using the `SESSION_ID` to proceed with the conversation.\n\n{}",
            error_suffix
        ));
    } else {
        result.agent_messages = Some(agent_messages);
    }

    if return_all_messages {
        result.all_messages = all_messages;
    }

    Ok(result)
}
