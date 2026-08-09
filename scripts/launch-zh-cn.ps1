#requires -version 5.1
<#
  启动 Codex 汉化版（zh-CN）— 过渡监督式重启 v1.3

  说明：
  - 读取汉化副本记录（%USERPROFILE%\.codex\zh-cn-patched-active.txt）。
  - 若汉化版已在运行且无原版进程，直接成功退出（不打扰正在使用的窗口）。
  - 否则执行过渡监督式重启：优雅关闭旧进程（超时再强杀）→
    以普通用户权限启动汉化副本（提升环境下通过一次性受限计划任务启动，
    避免权限差异导致启动不稳定）→ 轮询验证汉化副本稳定运行且无原版进程，
    验证通过立即退出（上限默认 60 秒，失败自动重试一次）。
  - 非驻留：不创建开机任务、不常驻后台；结束后仅保留日志与结果文件。
  - 日志：%USERPROFILE%\.codex\zh-cn-agent\logs\launch-*.log
    结果：%USERPROFILE%\.codex\zh-cn-agent\launch-result.json
#>
param(
    [int]$TimeoutSec = 60,
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$userProfile = $env:USERPROFILE
$activeFile = Join-Path $userProfile ".codex\zh-cn-patched-active.txt"
$toolHome = Join-Path $userProfile ".codex\zh-cn-agent"
$logDir = Join-Path $toolHome "logs"
$resultFile = Join-Path $toolHome "launch-result.json"
$script:logFile = ""
$script:patchedAppDir = ""
$script:attempts = 0

function Write-LogLine {
    param([string]$Message)
    try {
        if (-not $script:logFile) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            $script:logFile = Join-Path $logDir ("launch-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
        }
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $script:logFile -Value $line -Encoding UTF8
    } catch {}
}

function Show-Error([string]$Message) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($Message, 0, "Codex 汉化版", 16)
    } catch {
        Write-Host $Message -ForegroundColor Red
    }
}

function Test-IsAdministrator {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------- 纯逻辑（可离线测试） ----------------

function Get-ProcessKind {
    param([string]$Path, [string]$PatchedAppDir)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "unknown" }
    if ([string]::IsNullOrWhiteSpace($PatchedAppDir)) { return "original" }
    if ($Path.StartsWith($PatchedAppDir, [System.StringComparison]::OrdinalIgnoreCase)) { return "patched" }
    return "original"
}

function Get-GuardAction {
    param([int]$Patched, [int]$NonPatched)
    if ($Patched -gt 0 -and $NonPatched -eq 0) { return "ok" }
    if ($NonPatched -gt 0) { return "close" }
    return "start"
}

function Resolve-LaunchPaths {
    param([string]$ActiveFileOverride = "")
    $file = if ($ActiveFileOverride) { $ActiveFileOverride } else { $activeFile }
    if (-not (Test-Path -LiteralPath $file)) {
        throw "NOT_INSTALLED: 尚未安装汉化，请先运行「安装汉化.bat」完成汉化安装。"
    }
    $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 })
    if ($lines.Count -lt 1) {
        throw "ACTIVE_FILE_EMPTY: 汉化记录为空，请重新运行「安装汉化.bat」。"
    }
    $patchedRoot = $lines[0].Trim()
    $appDir = Join-Path $patchedRoot "app"
    $exePath = Join-Path $appDir "ChatGPT.exe"
    if (-not (Test-Path -LiteralPath $exePath)) { $exePath = Join-Path $appDir "Codex.exe" }
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "EXE_NOT_FOUND: 汉化副本中未找到启动程序：$appDir`n请重新运行「安装汉化.bat」。"
    }
    return [pscustomobject]@{ PatchedRoot = $patchedRoot; AppDir = $appDir; ExePath = $exePath }
}

function Write-LaunchResult {
    param(
        [string]$Status,
        [string]$Code,
        [string]$Message = "",
        [string]$PatchedDir = "",
        [int]$Attempts = 0,
        [string]$LogFile = "",
        [string]$ResultFileOverride = ""
    )
    try {
        $file = if ($ResultFileOverride) { $ResultFileOverride } else { $resultFile }
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
        $obj = [ordered]@{
            status     = $Status
            code       = $Code
            message    = $Message
            patchedDir = $PatchedDir
            attempts   = $Attempts
            logFile    = $LogFile
            updatedAt  = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fff")
        }
        [System.IO.File]::WriteAllText($file, ($obj | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        Write-LogLine "已写结果文件: $file (status=$Status, code=$Code)"
    } catch {
        Write-LogLine "无法写入结果文件: $_"
    }
}

# ---------------- 进程操作 ----------------

function Get-CodexProcessInfo {
    $patched = @()
    $nonPatched = @()
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' } |
        ForEach-Object {
            $path = $null
            try { $path = $_.Path } catch {}
            if ([string]::IsNullOrWhiteSpace($path)) {
                try { $path = $_.MainModule.FileName } catch {}
            }
            $kind = Get-ProcessKind -Path $path -PatchedAppDir $script:patchedAppDir
            if ($kind -eq "patched") { $patched += $_ } else { $nonPatched += $_ }
        }
    return [pscustomobject]@{ Patched = @($patched); NonPatched = @($nonPatched) }
}

function Stop-OnlyNonPatched {
    param($ProcessList)
    foreach ($p in $ProcessList) {
        try { $p.Refresh() } catch {}
        try { if ($p.HasExited) { continue } } catch {}
        Write-LogLine ("关闭进程: {0} pid={1}" -f $p.ProcessName, $p.Id)
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
}

function Close-NonPatchedGracefully {
    param($ProcessList)
    $graceful = @($ProcessList | Where-Object { try { $_.MainWindowHandle -ne 0 } catch { $false } })
    foreach ($p in $graceful) {
        Write-LogLine ("请求优雅关闭: {0} pid={1}" -f $p.ProcessName, $p.Id)
        try { [void]$p.CloseMainWindow() } catch {}
    }
    if ($graceful.Count -gt 0) {
        $deadline = (Get-Date).AddSeconds(6)
        while ((Get-Date) -lt $deadline) {
            $alive = @($graceful | Where-Object { try { -not $_.HasExited } catch { $true } })
            if ($alive.Count -eq 0) { break }
            Start-Sleep -Milliseconds 300
        }
    }
    $still = @($ProcessList | Where-Object { try { -not $_.HasExited } catch { $true } })
    Stop-OnlyNonPatched -ProcessList $still
    Start-Sleep -Seconds 2
}

function Start-PatchedApp {
    param($Paths)
    if (-not (Test-IsAdministrator)) {
        Write-LogLine ("以当前用户权限启动: {0}" -f $Paths.ExePath)
        Start-Process -FilePath $Paths.ExePath -WorkingDirectory $Paths.AppDir | Out-Null
        return
    }
    $taskName = "CodexZhLaunch_" + [guid]::NewGuid().ToString("N")
    $registered = $false
    try {
        $action = New-ScheduledTaskAction -Execute $Paths.ExePath -WorkingDirectory $Paths.AppDir
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        $task = New-ScheduledTask -Action $action -Principal $principal
        Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
        $registered = $true
        Write-LogLine ("通过一次性受限计划任务启动（任务: {0}）" -f $taskName)
        Start-ScheduledTask -TaskName $taskName
        Start-Sleep -Seconds 2
    } catch {
        Write-LogLine ("受限计划任务方式失败，回退为直接启动: {0}" -f $_.Exception.Message)
        Start-Process -FilePath $Paths.ExePath -WorkingDirectory $Paths.AppDir | Out-Null
    } finally {
        if ($registered) {
            try {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                Write-LogLine ("已清理一次性计划任务: {0}" -f $taskName)
            } catch {}
        }
    }
}

function Ensure-EntryGuardRunning {
    try {
        Start-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue
        Write-LogLine "已确保入口自动切换助手在运行。"
    } catch {
        Write-LogLine ("入口助手启动失败（不影响本次启动）: " + $_.Exception.Message)
    }
}

# ---------------- 监督式重启 ----------------

function Invoke-SupervisedLaunch {
    param($Paths)
    $script:attempts = 0
    while ($script:attempts -lt 2) {
        $script:attempts++
        Write-LogLine ("=== 第 {0} 次尝试开始 ===" -f $script:attempts)

        $info = Get-CodexProcessInfo
        if ($info.NonPatched.Count -gt 0) {
            Write-LogLine ("发现非汉化进程 {0} 个，准备关闭..." -f $info.NonPatched.Count)
            Close-NonPatchedGracefully -ProcessList $info.NonPatched
        } else {
            Write-LogLine "未发现需要关闭的进程。"
        }

        Start-PatchedApp -Paths $Paths
        $lastStart = Get-Date

        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        $poll = 0
        while ((Get-Date) -lt $deadline) {
            $poll++
            Start-Sleep -Seconds 2
            $info = Get-CodexProcessInfo
            $action = Get-GuardAction -Patched $info.Patched.Count -NonPatched $info.NonPatched.Count
            Write-LogLine ("poll#{0}: patched={1} nonpatched={2} action={3}" -f $poll, $info.Patched.Count, $info.NonPatched.Count, $action)
            if ($action -eq "ok") {
                Write-LogLine "汉化版已稳定运行（patched 进程数: $($info.Patched.Count)）。"
                return $true
            }
            if ($action -eq "close") {
                Stop-OnlyNonPatched -ProcessList $info.NonPatched
            } elseif ($action -eq "start" -and ((Get-Date) - $lastStart).TotalSeconds -ge 10) {
                Write-LogLine "汉化副本尚未出现，重新启动。"
                Start-PatchedApp -Paths $Paths
                $lastStart = Get-Date
            }
        }
        Write-LogLine ("第 {0} 次尝试在 {1} 秒内未达到稳定状态。" -f $script:attempts, $TimeoutSec)
    }
    return $false
}

# ---------------- 入口 ----------------

function Invoke-Main {
    $paths = $null
    try {
        $paths = Resolve-LaunchPaths
        $script:patchedAppDir = $paths.AppDir
    } catch {
        $msg = $_.Exception.Message
        Write-LogLine "启动失败: $msg"
        $code = if ($msg -match '^([A-Z][A-Z_]+): ') { $matches[1] } else { "LAUNCH_FAILED" }
        Write-LaunchResult -Status "fail" -Code $code -Message $msg -LogFile $script:logFile
        Show-Error $msg
        exit 1
    }

    try {
        $info = Get-CodexProcessInfo
        if (-not $Force -and $info.Patched.Count -gt 0 -and $info.NonPatched.Count -eq 0) {
            Write-LogLine ("汉化版已在运行（{0} 个进程），无需重启。" -f $info.Patched.Count)
            Write-LaunchResult -Status "ok" -Code "ALREADY_RUNNING" -PatchedDir $paths.PatchedRoot -LogFile $script:logFile
            Ensure-EntryGuardRunning
            exit 0
        }

        $ok = Invoke-SupervisedLaunch -Paths $paths
        if ($ok) {
            Write-LaunchResult -Status "ok" -Code "LAUNCH_OK" -PatchedDir $paths.PatchedRoot -Attempts $script:attempts -LogFile $script:logFile
            Ensure-EntryGuardRunning
            exit 0
        }

        $msg = "汉化版未能在 $TimeoutSec 秒内稳定运行（已自动重试）。`n日志: $($script:logFile)"
        Write-LogLine "最终失败: $msg"
        Write-LaunchResult -Status "fail" -Code "LAUNCH_FAILED" -Message $msg -PatchedDir $paths.PatchedRoot -Attempts $script:attempts -LogFile $script:logFile
        Show-Error $msg
        exit 1
    } catch {
        $msg = $_.Exception.Message
        Write-LogLine "异常: $msg"
        Write-LaunchResult -Status "fail" -Code "LAUNCH_FAILED" -Message $msg -PatchedDir $paths.PatchedRoot -Attempts $script:attempts -LogFile $script:logFile
        Show-Error $msg
        exit 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main
}
