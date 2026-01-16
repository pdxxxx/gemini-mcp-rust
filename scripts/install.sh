#!/bin/bash
# Gemini MCP Server 安装脚本
# 支持 Linux 和 macOS

set -e

REPO="pdxxxx/gemini-mcp-rust"
BINARY_NAME="gemini-mcp"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测系统架构
detect_platform() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)

    case "$os" in
        linux)
            case "$arch" in
                x86_64|amd64)
                    echo "linux-amd64"
                    ;;
                aarch64|arm64)
                    echo "linux-arm64"
                    ;;
                *)
                    print_error "不支持的架构: $arch"
                    exit 1
                    ;;
            esac
            ;;
        darwin)
            case "$arch" in
                x86_64|amd64)
                    echo "macos-amd64"
                    ;;
                arm64|aarch64)
                    echo "macos-arm64"
                    ;;
                *)
                    print_error "不支持的架构: $arch"
                    exit 1
                    ;;
            esac
            ;;
        *)
            print_error "不支持的操作系统: $os"
            exit 1
            ;;
    esac
}

# 获取最新版本
get_latest_version() {
    curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# 获取当前安装版本
get_installed_version() {
    local install_path="$1"
    if [ -f "$install_path" ]; then
        "$install_path" --version 2>/dev/null | awk '{print $2}' || echo ""
    else
        echo ""
    fi
}

# 下载并安装
download_and_install() {
    local version="$1"
    local platform="$2"
    local install_path="$3"

    local download_url="https://github.com/${REPO}/releases/download/${version}/${BINARY_NAME}-${platform}"

    print_info "正在下载 ${BINARY_NAME} ${version} (${platform})..."

    local tmp_file=$(mktemp)
    if ! curl -fsSL "$download_url" -o "$tmp_file"; then
        print_error "下载失败: $download_url"
        rm -f "$tmp_file"
        exit 1
    fi

    # 创建目标目录
    local install_dir=$(dirname "$install_path")
    if [ ! -d "$install_dir" ]; then
        print_info "创建目录: $install_dir"
        mkdir -p "$install_dir"
    fi

    # 移动文件并设置权限
    mv "$tmp_file" "$install_path"
    chmod +x "$install_path"

    print_success "已安装到: $install_path"
}

# 配置 Claude Code
configure_claude_code() {
    local install_path="$1"

    # 检查 claude 命令是否可用
    if command -v claude &> /dev/null; then
        print_info "检测到 Claude Code CLI，尝试使用 claude mcp add 命令..."

        # 使用 claude mcp add 命令添加配置
        if claude mcp add gemini "$install_path" 2>/dev/null; then
            print_success "已通过 Claude CLI 添加 gemini MCP 配置"
            return 0
        else
            print_warning "claude mcp add 命令失败，尝试手动配置..."
        fi
    fi

    # 手动配置 ~/.claude.json
    local config_file="$HOME/.claude.json"

    if [ -f "$config_file" ]; then
        # 备份原配置
        cp "$config_file" "${config_file}.backup"
        print_info "已备份原配置到: ${config_file}.backup"

        # 检查是否已经配置了 gemini
        if grep -q '"gemini"' "$config_file"; then
            print_warning "配置中已存在 gemini，正在更新..."
        fi

        # 使用 jq 如果可用
        if command -v jq &> /dev/null; then
            local tmp_config=$(mktemp)
            # 确保 mcpServers 存在并添加 gemini
            jq --arg path "$install_path" '
                .mcpServers //= {} |
                .mcpServers.gemini = {"command": $path, "args": []}
            ' "$config_file" > "$tmp_config"
            mv "$tmp_config" "$config_file"
            print_success "已更新 Claude Code 配置: $config_file"
        else
            print_warning "未找到 jq 工具，请手动编辑 $config_file"
            print_info "添加以下内容到 mcpServers 中:"
            echo ""
            echo '    "gemini": {'
            echo "      \"command\": \"$install_path\","
            echo '      "args": []'
            echo '    }'
            echo ""
        fi
    else
        # 创建新配置文件
        cat > "$config_file" << EOF
{
  "mcpServers": {
    "gemini": {
      "command": "$install_path",
      "args": []
    }
  }
}
EOF
        print_success "已创建 Claude Code 配置: $config_file"
    fi
}

# 主函数
main() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║     Gemini MCP Server 安装程序           ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    # 检测平台
    local platform=$(detect_platform)
    print_info "检测到平台: $platform"

    # 获取最新版本
    print_info "正在获取最新版本..."
    local latest_version=$(get_latest_version)
    if [ -z "$latest_version" ]; then
        print_error "无法获取最新版本信息"
        exit 1
    fi
    print_info "最新版本: $latest_version"

    # 默认安装路径
    local default_install_path="$HOME/.local/bin/${BINARY_NAME}"

    # 询问安装路径
    echo ""
    read -p "请输入安装路径 [默认: $default_install_path]: " install_path
    install_path="${install_path:-$default_install_path}"

    # 检查是否已安装
    local installed_version=$(get_installed_version "$install_path")
    if [ -n "$installed_version" ]; then
        print_info "检测到已安装版本: v$installed_version"
        if [ "v$installed_version" = "$latest_version" ]; then
            print_success "已是最新版本，无需更新"
            read -p "是否强制重新安装? [y/N]: " force_reinstall
            if [ "$force_reinstall" != "y" ] && [ "$force_reinstall" != "Y" ]; then
                exit 0
            fi
        else
            read -p "是否更新到 $latest_version? [Y/n]: " do_update
            if [ "$do_update" = "n" ] || [ "$do_update" = "N" ]; then
                exit 0
            fi
        fi
    fi

    # 下载并安装
    download_and_install "$latest_version" "$platform" "$install_path"

    # 询问是否配置 Claude Code
    echo ""
    read -p "是否将 gemini-mcp 添加到 Claude Code 配置? [Y/n]: " configure_claude
    if [ "$configure_claude" != "n" ] && [ "$configure_claude" != "N" ]; then
        configure_claude_code "$install_path"
    fi

    # 检查 PATH
    local install_dir=$(dirname "$install_path")
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        print_warning "安装目录不在 PATH 中，建议添加以下内容到 ~/.bashrc 或 ~/.zshrc:"
        echo ""
        echo "  export PATH=\"\$PATH:$install_dir\""
        echo ""
    fi

    echo ""
    print_success "安装完成！"
    echo ""
    echo "使用方法:"
    echo "  $install_path --help"
    echo ""
    echo "如需手动配置 Claude Code，请编辑 ~/.claude.json 或运行:"
    echo "  claude mcp add gemini $install_path"
    echo ""
}

main "$@"
