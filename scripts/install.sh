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
    local ver=""
    # 方法 1: GitHub API (受速率限制，每 IP 每小时 60 次)
    ver=$(curl -s --connect-timeout 10 --max-time 15 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    # 方法 2: Fallback 到 Release 页面重定向 URL (无速率限制)
    if [ -z "$ver" ]; then
        local effective_url=""
        effective_url=$(curl -sL --connect-timeout 10 --max-time 15 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null)
        ver="${effective_url##*/}"
    fi

    # 验证版本格式
    if [ -n "$ver" ] && [ "$ver" != "latest" ] && echo "$ver" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+'; then
        echo "$ver"
    else
        echo ""
    fi
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
    local install_dir=$(dirname "$install_path")
    local run_as=""

    # 检查写入权限，如果需要则使用 sudo
    if [ -d "$install_dir" ] && [ ! -w "$install_dir" ]; then
        run_as="sudo"
        print_warning "需要管理员权限写入 $install_dir"
    elif [ ! -d "$install_dir" ]; then
        local parent_dir=$(dirname "$install_dir")
        if [ -d "$parent_dir" ] && [ ! -w "$parent_dir" ]; then
            run_as="sudo"
            print_warning "需要管理员权限创建 $install_dir"
        fi
    fi

    # 检查 sudo 是否可用
    if [ -n "$run_as" ] && ! command -v sudo &> /dev/null; then
        print_error "需要 sudo 权限，但系统未安装 sudo"
        exit 1
    fi

    print_info "正在下载 ${BINARY_NAME} ${version} (${platform})..."

    # 创建临时文件并设置清理 trap
    local tmp_file
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/${BINARY_NAME}.XXXXXX")
    trap 'rm -f "'"$tmp_file"'"' EXIT INT TERM

    # 根据是否为终端决定进度显示方式
    local curl_progress="--progress-bar"
    if [ ! -t 1 ]; then
        curl_progress="-sS"
    fi

    # 使用 --progress-bar 显示进度，-L 跟随重定向，-f 失败时静默，--max-time 限制总耗时
    if ! curl -fL --connect-timeout 30 --max-time 300 $curl_progress "$download_url" -o "$tmp_file"; then
        print_error "下载失败: $download_url"
        exit 1
    fi

    # 验证下载的文件不为空
    if [ ! -s "$tmp_file" ]; then
        print_error "下载的文件为空"
        exit 1
    fi

    # 创建目标目录
    if [ ! -d "$install_dir" ]; then
        print_info "创建目录: $install_dir"
        $run_as mkdir -p "$install_dir"
    fi

    # 移动文件并设置权限
    $run_as mv "$tmp_file" "$install_path"
    $run_as chmod +x "$install_path"

    print_success "已安装到: $install_path"
    trap - EXIT INT TERM
}

# 检查 gemini MCP 是否已存在
check_existing_mcp() {
    if ! command -v claude &> /dev/null; then
        return 1
    fi

    # 精确匹配名为 "gemini" 的 MCP（避免匹配到 gemini-pro 等其他名称）
    if claude mcp list 2>/dev/null | grep -Eq '^[[:space:]]*gemini([[:space:]]|:|$)'; then
        return 0
    fi
    return 1
}

# 配置 Claude Code
configure_claude_code() {
    local install_path="$1"

    # 检查 claude 命令是否可用
    if ! command -v claude &> /dev/null; then
        print_error "未找到 claude 命令，请先安装 Claude Code CLI"
        print_info "安装后可手动运行: claude mcp add gemini \"$install_path\""
        return 1
    fi

    # 检查是否已存在 gemini MCP
    if check_existing_mcp; then
        print_warning "检测到已存在 gemini MCP 配置"
        read -p "是否先删除现有配置再添加? [Y/n]: " remove_existing
        if [ "$remove_existing" != "n" ] && [ "$remove_existing" != "N" ]; then
            print_info "正在删除现有 gemini MCP 配置..."
            if claude mcp remove gemini 2>/dev/null; then
                print_success "已删除现有配置"
            else
                print_error "删除失败，请手动运行: claude mcp remove gemini"
                return 1
            fi
        else
            print_info "跳过 MCP 配置"
            return 0
        fi
    fi

    # 添加 MCP 配置
    print_info "正在添加 gemini MCP 配置..."
    if claude mcp add gemini "$install_path" 2>/dev/null; then
        print_success "已成功添加 gemini MCP 配置"
        return 0
    else
        print_error "添加失败，请手动运行: claude mcp add gemini \"$install_path\""
        return 1
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
            print_info "正在重新安装 $latest_version..."
        else
            print_info "发现新版本: v$installed_version -> $latest_version"
            read -p "是否更新到 $latest_version? [Y/n]: " do_update
            if [ "$do_update" = "n" ] || [ "$do_update" = "N" ]; then
                exit 0
            fi
            print_info "正在更新到 $latest_version..."
        fi
    else
        print_info "正在安装 $latest_version..."
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
        print_warning "安装目录不在 PATH 中"

        # 自动检测用户 Shell 配置文件
        local shell_config=""
        case "$SHELL" in
            */zsh)  shell_config="$HOME/.zshrc" ;;
            */bash) shell_config="$HOME/.bashrc" ;;
            *)      shell_config="" ;;
        esac

        if [ -n "$shell_config" ] && [ -f "$shell_config" ]; then
            read -p "是否自动将路径添加到 $shell_config? [Y/n]: " auto_path
            if [ "$auto_path" != "n" ] && [ "$auto_path" != "N" ]; then
                # 幂等检查：避免重复添加
                if grep -Fqs "$install_dir" "$shell_config"; then
                    print_info "检测到 $shell_config 已包含 $install_dir，跳过写入"
                else
                    echo "" >> "$shell_config"
                    echo "# Gemini MCP Server" >> "$shell_config"
                    echo "export PATH=\"\$PATH:$install_dir\"" >> "$shell_config"
                    print_success "已添加到 $shell_config"
                fi
                print_info "请运行 'source $shell_config' 或重新打开终端使其生效"
            else
                echo ""
                echo "  请手动添加以下内容到你的 shell 配置文件:"
                echo "  export PATH=\"\$PATH:$install_dir\""
                echo ""
            fi
        else
            echo ""
            echo "  请手动添加以下内容到 ~/.bashrc 或 ~/.zshrc:"
            echo "  export PATH=\"\$PATH:$install_dir\""
            echo ""
        fi
    fi

    echo ""
    print_success "安装完成！版本: $latest_version"
    echo ""
    echo "使用方法:"
    echo "  $install_path --help"
    echo ""
}

main "$@"
