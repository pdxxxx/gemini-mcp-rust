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

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Error {
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
        Write-Error "下载失败: $_"
        exit 1
    }
}

function Add-ClaudeCodeConfig {
    param([string]$InstallPath)

    $configDir = Join-Path $env:USERPROFILE ".claude"
    $configFile = Join-Path $configDir "claude_desktop_config.json"

    # 创建配置目录
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # 转义路径中的反斜杠
    $escapedPath = $InstallPath.Replace("\", "\\")

    if (Test-Path $configFile) {
        # 备份原配置
        $backupFile = "$configFile.backup"
        Copy-Item $configFile $backupFile -Force
        Write-Info "已备份原配置到: $backupFile"

        # 读取并更新配置
        try {
            $config = Get-Content $configFile -Raw | ConvertFrom-Json

            if (-not $config.mcpServers) {
                $config | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue @{} -Force
            }

            if ($config.mcpServers.gemini) {
                Write-Warning "Claude Code 配置中已存在 gemini 配置，正在更新..."
            }

            $config.mcpServers | Add-Member -NotePropertyName "gemini" -NotePropertyValue @{
                command = $InstallPath
            } -Force

            $config | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
            Write-Success "已更新 Claude Code 配置"
        }
        catch {
            Write-Warning "无法解析现有配置文件，请手动添加以下配置:"
            Write-Host ""
            Write-Host "  `"gemini`": {"
            Write-Host "    `"command`": `"$escapedPath`""
            Write-Host "  }"
            return
        }
    }
    else {
        # 创建新配置
        $config = @{
            mcpServers = @{
                gemini = @{
                    command = $InstallPath
                }
            }
        }
        $config | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8
        Write-Success "已创建 Claude Code 配置"
    }
}

function Add-ToPath {
    param([string]$Directory)

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$Directory*") {
        $newPath = "$currentPath;$Directory"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Success "已将 $Directory 添加到用户 PATH"
        Write-Warning "请重新打开终端以使 PATH 更改生效"
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
        Write-Error "无法获取最新版本信息"
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
        }
        else {
            $doUpdate = Read-Host "是否更新到 $latestVersion? [Y/n]"
            if ($doUpdate -eq "n" -or $doUpdate -eq "N") {
                exit 0
            }
        }
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
    Write-Success "安装完成！"
    Write-Host ""
    Write-Host "使用方法:"
    Write-Host "  $installPath --help"
    Write-Host ""
}

Main
