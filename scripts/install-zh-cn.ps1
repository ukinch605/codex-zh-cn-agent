#requires -version 5.1
<#
  Codex Desktop 一键汉化安装器（Windows / Microsoft Store 版）v1.3
  用法：powershell -ExecutionPolicy Bypass -File install-zh-cn.ps1 [-Action menu|install|verify|status|uninstall|check-update|test] [-CodexPath "路径"] [-NoPause] [-Force]

  说明：
  - 结果文件协议：%USERPROFILE%\.codex\zh-cn-agent\install-result.json
    安装开始时先写 status=pending，提升后的进程结束时覆盖为 ok / fail（含 code、message、诊断文件路径），供 agent 轮询。
    安装完成后由监督式启动脚本另写 launch-result.json（见 scripts/launch-zh-cn.ps1），
    install-result.json 中记录该文件路径，供重启后的 agent 读取并汇报。
  - 自包含安装：bat、scripts、versions.json、使用说明等复制到 %USERPROFILE%\.codex\zh-cn-agent\，
    桌面快捷方式指向该固定副本，仓库被移动/删除后汉化入口仍可用。
  - 版本自适应：优先查 versions.json 已测版本表；未知版本用通用特征探测；仍失败则写诊断文件并报 VERSION_UNSUPPORTED。
#>
param(
    [ValidateSet("menu","install","uninstall","status","verify","check-update","test","freeze","unfreeze")]
    [string]$Action = "menu",
    [string]$CodexPath = "",
    [switch]$NoPause,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptDir
$launcher = Join-Path $scriptDir "launch-zh-cn.ps1"
$activeFile = Join-Path $env:USERPROFILE ".codex\zh-cn-patched-active.txt"
$patchedBase = Join-Path $env:USERPROFILE ".codex\zh-cn-patched"
$toolHome = Join-Path $env:USERPROFILE ".codex\zh-cn-agent"
$resultFile = Join-Path $toolHome "install-result.json"
$launchResultFile = Join-Path $toolHome "launch-result.json"
$installedFile = Join-Path $toolHome "installed.json"
$versionsFile = Join-Path $projectRoot "versions.json"
$logDir = Join-Path $toolHome "logs"
$script:logFile = ""

# 默认特征串（versions.json 缺省时的回退）
$script:defaultMarkers = [pscustomobject]@{
    enableI18nFrom = 'enable_i18n`,!1)'
    enableI18nTo   = 'enable_i18n`,!0)'
    initFrom       = 'let s=o,c=a?.get(`'
    initTo         = 'let s=1,c=a?.get(`'
}

# ---------------- 受保护版本线（locale-only） ----------------
$script:installMode = "patch"
$script:localeOnlyFrom = "26.900.0.0"
try {
    if (Test-Path -LiteralPath $versionsFile) {
        $vd0 = Get-Content -Raw -Encoding UTF8 $versionsFile | ConvertFrom-Json
        if ($vd0.localeOnlyFrom) { $script:localeOnlyFrom = [string]$vd0.localeOnlyFrom }
    }
} catch {}

function Test-LocaleOnlyVersion {
    param([string]$Version)
    function Get-VerParts([string]$V) {
        $p = @(($V.Trim().TrimStart('v','V')) -split '\.')
        $n = @()
        for ($i = 0; $i -lt 4; $i++) {
            if ($i -lt $p.Count) { $x = 0; [int]::TryParse($p[$i], [ref]$x) | Out-Null; $n += $x } else { $n += 0 }
        }
        return ,$n
    }
    $a = Get-VerParts $Version
    $b = Get-VerParts $script:localeOnlyFrom
    for ($i = 0; $i -lt 4; $i++) {
        if ($a[$i] -lt $b[$i]) { return $false }
        if ($a[$i] -gt $b[$i]) { return $true }
    }
    return $true
}

# ---------------- 基础工具 ----------------
function Test-IsAdministrator {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedInstaller {
    param([string[]]$ExtraArgs = @())
    Write-Host ""
    Write-Host "  需要管理员权限，正在请求 UAC 提升..." -ForegroundColor Yellow
    Write-Host "  请在弹窗中点击「是」。" -ForegroundColor DarkGray
    Write-Host ""
    $psArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"") + $ExtraArgs
    Start-Process -FilePath "powershell.exe" -Verb RunAs -WorkingDirectory $projectRoot -ArgumentList $psArgs
    exit 0
}

function Ensure-Administrator {
    if (Test-IsAdministrator) { return }
    $extra = @("-Action", $Action)
    if ($CodexPath) { $extra += @("-CodexPath", $CodexPath) }
    if ($NoPause) { $extra += "-NoPause" }
    if ($Force) { $extra += "-Force" }
    Invoke-ElevatedInstaller -ExtraArgs $extra
}

function Write-Title {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   Codex Desktop 一键汉化（zh-CN）" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}

function Write-Step([string]$Message) { Write-Host ""; Write-Host $Message -ForegroundColor Yellow }
function Write-Ok([string]$Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "  [!] $Message" -ForegroundColor Yellow }
function Write-Bad([string]$Message) { Write-Host "  [X] $Message" -ForegroundColor Red }
function Write-Info([string]$Message) { Write-Host "  [i] $Message" -ForegroundColor DarkGray }

function Write-Log {
    param([string]$Message)
    try {
        if (-not $script:logFile) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            $script:logFile = Join-Path $logDir ("install-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
        }
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $script:logFile -Value $line -Encoding UTF8
    } catch {}
}

function Write-ResultFile {
    param([string]$Status, [string]$Code = "", [string]$Message = "", [string]$CodexVersion = "", [string]$PatchedDir = "", [string]$DiagFile = "", [string]$LaunchResultFile = "", [string]$Mode = "")
    try {
        New-Item -ItemType Directory -Path $toolHome -Force | Out-Null
        $obj = [ordered]@{
            status       = $Status
            code         = $Code
            message      = $Message
            codexVersion = $CodexVersion
            patchedDir   = $PatchedDir
            diagFile     = $DiagFile
            launchResultFile = $LaunchResultFile
            mode         = $Mode
            updatedAt    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fff")
        }
        [System.IO.File]::WriteAllText($resultFile, ($obj | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        Write-Warn "无法写入结果文件: $_"
    }
}

function Stop-CodexProcesses {
    Write-Step "正在关闭 Codex 相关进程（防止冲突）..."
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# ---------------- 查找 Codex ----------------
function Get-CodexVersion {
    try {
        $pkg = Get-AppxPackage -ErrorAction Stop |
            Where-Object { $_.Name -match 'Codex|OpenAI' } |
            Sort-Object { try { [version]$_.Version } catch { [version]'0.0.0.0' } } -Descending |
            Select-Object -First 1
        if ($pkg) { return [string]$pkg.Version }
    } catch {}
    # 回退：从 WindowsApps 目录名或 active 文件记录的原版目录反推版本号
    $names = @()
    if (Test-Path "C:\Program Files\WindowsApps") {
        $names += Get-ChildItem "C:\Program Files\WindowsApps" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^OpenAI\.Codex_' } |
            Select-Object -ExpandProperty Name
    }
    if (Test-Path -LiteralPath $activeFile) {
        $lines = Get-Content -LiteralPath $activeFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim().Length -gt 0 }
        if ($lines.Count -ge 2) { $names += Split-Path -Leaf (Split-Path -Parent $lines[1]) }
    }
    foreach ($n in $names) {
        $m = [regex]::Match($n, 'OpenAI\.Codex_([0-9]+(?:\.[0-9]+)+)_')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return $null
}

function Get-CodexAppDir {
    param([string]$CustomPath)
    if ($CustomPath) {
        foreach ($c in @($CustomPath, (Join-Path $CustomPath "app"))) {
            if (Test-Path (Join-Path $c "resources\app.asar")) { return $c }
        }
    }
    $pkg = $null
    try {
        $pkg = Get-AppxPackage -ErrorAction Stop |
            Where-Object { $_.Name -match 'Codex|OpenAI' } |
            Sort-Object { try { [version]$_.Version } catch { [version]'0.0.0.0' } } -Descending |
            Select-Object -First 1
    } catch { $pkg = $null }
    if ($pkg) {
        foreach ($c in @((Join-Path $pkg.InstallLocation "app"), $pkg.InstallLocation)) {
            if (Test-Path (Join-Path $c "resources\app.asar")) { return $c }
        }
    }
    $wapps = "C:\Program Files\WindowsApps"
    if (Test-Path $wapps) {
        $dirs = Get-ChildItem $wapps -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Codex|OpenAI' } |
            Sort-Object Name -Descending
        foreach ($d in $dirs) {
            foreach ($c in @((Join-Path $d.FullName "app"), $d.FullName)) {
                if (Test-Path (Join-Path $c "resources\app.asar")) { return $c }
            }
        }
    }
    # 最后回退：已安装机器上，active 文件记录的原版目录
    if (Test-Path -LiteralPath $activeFile) {
        $lines = Get-Content -LiteralPath $activeFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim().Length -gt 0 }
        if ($lines.Count -ge 2) {
            $c = $lines[1].Trim()
            foreach ($x in @($c, (Join-Path $c "app"))) {
                if (Test-Path (Join-Path $x "resources\app.asar")) { return $x }
            }
        }
    }
    return $null
}

# ---------------- asar 读取与补丁（等长字节替换，不改 asar 结构） ----------------
function Get-AppInitialInfo {
    param([string]$AsarPath)
    $fs = [System.IO.File]::OpenRead($AsarPath)
    try {
        $head = New-Object byte[] 16
        [void]$fs.Read($head, 0, 16)
        $hs = [BitConverter]::ToUInt32($head, 12)
        if ($hs -le 0 -or $hs -gt 67108864) { return $null }
        $hb = New-Object byte[] $hs
        [void]$fs.Read($hb, 0, $hs)
        $json = [System.Text.Encoding]::UTF8.GetString($hb)
        $m = [regex]::Match($json, '"app-initial-([^"]+\.js)"\s*:\s*\{(.*?)\}')
        if (-not $m.Success) { return $null }
        $mo = [regex]::Match($m.Groups[2].Value, '"offset"\s*:\s*"(\d+)"')
        $ms = [regex]::Match($m.Groups[2].Value, '"size"\s*:\s*(\d+)')
        if (-not $mo.Success -or -not $ms.Success) { return $null }
        return [pscustomobject]@{
            Name       = $m.Groups[1].Value
            Offset     = [long]$mo.Groups[1].Value
            Size       = [long]$ms.Groups[1].Value
            HeaderSize = $hs
        }
    } finally { $fs.Dispose() }
}

function Read-AppInitialText {
    param([string]$AsarPath)
    $info = Get-AppInitialInfo -AsarPath $AsarPath
    if (-not $info) { return $null }
    $fs = [System.IO.File]::OpenRead($AsarPath)
    try {
        $start = 16 + $info.HeaderSize + $info.Offset
        $buf = New-Object byte[] $info.Size
        $fs.Position = $start
        [void]$fs.Read($buf, 0, $buf.Length)
        return [System.Text.Encoding]::GetEncoding(28591).GetString($buf)
    } finally { $fs.Dispose() }
}

# ---------------- 特征串解析（版本表 + 通用探测） ----------------
function Get-TestedMarkers {
    param([string]$CodexVersion, [string]$VersionsFile = "")
    $file = if ($VersionsFile) { $VersionsFile } else { $versionsFile }
    if (-not $CodexVersion -or -not $file -or -not (Test-Path -LiteralPath $file)) { return $null }
    try {
        $data = Get-Content -Raw -Encoding UTF8 $file | ConvertFrom-Json
        if ($data.schema -ne 1) { return $null }
        $entry = @($data.tested) | Where-Object { $_.version -eq $CodexVersion } | Select-Object -First 1
        if (-not $entry -or -not $entry.markers) { return $null }
        return [pscustomobject]@{
            enableI18nFrom = [string]$entry.markers.enableI18nFrom
            enableI18nTo   = [string]$entry.markers.enableI18nTo
            initFrom       = [string]$entry.markers.initFrom
            initTo         = [string]$entry.markers.initTo
        }
    } catch { return $null }
}

function Get-I18nStateFromText {
    param([string]$Text, $Markers)
    $m = if ($Markers) { $Markers } else { $script:defaultMarkers }
    if ($Text.Contains([string]$m.enableI18nTo) -and $Text.Contains([string]$m.initTo)) { return "patched" }
    if ($Text.Contains([string]$m.enableI18nFrom) -or $Text.Contains([string]$m.initFrom)) { return "original" }
    return "unsupported"
}

function Find-GenericMarkers {
    param([string]$Text)
    $m = $script:defaultMarkers
    $c1 = [regex]::Matches($Text, [regex]::Escape([string]$m.enableI18nFrom)).Count
    $c2 = [regex]::Matches($Text, [regex]::Escape([string]$m.initFrom)).Count
    if ($c1 -ne 1 -or $c2 -ne 1) { return $null }
    return $m
}

function Resolve-Markers {
    param([string]$Text, [string]$CodexVersion, [string]$VersionsFile = "")
    $m = Get-TestedMarkers -CodexVersion $CodexVersion -VersionsFile $VersionsFile
    if ($m -and (Get-I18nStateFromText -Text $Text -Markers $m) -eq "original") { return $m }
    $g = Find-GenericMarkers -Text $Text
    if ($g) { return $g }
    return $null
}

function Export-CandidateMarkers {
    param([string]$CodexVersion, $Markers)
    if (-not $CodexVersion -or -not $Markers) { return }
    try {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $path = Join-Path $logDir ("candidate-" + $CodexVersion + ".json")
        $obj = [ordered]@{
            version = $CodexVersion
            date    = (Get-Date).ToString("yyyy-MM-dd")
            status  = "ok"
            markers = [ordered]@{
                enableI18nFrom = [string]$Markers.enableI18nFrom
                enableI18nTo   = [string]$Markers.enableI18nTo
                initFrom       = [string]$Markers.initFrom
                initTo         = [string]$Markers.initTo
            }
        }
        [System.IO.File]::WriteAllText($path, ($obj | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        Write-Log "通用特征探测成功，已导出候选特征串: $path"
        Write-Info ("该版本尚未收录进版本表，已导出候选特征串: " + $path)
    } catch {
        Write-Log ("候选特征串导出失败: " + $_.Exception.Message)
    }
}

function Get-SnippetFromText {
    param([string]$Text)
    $i = $Text.IndexOf('enable_i18n')
    if ($i -lt 0) { $i = 0 }
    $from = [Math]::Max(0, $i - 60)
    $len = [Math]::Min(240, $Text.Length - $from)
    return $Text.Substring($from, $len)
}

function Save-Diagnostic {
    param([string]$CodexVersion, [string]$Snippet, [string]$OutPath = "")
    $path = if ($OutPath) { $OutPath } else {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Join-Path $logDir ("diagnostic-" + $CodexVersion + ".txt")
    }
    $content = @(
        "Codex 版本: $CodexVersion"
        "生成时间: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
        ""
        "此文件用于向仓库提交 issue，请把完整内容贴到 https://github.com/ukinch605/codex-zh-cn-agent/issues"
        ""
        "代码片段（app-initial JS）:"
        $Snippet
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Get-AsarI18nState {
    param([string]$AsarPath, $Markers = $null)
    if (-not (Test-Path -LiteralPath $AsarPath)) { return "missing" }
    $text = Read-AppInitialText -AsarPath $AsarPath
    if ($null -eq $text) { return "unsupported" }
    return Get-I18nStateFromText -Text $text -Markers $Markers
}

function Invoke-PatchText {
    param([string]$Text, $Markers)
    $out = $Text.Replace([string]$Markers.enableI18nFrom, [string]$Markers.enableI18nTo)
    $out = $out.Replace([string]$Markers.initFrom, [string]$Markers.initTo)
    if ($out.Length -ne $Text.Length) { throw "PATCH_LENGTH_MISMATCH: 补丁后字符长度变化，已中止" }
    return $out
}

function Patch-AsarFile {
    param([string]$AsarPath, $Markers)
    $info = Get-AppInitialInfo -AsarPath $AsarPath
    if (-not $info) { throw "ASAR_PARSE_FAILED: 无法解析 app.asar" }
    $fs = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
    try {
        $start = 16 + $info.HeaderSize + $info.Offset
        $buf = New-Object byte[] $info.Size
        $fs.Position = $start
        [void]$fs.Read($buf, 0, $buf.Length)
        $enc = [System.Text.Encoding]::GetEncoding(28591)
        $text = $enc.GetString($buf)
        $out = Invoke-PatchText -Text $text -Markers $Markers
        $newBytes = $enc.GetBytes($out)
        if ($newBytes.Length -ne $buf.Length) { throw "PATCH_LENGTH_MISMATCH: 补丁后字节长度变化，已中止" }
        $fs.Position = $start
        $fs.Write($newBytes, 0, $newBytes.Length)
        $fs.Flush($true)
    } finally { $fs.Dispose() }
    if ((Get-AsarI18nState -AsarPath $AsarPath -Markers $Markers) -ne "patched") {
        throw "PATCH_VERIFY_FAILED: 写后复验未通过，请检查 app.asar 是否被占用或版本结构有变化"
    }
    return $true
}

# ---------------- 语言配置 ----------------
function Set-LocaleOverrideZhCn {
    param([string]$ConfigPathOverride = "")
    $configPath = if ($ConfigPathOverride) { $ConfigPathOverride } else { Join-Path $env:USERPROFILE ".codex\config.toml" }
    $dir = Split-Path -Parent $configPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $content = ""
    if (Test-Path $configPath) { $content = [System.IO.File]::ReadAllText($configPath) }
    $bak = "$configPath.bak-zhcn"
    if ((Test-Path $configPath) -and (-not (Test-Path $bak))) {
        Copy-Item -LiteralPath $configPath -Destination $bak -Force
        Write-Info "已备份原配置: $bak"
    }
    $localePattern = '(?m)^[ \t]*localeOverride\s*=\s*(''|")[^''"]*\1'
    if ($content -match $localePattern) {
        $content = [regex]::Replace($content, $localePattern, 'localeOverride = "zh-CN"')
    } elseif ($content -match '(?m)^\[desktop\]\s*$') {
        $content = [regex]::Replace($content, '(?m)^\[desktop\]\s*$', "[desktop]`r`nlocaleOverride = `"zh-CN`"", 1)
    } elseif ($content.Trim().Length -eq 0) {
        $content = "[desktop]`r`nlocaleOverride = `"zh-CN`"`r`n"
    } else {
        $content = $content.TrimEnd() + "`r`n`r`n[desktop]`r`nlocaleOverride = `"zh-CN`"`r`n"
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configPath, $content, $utf8NoBom)
}

# ---------------- 自包含工具目录 ----------------
function Get-ToolVersion {
    if (Test-Path -LiteralPath $versionsFile) {
        try {
            $d = Get-Content -Raw -Encoding UTF8 $versionsFile | ConvertFrom-Json
            if ($d.toolVersion) { return [string]$d.toolVersion }
        } catch {}
    }
    return "1.3.0"
}

function Install-ToolFiles {
    param([string]$SourceRoot)
    $src = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $dst = [System.IO.Path]::GetFullPath($toolHome).TrimEnd('\')
    if ($src -eq $dst) { return }
    New-Item -ItemType Directory -Path $toolHome -Force | Out-Null
    foreach ($name in @("安装汉化.bat","启动汉化版.bat","恢复原版.bat","卸载汉化.bat","检查更新.bat","versions.json","使用说明.txt","README.md","AGENTS.md","LICENSE")) {
        $p = Join-Path $SourceRoot $name
        if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $toolHome $name) -Force }
    }
    $scriptsDst = Join-Path $toolHome "scripts"
    New-Item -ItemType Directory -Path $scriptsDst -Force | Out-Null
    Copy-Item -Path (Join-Path $SourceRoot "scripts\*") -Destination $scriptsDst -Recurse -Force
}

function Write-InstalledInfo {
    param([string]$ToolVersion, [string]$CodexVersion, [string]$PatchedDir, [string]$OrigDir, [string]$Mode = "patch")
    New-Item -ItemType Directory -Path $toolHome -Force | Out-Null
    $obj = [ordered]@{
        toolVersion = $ToolVersion
        codexVersion = $CodexVersion
        patchedDir = $PatchedDir
        origDir = $OrigDir
        mode = $Mode
        installedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fff")
    }
    [System.IO.File]::WriteAllText($installedFile, ($obj | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-DesktopShortcutName {
    param([int]$CodePage = 0)
    $cp = if ($CodePage -gt 0) { $CodePage } else { [System.Text.Encoding]::Default.CodePage }
    # 中文名仅在简体中文代码页(936)下使用；其他系统（如英文 1252）回退为 ASCII 名，
    # 避免 WSH 在 ANSI 代码页无法表示中文时把文件名写成 "Codex ???.lnk" 导致保存失败。
    if ($cp -eq 936) { return "Codex 汉化版.lnk" }
    return "Codex zh-CN.lnk"
}

function New-DesktopShortcut {
    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE "Desktop" }
    $lnk = Join-Path $desktop (Get-DesktopShortcutName)
    $ps = Join-Path $toolHome "scripts\launch-zh-cn.ps1"
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = "powershell.exe"
    $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps`""
    $sc.WorkingDirectory = $toolHome
    $sc.IconLocation = "$env:WINDIR\System32\shell32.dll,43"
    $sc.Description = "启动 Codex 汉化版（zh-CN）"
    $sc.Save()
    return $lnk
}

# ---------------- 旧副本清理 ----------------
function Get-StalePatchedRoots {
    param([string]$BaseDir, [string]$ActiveRoot)
    $stale = @()
    if (-not $BaseDir -or -not (Test-Path -LiteralPath $BaseDir)) { return $stale }
    foreach ($d in @(Get-ChildItem -LiteralPath $BaseDir -Directory -ErrorAction SilentlyContinue)) {
        $full = [System.IO.Path]::GetFullPath($d.FullName)
        $isActive = $false
        if ($ActiveRoot) {
            $isActive = $full.Equals([System.IO.Path]::GetFullPath($ActiveRoot), [System.StringComparison]::OrdinalIgnoreCase)
        }
        if (-not $isActive) { $stale += $full }
    }
    return $stale
}

# ---------------- 入口自动切换助手 ----------------
function Install-EntryGuard {
    $guard = Join-Path $toolHome "scripts\entry-guard.ps1"
    if (-not (Test-Path -LiteralPath $guard)) {
        Write-Warn "未找到入口助手脚本（entry-guard.ps1），跳过入口接管。"
        return
    }
    try {
        Stop-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "CodexZhCnEntryGuard" -Confirm:$false -ErrorAction SilentlyContinue
        Stop-EntryGuardProcesses
        # 优先使用 VBScript 隐藏启动器：计划任务直接启动 powershell 会在部分系统闪现命令行窗口
        $guardLauncher = Join-Path $toolHome "scripts\entry-guard-launcher.vbs"
        if (Test-Path -LiteralPath $guardLauncher) {
            $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ("`"" + $guardLauncher + "`"")
            Write-Log "入口助手任务使用隐藏启动器: wscript.exe $guardLauncher"
        } else {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"" + $guard + "`"")
        }
        # 触发器：登录自启 + Once(约 1 分钟后)每 5 分钟重复触发。
        # 若把 Repetition 挂到 LogonTrigger 上，登录会话中途注册时 NextRunTime 为空、自愈不生效；
        # 独立注册 Once+Repetition 触发器可确保注册后立即进入 5 分钟自愈节奏（配合单实例互斥）。
        $triggers = @()
        try {
            $triggers += New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        } catch {
            $triggers += New-ScheduledTaskTrigger -AtLogOn
        }
        try {
            $triggers += New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
        } catch {
            Write-Warn ("入口助手自愈触发配置失败（不影响登录自启）: " + $_.Exception.Message)
        }
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName "CodexZhCnEntryGuard" -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
        $guardLog = Join-Path (Join-Path $toolHome "logs") "entry-guard.log"
        $guardStarted = $false
        try {
            for ($attempt = 1; $attempt -le 2; $attempt++) {
                Start-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction Stop
                # 等待并验证助手确实在运行（日志出现启动行，且任务处于 Running）
                $before = if (Test-Path -LiteralPath $guardLog) { @(Get-Content -LiteralPath $guardLog -Encoding UTF8).Count } else { 0 }
                for ($i = 0; $i -lt 20; $i++) {
                    Start-Sleep -Milliseconds 500
                    $taskState = (Get-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue).State
                    $after = if (Test-Path -LiteralPath $guardLog) { @(Get-Content -LiteralPath $guardLog -Encoding UTF8).Count } else { 0 }
                    if ($taskState -eq "Running" -and $after -gt $before) { $guardStarted = $true; break }
                }
                if ($guardStarted) { break }
                Stop-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
            }
            if ($guardStarted) {
                Write-Ok "已安装并启动入口自动切换助手（登录自启、事件驱动、每 5 分钟自愈、不联网）。"
            } else {
                Write-Warn "入口助手已注册但本次启动未确认（自愈触发会在最多 5 分钟内自动拉起；若仍未生效，下次登录自动生效）。"
            }
        } catch {
            Write-Warn ("入口助手已注册但立即启动失败（下次登录自动生效）: " + $_.Exception.Message)
        }
        Write-Log "入口自动切换助手已安装"
    } catch {
        Write-Warn ("入口助手安装失败（不影响汉化本体）: " + $_.Exception.Message)
    }
}

function Stop-EntryGuardProcesses {
    try {
        $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq "powershell.exe" -and $_.CommandLine -match 'entry-guard\.ps1' })
        foreach ($p in $procs) {
            Write-Log ("正在结束残留的入口助手进程: PID " + $p.ProcessId)
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Remove-EntryGuard {
    # 顺序：先结束残留进程（避免任务 Running 导致 Unregister 失败）-> Stop -> Unregister -> 验证 -> schtasks 兜底
    Stop-EntryGuardProcesses
    $removed = $false
    try {
        Stop-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "CodexZhCnEntryGuard" -Confirm:$false -ErrorAction SilentlyContinue
        $removed = -not (Get-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue)
    } catch {
        Write-Warn ("移除入口助手任务失败: " + $_.Exception.Message)
    }
    if (-not $removed) {
        try {
            & schtasks.exe /Delete /TN "CodexZhCnEntryGuard" /F 2>$null | Out-Null
            $removed = -not (Get-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue)
        } catch {
            Write-Warn ("schtasks 删除入口助手任务失败: " + $_.Exception.Message)
        }
    }
    if ($removed) {
        Write-Ok "已移除入口自动切换助手。"
    } else {
        Write-Warn "入口助手计划任务仍存在（CodexZhCnEntryGuard），请以管理员身份重跑恢复/卸载，或手动执行：schtasks /Delete /TN CodexZhCnEntryGuard /F"
    }
}

# ---------------- 目录复制（robocopy：兼容新版 pnpm 超长路径 junction） ----------------
function Copy-AppDirectory {
    param([string]$Source, [string]$Destination)
    $src = $Source.TrimEnd('\')
    $dst = $Destination.TrimEnd('\')
    if (Test-Path -LiteralPath $dst) {
        Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    # robocopy 原生支持超长路径；/XJ 跳过 pnpm-store 等 junction 符号链接，
    # 避免 Copy-Item 遇到「未能找到路径的一部分」这类超长/重解析路径时报错。
    & robocopy.exe $src $dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XJ | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "COPY_FAILED: robocopy 复制失败（退出码 $LASTEXITCODE）$src -> $dst"
    }
}

# ---------------- locale-only 安装（受保护版本线） ----------------
function Start-OriginalCodex {
    try {
        $pkg2 = Get-AppxPackage -ErrorAction Stop | Where-Object { $_.Name -match 'Codex|OpenAI' } | Select-Object -First 1
        if ($pkg2) {
            $manifest = Get-AppxPackageManifest -Package $pkg2
            $appId = $manifest.Package.Applications.Application[0].Id
            Start-Process "explorer.exe" -ArgumentList "shell:AppsFolder\$($pkg2.PackageFamilyName)!$appId"
            return $true
        }
    } catch { Write-Log ("启动原版失败（shell 方式）: " + $_.Exception.Message) }
    return $false
}

function Install-ZhCnLocaleOnly {
    param([string]$CodexVersion, [string]$CodexAppDir)
    $script:installMode = "locale-only"
    # 清理旧补丁模式残留：入口助手任务/副本记录/桌面快捷方式
    Remove-EntryGuard
    if (Test-Path -LiteralPath $activeFile) { Remove-Item -LiteralPath $activeFile -Force -ErrorAction SilentlyContinue }
    $desktopL = [Environment]::GetFolderPath("Desktop")
    if (-not $desktopL) { $desktopL = Join-Path $env:USERPROFILE "Desktop" }
    foreach ($lnkName in @("Codex 汉化版.lnk", "Codex zh-CN.lnk")) {
        $lnk = Join-Path $desktopL $lnkName
        if (Test-Path $lnk) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue }
    }
    Write-Log "受保护版本线（$CodexVersion >= $script:localeOnlyFrom）：进入 locale-only 模式（不复制、不补丁、不装入口助手）"
    Write-Step "该 Codex 版本线受官方完整性保护（asar 不可改动），将采用 locale-only 模式：仅写入 localeOverride = zh-CN，界面中文由官方 i18n 提供（联网/服务端开启后生效）。"
    Set-LocaleOverrideZhCn
    Write-Ok "语言配置已设为 zh-CN。"
    Install-ToolFiles -SourceRoot $projectRoot
    Write-Ok "工具已安装到固定目录: $toolHome"
    $toolVersion = Get-ToolVersion
    Write-InstalledInfo -ToolVersion $toolVersion -CodexVersion $CodexVersion -PatchedDir "" -OrigDir $CodexAppDir -Mode "locale-only"
    Write-Step "正在重启原版 Codex（localeOverride 需重启生效）..."
    Stop-CodexProcesses
    if (Start-OriginalCodex) {
        Write-Ok "已启动原版 Codex（显示语言取决于官方 i18n，联网后通常自动为中文）。"
    } else {
        Write-Warn "请从开始菜单手动打开 Codex。"
    }
    Write-Log "locale-only 安装完成"
}

# ---------------- 安装 ----------------
function Install-ZhCn {
    param([string]$CodexAppDir)
    if (-not $CodexAppDir) { throw "CODEX_NOT_FOUND: 未找到 Codex Desktop，请确认已从 Microsoft Store 安装 Codex" }
    $asarPath = Join-Path $CodexAppDir "resources\app.asar"
    if (-not (Test-Path -LiteralPath $asarPath)) { throw "ASAR_NOT_FOUND: 目录中未找到 resources\app.asar：$CodexAppDir" }

    $codexVersion = Get-CodexVersion
    Write-Log "开始安装。Codex 版本: $codexVersion，安装目录: $CodexAppDir"

    if ($codexVersion -and (Test-LocaleOnlyVersion -Version $codexVersion)) {
        Install-ZhCnLocaleOnly -CodexVersion $codexVersion -CodexAppDir $CodexAppDir
        return
    }

    $origText = Read-AppInitialText -AsarPath $asarPath
    if ($null -eq $origText) { throw "ASAR_PARSE_FAILED: 无法解析 app.asar（app-initial 未找到）" }
    $markers = Resolve-Markers -Text $origText -CodexVersion $codexVersion
    if (-not $markers) {
        $diag = Save-Diagnostic -CodexVersion $codexVersion -Snippet (Get-SnippetFromText -Text $origText)
        Write-Log "版本结构无法识别，已生成诊断文件: $diag"
        throw "VERSION_UNSUPPORTED: 当前 Codex 版本的代码结构无法自动识别，请把诊断文件提交到仓库 issue：$diag"
    }
    if (-not (Get-TestedMarkers -CodexVersion $codexVersion -VersionsFile $versionsFile)) {
        Export-CandidateMarkers -CodexVersion $codexVersion -Markers $markers
    }
    $state = Get-I18nStateFromText -Text $origText -Markers $markers
    Write-Log "原版资源状态: $state"

    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $asarPath).Hash.Substring(0, 16).ToLowerInvariant()
    $patchedRoot = Join-Path $patchedBase $sha
    $patchedApp = Join-Path $patchedRoot "app"

    Stop-CodexProcesses

    # 判断是否需要重建：首次安装 / 缺 installed.json / 副本损坏 / Codex 版本变化
    $needRebuild = $true
    $installed = $null
    if (Test-Path -LiteralPath $installedFile) {
        try { $installed = Get-Content -Raw -Encoding UTF8 $installedFile | ConvertFrom-Json } catch { $installed = $null }
    }
    if (Test-Path -LiteralPath $patchedApp) {
        $pState = Get-AsarI18nState -AsarPath (Join-Path $patchedApp "resources\app.asar") -Markers $markers
        if ($pState -eq "patched" -and $installed -and [string]$installed.codexVersion -eq [string]$codexVersion) {
            $needRebuild = $false
        }
    }
    if ($needRebuild) {
        if (Test-Path -LiteralPath $patchedRoot) {
            Write-Warn "旧副本版本不匹配或未完成，将重新制作..."
            Remove-Item -LiteralPath $patchedRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $patchedRoot -Force | Out-Null
        Write-Step "正在复制 Codex 到汉化目录（需要 1-2 分钟，新版可能更久）..."
        Write-Log "复制 $CodexAppDir -> $patchedApp"
        Copy-AppDirectory -Source $CodexAppDir -Destination $patchedApp
        Write-Log "复制完成"
    } else {
        Write-Ok "已存在匹配版本的汉化副本，直接复用。"
    }

    Write-Step "正在开启中文界面开关..."
    Patch-AsarFile -AsarPath (Join-Path $patchedApp "resources\app.asar") -Markers $markers
    Write-Ok "中文界面开关已开启。"
    Write-Log "补丁完成"

    @($patchedRoot, $CodexAppDir) | Set-Content -LiteralPath $activeFile -Encoding UTF8
    Write-Ok "已记录汉化副本位置。"

    Set-LocaleOverrideZhCn
    Write-Ok "语言配置已设为 zh-CN。"

    Install-ToolFiles -SourceRoot $projectRoot
    Write-Ok "工具已安装到固定目录: $toolHome"

    $lnk = New-DesktopShortcut
    Write-Ok "已创建桌面快捷方式: $lnk"

    $toolVersion = Get-ToolVersion
    Write-InstalledInfo -ToolVersion $toolVersion -CodexVersion $codexVersion -PatchedDir $patchedRoot -OrigDir $CodexAppDir

    Write-Step "正在清理旧版本汉化副本..."
    $stale = @(Get-StalePatchedRoots -BaseDir $patchedBase -ActiveRoot $patchedRoot)
    if ($stale.Count -gt 0) {
        foreach ($s in $stale) {
            Write-Log "删除旧副本: $s"
            Remove-Item -LiteralPath $s -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "已删除旧副本: $s"
        }
    } else {
        Write-Info "无旧版本汉化副本需要清理。"
    }

    Install-EntryGuard

    Write-Step "安装完成！正在启动汉化版 Codex..."
    Start-Sleep -Milliseconds 800
    if (Test-Path -LiteralPath $launcher) {
        Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$launcher`"") -WindowStyle Hidden
        Write-Log "已调用过渡监督式启动脚本（结果见 launch-result.json）"
        Wait-LaunchThenFallback -CodexVersion $codexVersion
    }
    Write-Log "安装完成，已启动汉化版"
    if (-not (Test-LocaleOnlyVersion -Version $codexVersion)) {
        Write-Info "提示：建议运行菜单[7]（-Action freeze）关闭商店自动更新，防止升级到受保护版本（26.900+）后汉化失效。"
    }
}

# ---------------- 商店自动更新冻结（freeze / unfreeze） ----------------
function Get-StorePolicyAutoDownload {
    try {
        $v = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Store" -Name "AutoDownload" -ErrorAction Stop).AutoDownload
        return $v
    } catch { return $null }
}
function Test-StoreUpdatesFrozen {
    param($Value)
    return ($null -ne $Value -and ([int]$Value -eq 2))
}
function Set-StoreUpdatesFreeze {
    param([bool]$Freeze)
    $key = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Store"
    if ($Freeze) {
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name "AutoDownload" -Value 2 -PropertyType DWord -Force | Out-Null
    } else {
        if (Test-Path $key) { Remove-ItemProperty -Path $key -Name "AutoDownload" -ErrorAction SilentlyContinue }
    }
    return (Test-StoreUpdatesFrozen (Get-StorePolicyAutoDownload))
}
function Get-OfficialLocaleSince {
    param([string]$VersionsFileOverride = "")
    $file = if ($VersionsFileOverride) { $VersionsFileOverride } else { $versionsFile }
    try {
        if (Test-Path -LiteralPath $file) {
            $d = Get-Content -Raw -Encoding UTF8 $file | ConvertFrom-Json
            if ($d.officialLocaleSince) { return [string]$d.officialLocaleSince }
        }
    } catch {}
    return ""
}
function Show-StoreUpdateGuide {
    param([bool]$Frozen)
    Write-Host ""
    if ($Frozen) { Write-Ok "已关闭 Microsoft Store 自动更新（策略 AutoDownload=2）。" }
    else { Write-Ok "已恢复 Microsoft Store 自动更新（移除策略，跟随商店设置）。" }
    Write-Info "双保险：可到「Microsoft Store -> 设置 -> 关闭『自动更新应用』」。"
}
function Invoke-FreezeAction {
    param([bool]$Freeze)
    $ok = Set-StoreUpdatesFreeze -Freeze $Freeze
    if ($ok -eq $Freeze) { Show-StoreUpdateGuide -Frozen $Freeze }
    else { Write-Warn "设置未生效，请以管理员身份重试，或按提示在 Microsoft Store 设置中手动操作。" }
}

function Wait-LaunchThenFallback {
    param([string]$CodexVersion)
    $deadline = (Get-Date).AddSeconds(150)
    $status = ""
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 10
        if (Test-Path -LiteralPath $launchResultFile) {
            try {
                $j = Get-Content -Raw -Encoding UTF8 $launchResultFile | ConvertFrom-Json
                $status = [string]$j.status
            } catch {}
            if ($status) { break }
        }
    }
    if ($status -ne "ok") {
        Write-Warn "汉化版未能在预期时间内稳定运行（疑似受保护版本线），自动降级为 locale-only 模式..."
        Write-Log "监督启动未确认成功（status=$status），自动降级 locale-only"
        Remove-EntryGuard
        if (Test-Path -LiteralPath $activeFile) { Remove-Item -LiteralPath $activeFile -Force -ErrorAction SilentlyContinue }
        Stop-CodexProcesses
        Start-OriginalCodex | Out-Null
        $script:installMode = "locale-only"
        Write-Warn "已降级：仅 localeOverride（中文依赖官方 i18n），原版 Codex 已重启。"
    }
}

# ---------------- 卸载 ----------------
function Uninstall-ZhCn {
    Remove-EntryGuard
    Stop-CodexProcesses
    $removedRoot = $null
    $expectedBase = [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ".codex\zh-cn-patched"))
    if (Test-Path -LiteralPath $patchedBase) {
        $resolvedBase = [System.IO.Path]::GetFullPath($patchedBase)
        if ($resolvedBase.StartsWith($expectedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Step "正在删除全部汉化副本: $patchedBase"
            Remove-Item -LiteralPath $patchedBase -Recurse -Force
            $removedRoot = $patchedBase
        }
    }
    if (Test-Path -LiteralPath $activeFile) {
        Remove-Item -LiteralPath $activeFile -Force -ErrorAction SilentlyContinue
    }
    $configPath = Join-Path $env:USERPROFILE ".codex\config.toml"
    $bak = "$configPath.bak-zhcn"
    if (Test-Path $bak) {
        Copy-Item -LiteralPath $bak -Destination $configPath -Force
        Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
        Write-Ok "已恢复原始语言配置。"
    } elseif (Test-Path $configPath) {
        $content = [System.IO.File]::ReadAllText($configPath)
        $content = [regex]::Replace($content, '(?m)^[ \t]*localeOverride\s*=\s*(''|")[^''"]*\1[ \t]*(\r?\n|$)', "")
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($configPath, $content, $utf8NoBom)
        Write-Ok "已移除语言覆盖配置。"
    }
    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE "Desktop" }
    foreach ($lnkName in @("Codex 汉化版.lnk", "Codex zh-CN.lnk")) {
        $lnk = Join-Path $desktop $lnkName
        if (Test-Path $lnk) {
            Remove-Item -LiteralPath $lnk -Force
            Write-Ok "已删除桌面快捷方式: $lnk"
        }
    }
    if (Test-Path -LiteralPath $toolHome) {
        Write-Step "正在删除工具目录: $toolHome"
        Remove-Item -LiteralPath $toolHome -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($removedRoot) { Write-Ok "汉化副本已全部删除（原版未受影响）。" }
    Write-Step "卸载完成。请从开始菜单启动原版 Codex（英文）。"
}

# ---------------- 状态 / 验证 ----------------
function Show-Status {
    Write-Title
    $dir = Get-CodexAppDir -CustomPath $CodexPath
    if ($dir) {
        Write-Ok "Codex 安装目录: $dir"
        $ver = Get-CodexVersion
        if ($ver) { Write-Info "Codex 版本: $ver" }
        $s = Get-AsarI18nState -AsarPath (Join-Path $dir "resources\app.asar")
        Write-Info "原版资源状态: $s"
    } else {
        Write-Bad "未找到 Codex Desktop 安装目录"
    }
    if (Test-Path -LiteralPath $activeFile) {
        $lines = Get-Content -LiteralPath $activeFile | Where-Object { $_.Trim().Length -gt 0 }
        if ($lines.Count -ge 1) {
            $root = $lines[0].Trim()
            if (Test-Path (Join-Path $root "app")) {
                $s2 = Get-AsarI18nState -AsarPath (Join-Path $root "app\resources\app.asar")
                Write-Ok "汉化副本: $root （状态: $s2）"
            } else {
                Write-Warn "汉化副本记录存在，但文件夹缺失: $root"
            }
        }
    } else {
        Write-Info "尚未安装汉化副本。"
    }
    if (Test-Path -LiteralPath $installedFile) {
        try {
            $info = Get-Content -Raw -Encoding UTF8 $installedFile | ConvertFrom-Json
            Write-Info "工具版本: $($info.toolVersion)（安装于 $($info.installedAt)）"
            $modeShow = if ($info.mode) { $info.mode } else { "patch" }
            Write-Info "安装模式: $modeShow"
            $olSince = Get-OfficialLocaleSince
            if ($olSince) { Write-Info "官方本地语言确认自版本: $olSince（locale-only 已自动生效）" }
            else { Write-Info "官方本地语言：尚未确认（26.900+ 中文依赖服务端开关）" }
            $sv = Get-StorePolicyAutoDownload
            if (Test-StoreUpdatesFrozen $sv) { Write-Ok "商店自动更新：已关闭（汉化受保护）" }
            elseif ($null -eq $sv) { Write-Info "商店自动更新：未设置策略（跟随商店设置，可能自动升级）" }
            else { Write-Info "商店自动更新：策略值 $sv（未冻结）" }
        } catch { Write-Info "installed.json 无法解析。" }
    } else {
        Write-Info "尚未安装 v1.1 工具信息（installed.json 缺失）。"
    }
}

function Show-Verify {
    Write-Title
    $script:verifyOk = $true
    function Assert-VerifyItem([string]$Name, [bool]$Ok, [string]$Detail = "") {
        if ($Ok) { Write-Host "VERIFY: $Name=OK" -ForegroundColor Green }
        else { Write-Host "VERIFY: $Name=FAIL $Detail" -ForegroundColor Red; $script:verifyOk = $false }
    }

    $mode = "patch"
    try {
        if (Test-Path -LiteralPath $installedFile) {
            $mi = Get-Content -Raw -Encoding UTF8 $installedFile | ConvertFrom-Json
            if ($mi.mode) { $mode = [string]$mi.mode }
        }
    } catch {}
    Assert-VerifyItem "mode" ($mode -in @("patch","locale-only")) "未知模式: $mode"

    $cfgOk = $false
    $cfgPath = Join-Path $env:USERPROFILE ".codex\config.toml"
    if (Test-Path $cfgPath) {
        $cfgContent = Get-Content -Raw $cfgPath
        $cfgOk = $cfgContent -match 'localeOverride\s*=\s*"zh-CN"'
    }
    Assert-VerifyItem "config-locale" $cfgOk $cfgPath

    if ($mode -eq "locale-only") {
        $procsLO = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' })
        $origOk = $true
        if ($procsLO.Count -gt 0) {
            $badLO = @($procsLO | Where-Object { $_.Path -and -not $_.Path.StartsWith("C:\Program Files\WindowsApps", [System.StringComparison]::OrdinalIgnoreCase) })
            $origOk = $badLO.Count -eq 0
        }
        Assert-VerifyItem "processes-from-original" $origOk "检测到非原版进程"
        Write-Host "VERIFY: locale-note=中文由官方 i18n 提供，国内网络下可能仍为英文" -ForegroundColor DarkGray
    } else {
        $patchedRoot = ""
        $activeOk = $false
        if (Test-Path -LiteralPath $activeFile) {
            $lines = @(Get-Content -LiteralPath $activeFile -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 })
            if ($lines.Count -ge 1) {
                $patchedRoot = $lines[0].Trim()
                $activeOk = Test-Path (Join-Path $patchedRoot "app\resources\app.asar")
            }
        }
        Assert-VerifyItem "patched-copy" $activeOk "汉化副本缺失: $activeFile"

        $asarOk = $false
        if ($activeOk) { $asarOk = ((Get-AsarI18nState -AsarPath (Join-Path $patchedRoot "app\resources\app.asar")) -eq "patched") }
        Assert-VerifyItem "asar-patched" $asarOk "汉化副本 app.asar 未处于 patched 状态"

    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE "Desktop" }
    $lnkOk = (Test-Path (Join-Path $desktop "Codex 汉化版.lnk")) -or (Test-Path (Join-Path $desktop "Codex zh-CN.lnk"))
    Assert-VerifyItem "desktop-shortcut" $lnkOk "桌面快捷方式缺失"

    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' })
    $procOk = $true
    if ($procs.Count -gt 0) {
        if ($activeOk) {
            $prefix = (Join-Path $patchedRoot "app")
            $bad = @($procs | Where-Object { $_.Path -and -not $_.Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
            $procOk = $bad.Count -eq 0
        } else {
            $procOk = $false
        }
    }
    Assert-VerifyItem "processes-from-patched" $procOk "检测到非汉化副本进程"

    $launchOk = $true
    $launchDetail = ""
    if (Test-Path -LiteralPath $launchResultFile) {
        try {
            $lr = Get-Content -Raw -Encoding UTF8 $launchResultFile | ConvertFrom-Json
            $launchOk = ([string]$lr.status -eq "ok")
            if (-not $launchOk) { $launchDetail = "最近一次启动汉化版失败: code=$($lr.code)（见 launch-result.json）" }
        } catch {
            $launchOk = $false
            $launchDetail = "launch-result.json 无法解析"
        }
    }
    Assert-VerifyItem "last-launch" $launchOk $launchDetail

    $guardOk = $false
    $guardDetail = "入口助手任务缺失（CodexZhCnEntryGuard）"
    try {
        $gt = Get-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue
        if ($gt) {
            $state = [string]$gt.State
            $guardOk = ($state -in @("Ready", "Running", "Queued"))
            if (-not $guardOk) { $guardDetail = "入口助手任务状态异常: $state" }
        }
    } catch {
        $guardOk = $false
        $guardDetail = "无法读取入口助手任务: " + $_.Exception.Message
    }
    Assert-VerifyItem "guard-task" $guardOk $guardDetail
    }

    if ($script:verifyOk) { Write-Host "VERIFY: OVERALL=OK" -ForegroundColor Green; return $true }
    Write-Host "VERIFY: OVERALL=FAIL" -ForegroundColor Red
    return $false
}

# ---------------- 菜单 ----------------
function Start-Menu {
    Ensure-Administrator
    while ($true) {
        Clear-Host
        Write-Title
        Write-Host ""
        Write-Host "  请选择操作："
        Write-Host ""
        Write-Host "    [1] 安装汉化（复制 + 开启中文 + 建桌面快捷方式）"
        Write-Host "    [2] 检查当前汉化状态"
        Write-Host "    [3] 启动汉化版 Codex"
        Write-Host "    [4] 恢复英文原版"
        Write-Host "    [5] 卸载汉化（删除汉化副本、恢复原配置）"
        Write-Host "    [6] 检查更新（联网，可选功能）"
        Write-Host "    [7] 阻止商店自动更新（保护老版本汉化）"
        Write-Host "    [8] 恢复商店自动更新"
        Write-Host "    [9] 退出"
        Write-Host ""
        $choice = Read-Host "  请输入数字后回车"
        switch ($choice) {
            "1" {
                Clear-Host
                Write-Title
                Write-Step "【安装汉化】"
                try {
                    Install-ZhCn -CodexAppDir (Get-CodexAppDir -CustomPath $CodexPath)
                    Write-Ok "全部完成！"
                } catch {
                    Write-Bad $_.Exception.Message
                }
                if (-not $NoPause) { Read-Host "按 Enter 返回菜单" | Out-Null }
            }
            "2" {
                Clear-Host
                Show-Status
                if (-not $NoPause) { Read-Host "按 Enter 返回菜单" | Out-Null }
            }
            "3" {
                if (Test-Path -LiteralPath $launcher) {
                    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$launcher`"") -WindowStyle Hidden
                }
                Write-Ok "已在后台启动汉化版 Codex。"
                if (-not $NoPause) { Read-Host "按 Enter 返回菜单" | Out-Null }
            }
            "4" {
                Clear-Host
                Write-Step "【恢复英文原版】"
                try {
                    Remove-EntryGuard
                    Stop-CodexProcesses
                    Write-Info "请从开始菜单中打开 Codex（原版，英文界面）。"
                } catch {
                    Write-Bad $_.Exception.Message
                }
                if (-not $NoPause) { Read-Host "按 Enter 返回菜单" | Out-Null }
            }
            "5" {
                Clear-Host
                Write-Title
                Write-Step "【卸载汉化】"
                $confirm = Read-Host "确认删除汉化副本并恢复英文？(输入 y 确认)"
                if ($confirm -match '^[yY]$') {
                    try { Uninstall-ZhCn } catch { Write-Bad $_.Exception.Message }
                } else {
                    Write-Info "已取消。"
                }
                if (-not $NoPause) { Read-Host "按 Enter 返回菜单" | Out-Null }
            }
            "6" {
                Clear-Host
                Write-Title
                Write-Step "【检查更新（联网）】"
                $updater = Join-Path $scriptDir "check-update.ps1"
                if (Test-Path -LiteralPath $updater) { & $updater -NoPause } else { Write-Bad "未找到 check-update.ps1" }
                if (-not $NoPause) { Read-Host "按 Enter 返回菜单" | Out-Null }
            }
            "7" {
                Clear-Host
                Write-Title
                Write-Step "【阻止商店自动更新】"
                Invoke-FreezeAction -Freeze $true
                if (-not $NoPause) { Read-Host "按 Enter 返回菜单" | Out-Null }
            }
            "8" {
                Clear-Host
                Write-Title
                Write-Step "【恢复商店自动更新】"
                Invoke-FreezeAction -Freeze $false
                if (-not $NoPause) { Read-Host "按 Enter 返回菜单" | Out-Null }
            }
            "9" { return }
            default { Write-Warn "无效输入，请重新选择。"; Start-Sleep -Seconds 1 }
        }
    }
}

# ---------------- 入口 ----------------
function Invoke-Main {
    switch ($Action) {
        "menu" { Start-Menu }
        "install" {
            if (-not (Test-IsAdministrator)) {
                Write-ResultFile -Status "pending" -CodexVersion (Get-CodexVersion)
                Ensure-Administrator
            } else {
                try {
                    Write-ResultFile -Status "pending" -CodexVersion (Get-CodexVersion)
                    Install-ZhCn -CodexAppDir (Get-CodexAppDir -CustomPath $CodexPath)
                    Write-Host "RESULT: INSTALL_OK"
                    $patched = ""
                    if (Test-Path -LiteralPath $activeFile) {
                        $lines = @(Get-Content -LiteralPath $activeFile | Where-Object { $_.Trim().Length -gt 0 })
                        if ($lines.Count -ge 1) { $patched = $lines[0].Trim() }
                    }
                    Write-ResultFile -Status "ok" -Code "INSTALL_OK" -CodexVersion (Get-CodexVersion) -PatchedDir $patched -LaunchResultFile $launchResultFile -Mode $script:installMode
                } catch {
                    $msg = $_.Exception.Message
                    $code = if ($msg -match '^([A-Z][A-Z_]+): ') { $matches[1] } else { "UNKNOWN" }
                    Write-Bad $msg
                    Write-Log "安装失败: $code - $msg"
                    Write-Host "RESULT: INSTALL_FAIL"
                    $diag = ""
                    if ($code -eq "VERSION_UNSUPPORTED") {
                        $diagFile = Get-ChildItem -Path $logDir -Filter "diagnostic-*.txt" -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($diagFile) { $diag = $diagFile.FullName }
                    }
                    Write-ResultFile -Status "fail" -Code $code -Message $msg -CodexVersion (Get-CodexVersion) -DiagFile $diag
                    if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
                    exit 1
                }
            }
        }
        "verify" {
            if (-not (Show-Verify)) {
                if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
                exit 1
            }
        }
        "status" { Show-Status }
        "check-update" {
            $updater = Join-Path $scriptDir "check-update.ps1"
            if (Test-Path -LiteralPath $updater) { & $updater } else { Write-Bad "未找到 check-update.ps1"; exit 1 }
        }
        "test" {
            $t = Join-Path $scriptDir "tests\tests.ps1"
            if (Test-Path -LiteralPath $t) { & $t } else { Write-Bad "未找到 tests\tests.ps1"; exit 1 }
        }
        "freeze" {
            Ensure-Administrator
            Invoke-FreezeAction -Freeze $true
            if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
        }
        "unfreeze" {
            Ensure-Administrator
            Invoke-FreezeAction -Freeze $false
            if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
        }
        "uninstall" {
            if (-not $Force) {
                $confirm = Read-Host "确认删除汉化副本并恢复英文？(输入 y 确认)"
                if ($confirm -notmatch '^[yY]$') {
                    Write-Info "已取消。"
                    if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
                    exit 0
                }
            }
            Ensure-Administrator
            try { Uninstall-ZhCn } catch {
                Write-Bad $_.Exception.Message
                if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
                exit 1
            }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main
}
if (-not $NoPause -and $MyInvocation.InvocationName -ne '.') {
    Write-Host ""
    Read-Host "按 Enter 退出" | Out-Null
}
