#requires -version 5.1
<#
  恢复英文原版 Codex
  说明：关闭汉化版后，从开始菜单/原版安装启动原版 Codex（英文界面）。
#>
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

Write-Host ""
Write-Host "正在移除入口自动切换助手..." -ForegroundColor Yellow
try {
    Stop-ScheduledTask -TaskName "CodexZhCnEntryGuard" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "CodexZhCnEntryGuard" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "已移除入口自动切换助手。" -ForegroundColor Green
} catch {}
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
