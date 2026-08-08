#requires -version 5.1
<#
  Codex Desktop 一键汉化安装器（Windows / Microsoft Store 版）
  用法：powershell -ExecutionPolicy Bypass -File install-zh-cn.ps1 [-Action menu|install|uninstall|status] [-CodexPath "路径"]
#>
param(
    [ValidateSet("menu","install","uninstall","status")]
    [string]$Action = "menu",
    [string]$CodexPath = "",
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptDir
$launcher = Join-Path $scriptDir "launch-zh-cn.ps1"
$activeFile = Join-Path $env:USERPROFILE ".codex\zh-cn-patched-active.txt"
$patchedBase = Join-Path $env:USERPROFILE ".codex\zh-cn-patched"

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

function Stop-CodexProcesses {
    Write-Step "正在关闭 Codex 相关进程（防止冲突）..."
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# ---------------- 查找 Codex ----------------
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
            Sort-Object { [version]$_.Version } -Descending |
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
    return $null
}

# ---------------- asar 补丁（等长字节替换，不改 asar 结构） ----------------
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

function Get-AsarI18nState {
    param([string]$AsarPath)
    if (-not (Test-Path $AsarPath)) { return "missing" }
    $info = Get-AppInitialInfo -AsarPath $AsarPath
    if (-not $info) { return "unsupported" }
    $fs = [System.IO.File]::OpenRead($AsarPath)
    try {
        $start = 16 + $info.HeaderSize + $info.Offset
        $buf = New-Object byte[] $info.Size
        $fs.Position = $start
        [void]$fs.Read($buf, 0, $buf.Length)
        $enc = [System.Text.Encoding]::GetEncoding(28591)
        $text = $enc.GetString($buf)
        if ($text.Contains('enable_i18n`,!0)') -and $text.Contains('let s=1,c=a?.get(`')) { return "patched" }
        if ($text.Contains('enable_i18n`,!1)') -or $text.Contains('let s=o,c=a?.get(`')) { return "original" }
        return "unsupported"
    } finally { $fs.Dispose() }
}

function Patch-AsarEnableI18n {
    param([string]$AsarPath)
    $state = Get-AsarI18nState -AsarPath $AsarPath
    if ($state -eq "patched") { return $true }
    if ($state -eq "unsupported") {
        $info = Get-AppInitialInfo -AsarPath $AsarPath
        $snippet = ""
        if ($info) {
            $fs = [System.IO.File]::OpenRead($AsarPath)
            try {
                $start = 16 + $info.HeaderSize + $info.Offset
                $buf = New-Object byte[] $info.Size
                $fs.Position = $start
                [void]$fs.Read($buf, 0, $buf.Length)
                $enc = [System.Text.Encoding]::GetEncoding(28591)
                $text = $enc.GetString($buf)
                $i = $text.IndexOf('enable_i18n')
                if ($i -ge 0) {
                    $from = [Math]::Max(0, $i - 40)
                    $len = [Math]::Min(120, $text.Length - $from)
                    $snippet = $text.Substring($from, $len)
                }
            } finally { $fs.Dispose() }
        }
        throw "当前 Codex 版本的代码结构无法自动识别，请稍后重试或联系维护者。`n文件: $($info.Name)`n片段: $snippet"
    }
    $info = Get-AppInitialInfo -AsarPath $AsarPath
    if (-not $info) { throw "无法解析 app.asar" }
    $fs = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
    try {
        $start = 16 + $info.HeaderSize + $info.Offset
        $buf = New-Object byte[] $info.Size
        $fs.Position = $start
        [void]$fs.Read($buf, 0, $buf.Length)
        $enc = [System.Text.Encoding]::GetEncoding(28591)
        $text = $enc.GetString($buf)
        $from1 = 'enable_i18n`,!1)'
        $to1   = 'enable_i18n`,!0)'
        $from2 = 'let s=o,c=a?.get(`'
        $to2   = 'let s=1,c=a?.get(`'
        $changed = $false
        if ($text.Contains($from1)) { $text = $text.Replace($from1, $to1); $changed = $true }
        if ($text.Contains($from2)) { $text = $text.Replace($from2, $to2); $changed = $true }
        if (-not $changed) { throw "未找到需要修改的内容，请确认原版未改动" }
        $newBytes = $enc.GetBytes($text)
        if ($newBytes.Length -ne $buf.Length) { throw "补丁后长度变化，已中止" }
        $fs.Position = $start
        $fs.Write($newBytes, 0, $newBytes.Length)
        $fs.Flush($true)
        return $true
    } finally { $fs.Dispose() }
}

# ---------------- 语言配置 ----------------
function Set-LocaleOverrideZhCn {
    $configPath = Join-Path $env:USERPROFILE ".codex\config.toml"
    $dir = Split-Path -Parent $configPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $content = ""
    if (Test-Path $configPath) { $content = [System.IO.File]::ReadAllText($configPath) }
    $bak = "$configPath.bak-zhcn"
    if ((Test-Path $configPath) -and (-not (Test-Path $bak))) {
        Copy-Item -LiteralPath $configPath -Destination $bak -Force
        Write-Info "已备份原配置: $bak"
    }
    if ($content -match 'localeOverride\s*=\s*"[^"]*"') {
        $content = [regex]::Replace($content, 'localeOverride\s*=\s*"[^"]*"', 'localeOverride = "zh-CN"')
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

# ---------------- 桌面快捷方式 ----------------
function New-DesktopShortcut {
    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE "Desktop" }
    $lnk = Join-Path $desktop "Codex 汉化版.lnk"
    $ps = Join-Path $scriptDir "launch-zh-cn.ps1"
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = "powershell.exe"
    $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps`""
    $sc.WorkingDirectory = $projectRoot
    $sc.IconLocation = "$env:WINDIR\System32\shell32.dll,43"
    $sc.Description = "启动 Codex 汉化版（zh-CN）"
    $sc.Save()
    return $lnk
}

# ---------------- 安装 ----------------
function Install-ZhCn {
    param([string]$CodexAppDir)
    if (-not $CodexAppDir) { throw "未找到 Codex Desktop，请确认已从 Microsoft Store 安装 Codex" }
    $asarPath = Join-Path $CodexAppDir "resources\app.asar"
    if (-not (Test-Path $asarPath)) { throw "目录中未找到 resources\app.asar：$CodexAppDir" }

    $state = Get-AsarI18nState -AsarPath $asarPath
    Write-Info "检测到 Codex 安装目录: $CodexAppDir"
    Write-Info "原版状态: $state"
    if ($state -ne "original" -and $state -ne "patched") {
        throw "此版本暂时无法自动汉化（结构不识别），请稍后重试或联系维护者。"
    }

    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $asarPath).Hash.Substring(0, 16).ToLowerInvariant()
    $patchedRoot = Join-Path $patchedBase $sha
    $patchedApp = Join-Path $patchedRoot "app"

    Stop-CodexProcesses

    if (Test-Path $patchedApp) {
        $pState = Get-AsarI18nState -AsarPath (Join-Path $patchedApp "resources\app.asar")
        if ($pState -eq "patched") {
            Write-Ok "已存在汉化副本，直接复用。"
        } else {
            Write-Warn "旧副本未完成汉化，将重新制作..."
            Remove-Item -LiteralPath $patchedApp -Recurse -Force
            New-Item -ItemType Directory -Path $patchedRoot -Force | Out-Null
            Write-Step "正在复制 Codex 到汉化目录（需要 1-2 分钟）..."
            Copy-Item -LiteralPath $CodexAppDir -Destination $patchedApp -Recurse -Force
        }
    } else {
        New-Item -ItemType Directory -Path $patchedRoot -Force | Out-Null
        Write-Step "正在复制 Codex 到汉化目录（需要 1-2 分钟）..."
        Copy-Item -LiteralPath $CodexAppDir -Destination $patchedApp -Recurse -Force
    }

    Write-Step "正在开启中文界面开关..."
    Patch-AsarEnableI18n -AsarPath (Join-Path $patchedApp "resources\app.asar")
    Write-Ok "中文界面开关已开启。"

    @($patchedRoot, $CodexAppDir) | Set-Content -LiteralPath $activeFile -Encoding UTF8
    Write-Ok "已记录汉化副本位置。"

    Set-LocaleOverrideZhCn
    Write-Ok "语言配置已设为 zh-CN。"

    $lnk = New-DesktopShortcut
    Write-Ok "已创建桌面快捷方式: $lnk"

    Write-Step "安装完成！正在启动汉化版 Codex..."
    Start-Sleep -Milliseconds 800
    if (Test-Path $launcher) {
        Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$launcher`"") -WindowStyle Hidden
    }
}

# ---------------- 卸载 ----------------
function Uninstall-ZhCn {
    Stop-CodexProcesses
    $removedRoot = $null
    if (Test-Path $activeFile) {
        $lines = Get-Content -LiteralPath $activeFile | Where-Object { $_.Trim().Length -gt 0 }
        if ($lines.Count -ge 1) {
            $root = $lines[0].Trim()
            $expectedBase = (Join-Path $env:USERPROFILE ".codex\zh-cn-patched")
            if ($root.StartsWith($expectedBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $root)) {
                Write-Step "正在删除汉化副本: $root"
                Remove-Item -LiteralPath $root -Recurse -Force
                $removedRoot = $root
            }
        }
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
        $content = [regex]::Replace($content, '(?m)^\s*localeOverride\s*=\s*"[^"]*"\s*\r?\n', "")
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($configPath, $content, $utf8NoBom)
        Write-Ok "已移除语言覆盖配置。"
    }
    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE "Desktop" }
    $lnk = Join-Path $desktop "Codex 汉化版.lnk"
    if (Test-Path $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Ok "已删除桌面快捷方式。" }
    if ($removedRoot) { Write-Ok "汉化副本已删除（原版未受影响）。" }
    Write-Step "卸载完成。请从开始菜单启动原版 Codex（英文）。"
}

# ---------------- 状态 ----------------
function Show-Status {
    Write-Title
    $dir = Get-CodexAppDir -CustomPath $CodexPath
    if ($dir) {
        Write-Ok "Codex 安装目录: $dir"
        $s = Get-AsarI18nState -AsarPath (Join-Path $dir "resources\app.asar")
        Write-Info "原版资源状态: $s"
    } else {
        Write-Bad "未找到 Codex Desktop 安装目录"
    }
    if (Test-Path $activeFile) {
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
        Write-Host "    [6] 退出"
        Write-Host ""
        $choice = Read-Host "  请输入数字后回车"
        switch ($choice) {
            "1" {
                Clear-Host
                Write-Title
                Write-Step "【安装汉化】"
                try {
                    $dir = Get-CodexAppDir -CustomPath $CodexPath
                    Install-ZhCn -CodexAppDir $dir
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
                if (Test-Path $launcher) {
                    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$launcher`"") -WindowStyle Hidden
                }
                Write-Ok "已在后台启动汉化版 Codex。"
                if (-not $NoPause) { Read-Host "按 Enter 返回菜单" | Out-Null }
            }
            "4" {
                Clear-Host
                Write-Step "【恢复英文原版】"
                try {
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
            "6" { return }
            default { Write-Warn "无效输入，请重新选择。"; Start-Sleep -Seconds 1 }
        }
    }
}

# ---------------- 入口 ----------------
switch ($Action) {
    "menu"    { Start-Menu }
    "install" {
        Ensure-Administrator
        try {
            Install-ZhCn -CodexAppDir (Get-CodexAppDir -CustomPath $CodexPath)
            Write-Host "RESULT: INSTALL_OK"
        } catch {
            Write-Bad $_.Exception.Message
            Write-Host "RESULT: INSTALL_FAIL"
            if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null }
            exit 1
        }
    }
    "uninstall" { Ensure-Administrator; try { Uninstall-ZhCn } catch { Write-Bad $_.Exception.Message; if (-not $NoPause) { Read-Host "按 Enter 退出" | Out-Null } ; exit 1 } }
    "status"  { Show-Status }
}
if (-not $NoPause) { Write-Host ""; Read-Host "按 Enter 退出" | Out-Null }