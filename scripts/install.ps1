# Gemini MCP Server 安装脚本 (Windows PowerShell)
# 支持 Windows x86_64

$ErrorActionPreference = "Stop"

$REPO = "pdxxxx/gemini-mcp-rust"
$BINARY_NAME = "gemini-mcp"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARNING] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Get-LatestVersion {
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/releases/latest"
        return $release.tag_name
    }
    catch {
        return $null
    }
}

function Get-InstalledVersion {
    param([string]$InstallPath)

    if (Test-Path $InstallPath) {
        try {
            $output = & $InstallPath --version 2>$null
            if ($output -match "(\d+\.\d+\.\d+)") {
                return $Matches[1]
            }
        }
        catch {
            return $null
        }
    }
    return $null
}

function Install-GeminiMcp {
    param(
        [string]$Version,
        [string]$InstallPath
    )

    $platform = "windows-amd64"
    $downloadUrl = "https://github.com/$REPO/releases/download/$Version/$BINARY_NAME-$platform.exe"

    Write-Info "正在下载 $BINARY_NAME $Version ($platform)..."

    # 创建目标目录
    $installDir = Split-Path -Parent $InstallPath
    if (-not (Test-Path $installDir)) {
        Write-Info "创建目录: $installDir"
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    # 下载文件
    try {
        $tempFile = [System.IO.Path]::GetTempFileName() + ".exe"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -UseBasicParsing

        # 移动文件
        if (Test-Path $InstallPath) {
            Remove-Item $InstallPath -Force
        }
        Move-Item $tempFile $InstallPath -Force

        Write-Success "已安装到: $InstallPath"
    }
    catch {
        Write-Err "下载失败: $_"
        exit 1
    }
}

function Test-ExistingMcp {
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        return $false
    }

    try {
        $mcpList = & claude mcp list 2>$null
        if ($mcpList -match "gemini") {
            return $true
        }
    }
    catch {
        return $false
    }
    return $false
}

function Add-ClaudeCodeConfig {
    param([string]$InstallPath)

    # 检查 claude 命令是否可用
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Write-Err "未找到 claude 命令，请先安装 Claude Code CLI"
        Write-Info "安装后可手动运行: claude mcp add gemini `"$InstallPath`""
        return $false
    }

    # 检查是否已存在 gemini MCP
    if (Test-ExistingMcp) {
        Write-Warn "检测到已存在 gemini MCP 配置"
        $removeExisting = Read-Host "是否先删除现有配置再添加? [Y/n]"
        if ($removeExisting -ne "n" -and $removeExisting -ne "N") {
            Write-Info "正在删除现有 gemini MCP 配置..."
            try {
                & claude mcp remove gemini 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "已删除现有配置"
                }
                else {
                    Write-Err "删除失败，请手动运行: claude mcp remove gemini"
                    return $false
                }
            }
            catch {
                Write-Err "删除失败，请手动运行: claude mcp remove gemini"
                return $false
            }
        }
        else {
            Write-Info "跳过 MCP 配置"
            return $true
        }
    }

    # 添加 MCP 配置
    Write-Info "正在添加 gemini MCP 配置..."
    try {
        & claude mcp add gemini $InstallPath 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "已成功添加 gemini MCP 配置"
            return $true
        }
        else {
            Write-Err "添加失败，请手动运行: claude mcp add gemini `"$InstallPath`""
            return $false
        }
    }
    catch {
        Write-Err "添加失败，请手动运行: claude mcp add gemini `"$InstallPath`""
        return $false
    }
}

function Add-ToPath {
    param([string]$Directory)

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$Directory*") {
        $newPath = "$currentPath;$Directory"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Success "已将 $Directory 添加到用户 PATH"
        Write-Warn "请重新打开终端以使 PATH 更改生效"
    }
}

function Main {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     Gemini MCP Server 安装程序           ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # 获取最新版本
    Write-Info "正在获取最新版本..."
    $latestVersion = Get-LatestVersion
    if (-not $latestVersion) {
        Write-Err "无法获取最新版本信息"
        exit 1
    }
    Write-Info "最新版本: $latestVersion"

    # 默认安装路径
    $defaultInstallPath = Join-Path $env:LOCALAPPDATA "Programs\gemini-mcp\gemini-mcp.exe"

    # 询问安装路径
    Write-Host ""
    $installPath = Read-Host "请输入安装路径 [默认: $defaultInstallPath]"
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        $installPath = $defaultInstallPath
    }

    # 检查是否已安装
    $installedVersion = Get-InstalledVersion -InstallPath $installPath
    if ($installedVersion) {
        Write-Info "检测到已安装版本: v$installedVersion"
        if ("v$installedVersion" -eq $latestVersion) {
            Write-Success "已是最新版本，无需更新"
            $forceReinstall = Read-Host "是否强制重新安装? [y/N]"
            if ($forceReinstall -ne "y" -and $forceReinstall -ne "Y") {
                exit 0
            }
            Write-Info "正在重新安装 $latestVersion..."
        }
        else {
            Write-Info "发现新版本: v$installedVersion -> $latestVersion"
            $doUpdate = Read-Host "是否更新到 $latestVersion? [Y/n]"
            if ($doUpdate -eq "n" -or $doUpdate -eq "N") {
                exit 0
            }
            Write-Info "正在更新到 $latestVersion..."
        }
    }
    else {
        Write-Info "正在安装 $latestVersion..."
    }

    # 下载并安装
    Install-GeminiMcp -Version $latestVersion -InstallPath $installPath

    # 询问是否配置 Claude Code
    Write-Host ""
    $configureClaude = Read-Host "是否将 gemini-mcp 添加到 Claude Code 配置? [Y/n]"
    if ($configureClaude -ne "n" -and $configureClaude -ne "N") {
        Add-ClaudeCodeConfig -InstallPath $installPath
    }

    # 询问是否添加到 PATH
    $installDir = Split-Path -Parent $installPath
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$installDir*") {
        Write-Host ""
        $addToPath = Read-Host "是否将安装目录添加到 PATH? [Y/n]"
        if ($addToPath -ne "n" -and $addToPath -ne "N") {
            Add-ToPath -Directory $installDir
        }
    }

    Write-Host ""
    Write-Success "安装完成！版本: $latestVersion"
    Write-Host ""
    Write-Host "使用方法:"
    Write-Host "  $installPath --help"
    Write-Host ""
}

Main
