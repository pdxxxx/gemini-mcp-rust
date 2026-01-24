# Gemini MCP Server (Rust)

一个将 [Gemini CLI](https://github.com/google-gemini/gemini-cli) 封装为标准 MCP (Model Context Protocol) 协议接口的服务器，使用 Rust 实现。

## 功能特性

- 🚀 **高性能**: 使用 Rust 编写，编译为原生二进制文件
- 🔄 **会话管理**: 支持多轮对话，通过 SESSION_ID 保持上下文
- 🛡️ **沙箱模式**: 可选的沙箱模式隔离文件修改
- 📦 **跨平台**: 支持 Linux、Windows、macOS

## 安装

### 方式一：使用 npx 安装（推荐）

使用交互式安装程序，支持安装、配置、更新和卸载：

```bash
npx gemini-mcp-rust@latest
```

安装程序提供以下功能：

| 选项 | 功能 | 说明 |
|------|------|------|
| 1. Install | 安装 | 自动检测系统架构，下载并安装最新版本 |
| 2. Configure | 配置 | 将 gemini-mcp 注册到 Claude Code |
| 3. Update | 更新 | 检查新版本并升级 |
| 4. Uninstall | 卸载 | 删除二进制文件和 Claude 配置 |

**默认安装路径：**
- Linux/macOS: `~/.local/bin/gemini-mcp`
- Windows: `%LOCALAPPDATA%\Programs\gemini-mcp\gemini-mcp.exe`

### 方式二：从 GitHub Release 手动下载

前往 [Releases 页面](https://github.com/pdxxxx/gemini-mcp-rust/releases) 下载适合您系统的版本：

| 操作系统 | 架构 | 文件名 |
|---------|------|--------|
| Linux | x86_64 | `gemini-mcp-linux-amd64` |
| Linux | ARM64 | `gemini-mcp-linux-arm64` |
| Windows | x86_64 | `gemini-mcp-windows-amd64.exe` |
| macOS | x86_64 | `gemini-mcp-macos-amd64` |
| macOS | ARM64 (Apple Silicon) | `gemini-mcp-macos-arm64` |

下载后给予执行权限（Linux/macOS）：

```bash
chmod +x gemini-mcp-*
```

### 方式三：从源码编译

```bash
git clone https://github.com/pdxxxx/gemini-mcp-rust.git
cd gemini-mcp-rust
cargo build --release
```

编译后的二进制文件位于 `target/release/gemini-mcp`

## 配置

### Claude Code 配置

在 Claude Code 的 MCP 配置文件中添加：

```json
{
  "mcpServers": {
    "gemini": {
      "command": "/path/to/gemini-mcp"
    }
  }
}
```

Windows 用户：

```json
{
  "mcpServers": {
    "gemini": {
      "command": "C:\\path\\to\\gemini-mcp.exe"
    }
  }
}
```

## 使用方法

### 工具参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `PROMPT` | string | ✅ | 发送给 Gemini 的指令 |
| `cd` | string | ✅ | Gemini 执行的工作目录 |
| `sandbox` | boolean | ❌ | 是否启用沙箱模式（默认: false）|
| `SESSION_ID` | string | ❌ | 会话ID，用于恢复之前的对话 |
| `return_all_messages` | boolean | ❌ | 是否返回所有消息（默认: false）|
| `model` | string | ❌ | 指定使用的模型 |

### 返回结构

```json
{
  "success": true,
  "SESSION_ID": "uuid-string",
  "agent_messages": "Gemini 的回复内容",
  "all_messages": [],
  "error": null
}
```

## 前置要求

- 需要先安装 [Gemini CLI](https://github.com/google-gemini/gemini-cli) 并确保 `gemini` 命令在 PATH 中可用

## 许可证

MIT License

## 致谢

- [geminimcp](https://github.com/GuDaStudio/geminimcp) - 本项目参考了该项目的 Python 实现
- [rmcp](https://github.com/modelcontextprotocol/rust-sdk) - Rust MCP SDK
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) - Google Gemini 命令行工具
