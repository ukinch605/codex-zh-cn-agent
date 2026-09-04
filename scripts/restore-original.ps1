#requires -version 5.1
<#
  恢复英文原版 Codex
  说明：关闭汉化版后，从开始菜单/原版安装启动原版 Codex（英文界面）。
#>
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Stop-EntryGuardProcesses {
    try {
        $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq "powershell.exe" -and $_.CommandLine -match 'entry-guard\.ps1' })
        foreach ($p in $procs) {
            Write-Host ("正在结束残留的入口助手进程: PID " + $p.ProcessId) -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

Write-Host ""
Write-Host "正在移除入口自动切换助手..." -ForegroundColor Yellow
Stop-EntryGuardProcesses
$removed = $false
try {
    Stop-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "CodexZhCnEntryGuard" -Confirm:$false -ErrorAction SilentlyContinue
    $removed = -not (Get-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue)
} catch {
    Write-Host ("移除入口助手任务失败: " + $_.Exception.Message) -ForegroundColor Yellow
}
if (-not $removed) {
    try {
        & schtasks.exe /Delete /TN "CodexZhCnEntryGuard" /F 2>$null | Out-Null
        $removed = -not (Get-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue)
    } catch {
        Write-Host ("schtasks 删除入口助手任务失败: " + $_.Exception.Message) -ForegroundColor Yellow
    }
}
if ($removed) {
    Write-Host "已移除入口自动切换助手。" -ForegroundColor Green
} else {
    Write-Host "警告：入口助手计划任务仍存在（CodexZhCnEntryGuard），请以管理员身份重跑恢复，或手动执行：schtasks /Delete /TN CodexZhCnEntryGuard /F" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "正在恢复原始语言配置..." -ForegroundColor Yellow
$configPath = Join-Path $env:USERPROFILE ".codex\config.toml"
$bak = "$configPath.bak-zhcn"
if (Test-Path $bak) {
    Copy-Item -LiteralPath $bak -Destination $configPath -Force
    Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
    Write-Host "已恢复原始语言配置。" -ForegroundColor Green
} elseif (Test-Path $configPath) {
    $content = [System.IO.File]::ReadAllText($configPath)
    $content = [regex]::Replace($content, '(?m)^[ \t]*localeOverride\s*=\s*(''|")[^''"]*\1[ \t]*(\r?\n|$)', "")
    [System.IO.File]::WriteAllText($configPath, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已移除语言覆盖配置。" -ForegroundColor Green
}
Write-Host ""
Write-Host "正在关闭汉化版 Codex..." -ForegroundColor Yellow
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$pkg = $null
try {
    $pkg = Get-AppxPackage -ErrorAction Stop |
        Where-Object { $_.Name -match 'Codex|OpenAI' } |
        Select-Object -First 1
} catch { $pkg = $null }

if ($pkg) {
    try {
        $manifest = Get-AppxPackageManifest -Package $pkg
        $appId = $manifest.Package.Applications.Application[0].Id
        Write-Host "正在启动原版 Codex（英文界面）..." -ForegroundColor Yellow
        Start-Process "explorer.exe" -ArgumentList "shell:AppsFolder\$($pkg.PackageFamilyName)!$appId"
        Write-Host ""
        Write-Host "已启动原版。以后请从开始菜单打开 Codex 即可使用英文界面。" -ForegroundColor Green
        exit 0
    } catch {
        Write-Host "无法通过开始菜单启动，将尝试直接启动原版程序..." -ForegroundColor Yellow
    }
}

$activeFile = Join-Path $env:USERPROFILE ".codex\zh-cn-patched-active.txt"
if (Test-Path $activeFile) {
    $lines = Get-Content -LiteralPath $activeFile -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 }
    if ($lines.Count -ge 2) {
        $orig = $lines[1].Trim()
        foreach ($name in @("ChatGPT.exe", "Codex.exe")) {
            $exe = Join-Path $orig $name
            if (Test-Path $exe) {
                Write-Host "正在启动原版 Codex..." -ForegroundColor Yellow
                Start-Process $exe
                Write-Host "已启动原版。以后请从开始菜单打开 Codex 即可使用英文界面。" -ForegroundColor Green
                exit 0
            }
        }
    }
}
Write-Host ""
Write-Host "未能自动启动原版。请从开始菜单中手动打开 Codex（英文界面）。" -ForegroundColor Yellow
Read-Host "按 Enter 退出"
exit 0
