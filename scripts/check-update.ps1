#requires -version 5.1
<#
  Codex 汉化工具在线更新（可选功能，默认不使用）
  说明：联网获取仓库最新 Release，与本地工具版本比较；
        有新版本时自动下载 zip、备份旧工具目录、覆盖，并重新运行安装（仅一次 UAC）。
        断网时输出离线提示并正常退出，不影响已有汉化。
        本脚本只访问 github.com，绝不访问 OpenAI。
#>
param([switch]$NoPause)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Write-Title {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   Codex 汉化工具在线更新检查" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}
function Write-Step([string]$Message) { Write-Host ""; Write-Host $Message -ForegroundColor Yellow }
function Write-Ok([string]$Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "  [!] $Message" -ForegroundColor Yellow }
function Write-Bad([string]$Message) { Write-Host "  [X] $Message" -ForegroundColor Red }
function Write-Info([string]$Message) { Write-Host "  [i] $Message" -ForegroundColor DarkGray }

function Compare-VersionStr {
    param([string]$A, [string]$B)
    function Get-Nums([string]$S) {
        $p = @(($S.Trim().TrimStart('v','V')) -split '\.')
        $n = @()
        for ($i = 0; $i -lt 4; $i++) {
            if ($i -lt $p.Count) { $v = 0; [int]::TryParse($p[$i], [ref]$v) | Out-Null; $n += $v }
            else { $n += 0 }
        }
        return ,$n
    }
    $na = Get-Nums $A
    $nb = Get-Nums $B
    for ($i = 0; $i -lt 4; $i++) {
        if ($na[$i] -gt $nb[$i]) { return 1 }
        if ($na[$i] -lt $nb[$i]) { return -1 }
    }
    return 0
}

$repo = "ukinch605/codex-zh-cn-agent"
$toolHome = Join-Path $env:USERPROFILE ".codex\zh-cn-agent"
$versionsLocal = Join-Path $toolHome "versions.json"
if (-not (Test-Path -LiteralPath $versionsLocal)) { $versionsLocal = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\versions.json" }
$localVersion = "0.0.0"
if (Test-Path -LiteralPath $versionsLocal) {
    try {
        $d = Get-Content -Raw -Encoding UTF8 $versionsLocal | ConvertFrom-Json
        if ($d.toolVersion) { $localVersion = [string]$d.toolVersion }
    } catch {}
}

Write-Title
Write-Info "本地工具版本: $localVersion"
Write-Info "检查来源: https://github.com/$repo/releases"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$release = $null
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "codex-zh-cn-agent" } -TimeoutSec 20
} catch {
    Write-Host ""
    Write-Warn "无法连接 GitHub（可能处于离线环境）。"
    Write-Info "当前为离线模式，请到 https://github.com/$repo/releases 手动下载最新版本，或让 Codex 重新拉取仓库执行安装。"
    if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
    exit 0
}

$remoteTag = [string]$release.tag_name
$asset = @($release.assets) | Where-Object { $_.name -like "codex-zh-cn-agent-v*.zip" } | Select-Object -First 1
if (-not $asset) {
    Write-Bad "最新 Release（$remoteTag）中未找到安装包 zip，请到仓库 Releases 页查看。"
    if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
    exit 1
}

$cmp = Compare-VersionStr -A $localVersion -B $remoteTag
if ($cmp -ge 0) {
    Write-Ok "已是最新版本（$localVersion）。"
    if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
    exit 0
}

Write-Step "发现新版本 $remoteTag（当前 $localVersion），正在下载..."
$tmpZip = Join-Path $env:TEMP ("codex-zh-cn-agent-" + $remoteTag + "-" + [guid]::NewGuid().ToString("N") + ".zip")
try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -UseBasicParsing -TimeoutSec 120
} catch {
    Write-Bad "下载失败：$($_.Exception.Message)"
    Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
    if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
    exit 1
}

$tmpDir = Join-Path $env:TEMP ("codex-zh-cn-agent-update-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
try {
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
} catch {
    Write-Bad "解压失败：$($_.Exception.Message)"
    Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
    exit 1
}

$newRoot = Join-Path $tmpDir ("codex-zh-cn-agent-v" + ($remoteTag.TrimStart('v','V')))
if (-not (Test-Path -LiteralPath (Join-Path $newRoot "scripts\install-zh-cn.ps1"))) { $newRoot = $tmpDir }
if (-not (Test-Path -LiteralPath (Join-Path $newRoot "scripts\install-zh-cn.ps1")) -or -not (Test-Path -LiteralPath (Join-Path $newRoot "versions.json"))) {
    Write-Bad "下载的更新包内容不完整，已中止（未做任何修改）。"
    Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
    exit 1
}

if (Test-Path -LiteralPath $toolHome) {
    $bak = Join-Path $env:USERPROFILE (".codex\zh-cn-agent.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-Step "正在备份旧工具目录: $bak"
    Copy-Item -LiteralPath $toolHome -Destination $bak -Recurse -Force
}

New-Item -ItemType Directory -Path $toolHome -Force | Out-Null
Copy-Item -Path (Join-Path $newRoot "*") -Destination $toolHome -Recurse -Force
Write-Ok "工具已更新到 $remoteTag。"

Write-Step "正在重新安装汉化（请在弹出的 UAC 窗口中点击「是」）..."
$installer = Join-Path $toolHome "scripts\install-zh-cn.ps1"
Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$installer`"","-Action","install","-NoPause")
Write-Ok "已启动安装流程。安装完成后 Codex 会自动重启为中文版。"

Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
exit 0
