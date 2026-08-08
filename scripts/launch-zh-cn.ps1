#requires -version 5.1
<#
  启动 Codex 汉化版（zh-CN）
  说明：先关闭所有 Codex 相关进程（单实例限制），再从汉化副本启动 ChatGPT.exe。
#>
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Show-Error([string]$Message) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($Message, 0, "Codex 汉化版", 16)
    } catch {
        Write-Host $Message -ForegroundColor Red
    }
}

$activeFile = Join-Path $env:USERPROFILE ".codex\zh-cn-patched-active.txt"
if (-not (Test-Path $activeFile)) {
    Show-Error "尚未安装汉化。`n`n请先双击「安装汉化.bat」完成汉化安装。"
    exit 1
}

$lines = Get-Content -LiteralPath $activeFile -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 }
if ($lines.Count -lt 1) {
    Show-Error "汉化记录为空。请重新运行「安装汉化.bat」。"
    exit 1
}
$patchedRoot = $lines[0].Trim()
$appDir = Join-Path $patchedRoot "app"
if (-not (Test-Path $appDir)) {
    Show-Error "汉化副本文件夹不存在：`n$appDir`n`n请重新运行「安装汉化.bat」。"
    exit 1
}

$exePath = Join-Path $appDir "ChatGPT.exe"
if (-not (Test-Path $exePath)) {
    $exePath = Join-Path $appDir "Codex.exe"
}
if (-not (Test-Path $exePath)) {
    Show-Error "汉化副本中未找到启动程序。请重新运行「安装汉化.bat」。"
    exit 1
}

# 单实例：先彻底关闭旧进程（含原版与汉化版）
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match '^(codex|chatgpt)$' } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Start-Process -FilePath $exePath -WorkingDirectory $appDir | Out-Null
exit 0