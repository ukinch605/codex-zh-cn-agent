#requires -version 5.1
<#
  Codex 汉化版入口自动切换助手 v1.3（登录自启，隐藏窗口）
  作用：让“从任何入口打开 Codex”都能得到中文版。
  - 监听 codex/chatgpt 进程启动事件（WMI 事件驱动），并每 10 秒安全复查一次。
  - 规则：发现原版进程被打开且汉化版未运行 → 关闭原版并启动汉化副本；
          原版与汉化版并存 → 仅关闭原版；只有汉化版 → 不做任何事。
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

function Invoke-EntryAction {
    param($Paths, [string]$Action)
    if ($Action -eq "none") { return }
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
    if ($Action -eq "switch") {
        Write-GuardLog ("检测到原版入口被打开（{0} 个进程），正在切换为汉化版..." -f $procs.Count)
        Start-Process -FilePath $Paths.ExePath -WorkingDirectory $Paths.AppDir
    } else {
        Write-GuardLog ("已关闭与汉化版并存的英文进程 {0} 个" -f $procs.Count)
    }
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
    try {
        Register-CimIndicationEvent -Query "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName='codex.exe' OR ProcessName='chatgpt.exe'" -SourceIdentifier "CodexZhCnEntryStart" -ErrorAction Stop | Out-Null
        $wmiOk = $true
        Write-GuardLog "已注册进程启动事件监听。"
    } catch {
        Write-GuardLog ("事件监听不可用，回退为定期扫描: " + $_.Exception.Message)
    }
    $lastScan = Get-Date
    while ($true) {
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
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-EntryGuardLoop
}
