//! Gemini MCP Server - Wraps Gemini CLI as a standard MCP protocol interface.
//!
//! This crate provides an MCP server that enables Claude Code to invoke
//! the Gemini CLI for AI-assisted programming tasks.

pub mod error;
pub mod gemini;
pub mod server;

pub use error::{GeminiError, Result};
pub use gemini::{execute_gemini, GeminiEvent, GeminiResult};
pub use server::{run_server, GeminiServer, GeminiToolInput};
