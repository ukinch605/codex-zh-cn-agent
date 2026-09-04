#requires -version 5.1
<#
  Codex 汉化版入口自动切换助手 v1.3.3（登录自启 + 每 5 分钟自愈，隐藏窗口）
  作用：让“从任何入口打开 Codex”都能得到中文版。
  - 监听 codex/chatgpt 进程启动事件（WMI 事件驱动），并每 10 秒安全复查一次。
  - 规则：发现原版进程被打开且汉化版未运行 → 关闭原版并启动汉化副本；
          原版与汉化版并存 → 仅关闭原版；只有汉化版 → 不做任何事。
  - 自愈：计划任务每 5 分钟触发一次；本脚本用命名互斥锁保证同一时刻只有一个实例，
          已有实例在运行时新触发的实例立即退出，助手进程意外终止后最多 5 分钟自动恢复。
  - 不联网、不访问 OpenAI；恢复原版/卸载时由安装器移除本任务。
  日志：%USERPROFILE%\.codex\zh-cn-agent\logs\entry-guard.log
#>
$ErrorActionPreference = "SilentlyContinue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$userProfile = $env:USERPROFILE
$activeFile = Join-Path $userProfile ".codex\zh-cn-patched-active.txt"
$logDir = Join-Path (Join-Path $userProfile ".codex\zh-cn-agent") "logs"
$logFile = Join-Path $logDir "entry-guard.log"

function Write-GuardLog {
    param([string]$Message)
    try {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
        if ((Get-Item -LiteralPath $logFile).Length -gt 1MB) {
            Move-Item -LiteralPath $logFile -Destination "$logFile.old" -Force
        }
    } catch {}
}

function Get-EntryActivePaths {
    param([string]$ActiveFileOverride = "")
    $file = if ($ActiveFileOverride) { $ActiveFileOverride } else { $activeFile }
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 })
    if ($lines.Count -lt 1) { return $null }
    $root = $lines[0].Trim()
    $appDir = Join-Path $root "app"
    $exePath = Join-Path $appDir "ChatGPT.exe"
    if (-not (Test-Path -LiteralPath $exePath)) { $exePath = Join-Path $appDir "Codex.exe" }
    if (-not (Test-Path -LiteralPath $exePath)) { return $null }
    return [pscustomobject]@{ AppDir = $appDir; ExePath = $exePath }
}

function Test-GuardSingleInstance {
    <#
      命名互斥锁单实例检查（供计划任务重复触发使用）。
      返回 $true = 本实例应继续运行（抢到互斥权）；$false = 已有实例，应退出。
      互斥句柄保存在 $script:GuardMutex，保证脚本运行期间不会被垃圾回收。
    #>
    param([string]$MutexName = "CodexZhCnEntryGuardMutex")
    $createdNew = $false
    try {
        $m = New-Object System.Threading.Mutex($false, $MutexName, [ref]$createdNew)
    } catch {
        Write-GuardLog ("互斥锁创建失败，按可运行处理（防止助手停摆）: " + $_.Exception.Message)
        return $true
    }
    if ($createdNew) {
        $script:GuardMutex = $m
        return $true
    }
    try { $m.Dispose() } catch {}
    return $false
}

function Get-GuardMutexName {
    <#
      生成按用户隔离的互斥锁名（多用户机器上每个用户独立，互不影响）。
    #>
    $sid = ""
    try { $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch {}
    if (-not $sid) { $sid = $env:USERNAME }
    $safe = ($sid -replace '[^0-9A-Za-z_-]', '_')
    return "CodexZhCnEntryGuardMutex_" + $safe
}

function Get-EntryProcessKind {
    param([string]$Path, [string]$PatchedAppDir)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "unknown" }
    if ($Path.StartsWith($PatchedAppDir, [System.StringComparison]::OrdinalIgnoreCase)) { return "patched" }
    return "original"
}

function Get-EntryAction {
    param([int]$Patched, [int]$NonPatched)
    if ($NonPatched -le 0) { return "none" }
    if ($Patched -gt 0) { return "close-only" }
    return "switch"
}

function Get-CodexCounts {
    param($Paths)
    $patched = 0
    $nonPatched = 0
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' } |
        ForEach-Object {
            $path = $null
            try { $path = $_.Path } catch {}
            if ([string]::IsNullOrWhiteSpace($path)) { try { $path = $_.MainModule.FileName } catch {} }
            $kind = Get-EntryProcessKind -Path $path -PatchedAppDir $Paths.AppDir
            if ($kind -eq "patched") { $patched++ } else { $nonPatched++ }
        }
    return [pscustomobject]@{ Patched = $patched; NonPatched = $nonPatched }
}

function Stop-NonPatchedProcs {
    param($Paths)
    $procs = @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' } |
        Where-Object {
            $path = $null
            try { $path = $_.Path } catch {}
            if ([string]::IsNullOrWhiteSpace($path)) { try { $path = $_.MainModule.FileName } catch {} }
            (Get-EntryProcessKind -Path $path -PatchedAppDir $Paths.AppDir) -ne "patched"
        })
    foreach ($p in $procs) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    return $procs.Count
}

function Start-PatchedWithRetry {
    param($Paths)
    # 强杀原版后立即启动汉化版，会与原版残留的 Electron 单实例锁竞争导致秒退；
    # 因此等旧进程完全退出 -> 启动 -> 短暂验证，失败则重试一次。
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Start-Sleep -Seconds 2
        $left = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' })
        foreach ($p in $left) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
        Write-GuardLog ("启动汉化版（第 {0} 次尝试）..." -f $attempt)
        Start-Process -FilePath $Paths.ExePath -WorkingDirectory $Paths.AppDir
        Start-Sleep -Seconds 6
        $counts = Get-CodexCounts -Paths $Paths
        if ($counts.Patched -gt 0) {
            Write-GuardLog ("汉化版已启动（patched 进程 {0} 个）。" -f $counts.Patched)
            return $true
        }
        Write-GuardLog "汉化版启动后未存活（patched=0）。"
    }
    Write-GuardLog "汉化版启动失败：两次尝试后仍无 patched 进程。"
    return $false
}

function Invoke-EntryAction {
    param($Paths, [string]$Action)
    if ($Action -eq "none") { return }
    if ($Action -eq "close-only") {
        $killed = Stop-NonPatchedProcs -Paths $Paths
        Write-GuardLog ("已关闭与汉化版并存的英文进程 {0} 个" -f $killed)
        return
    }
    $killed = Stop-NonPatchedProcs -Paths $Paths
    Write-GuardLog ("检测到原版入口被打开（已关闭原版进程 {0} 个），正在切换为汉化版..." -f $killed)
    [void](Start-PatchedWithRetry -Paths $Paths)
}

function Test-SwitchNeeded {
    param($Paths)
    if (-not $Paths) { return }
    $counts = Get-CodexCounts -Paths $Paths
    $action = Get-EntryAction -Patched $counts.Patched -NonPatched $counts.NonPatched
    if ($action -ne "none") {
        Invoke-EntryAction -Paths $Paths -Action $action
    }
}

function Invoke-EntryGuardLoop {
    Write-GuardLog "入口自动切换助手启动。"
    $wmiOk = $false
    $wmiFallbackLogged = $false
    $lastWmiRetry = Get-Date
    $lastScan = Get-Date
    $lastBeat = Get-Date
    $lastTaskCheck = Get-Date
    while ($true) {
        try {
            # 计划任务被移除（恢复原版/卸载）时自行退出，防止残留实例继续切换
            if (((Get-Date) - $lastTaskCheck).TotalSeconds -ge 30) {
                $lastTaskCheck = Get-Date
                if (-not (Get-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue)) {
                    Write-GuardLog "入口助手计划任务已不存在，助手退出。"
                    exit 0
                }
            }
            if (-not $wmiOk -and ((Get-Date) - $lastWmiRetry).TotalSeconds -ge 60) {
                $lastWmiRetry = Get-Date
                try {
                    Register-CimIndicationEvent -Query "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName='codex.exe' OR ProcessName='chatgpt.exe'" -SourceIdentifier "CodexZhCnEntryStart" -ErrorAction Stop | Out-Null
                    $wmiOk = $true
                    if ($wmiFallbackLogged) {
                        Write-GuardLog "事件监听恢复成功，已退出定期扫描模式。"
                    } else {
                        Write-GuardLog "已注册进程启动事件监听。"
                    }
                } catch {
                    if (-not $wmiFallbackLogged) {
                        $wmiFallbackLogged = $true
                        Write-GuardLog ("事件监听不可用，已进入定期扫描模式（每 10 秒扫描一次）: " + $_.Exception.Message)
                    } else {
                        Write-GuardLog ("事件监听重试仍失败（保持定期扫描模式）: " + $_.Exception.Message)
                    }
                }
            }
            $eventHit = $false
            if ($wmiOk) {
                $evt = Wait-Event -SourceIdentifier "CodexZhCnEntryStart" -Timeout 10 -ErrorAction SilentlyContinue
                if ($evt) {
                    $eventHit = $true
                    Remove-Event -SourceIdentifier "CodexZhCnEntryStart" -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 800
                }
            } else {
                Start-Sleep -Seconds 10
            }
            if ($eventHit -or ((Get-Date) - $lastScan).TotalSeconds -ge 10) {
                $lastScan = Get-Date
                Test-SwitchNeeded -Paths (Get-EntryActivePaths)
            }
            if (((Get-Date) - $lastBeat).TotalSeconds -ge 300) {
                $lastBeat = Get-Date
                Write-GuardLog "存活检查正常。"
            }
        } catch {
            Write-GuardLog ("扫描异常（继续运行）: " + $_.Exception.Message)
            Start-Sleep -Seconds 5
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-GuardSingleInstance -MutexName (Get-GuardMutexName))) {
        Write-GuardLog "已有助手实例在运行，本次触发退出。"
        exit 0
    }
    Invoke-EntryGuardLoop
}
