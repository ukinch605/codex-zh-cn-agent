#requires -version 5.1
<#
  生成发布 zip（供维护者上传到 GitHub Releases）。
  用法：powershell -ExecutionPolicy Bypass -File publish-release.ps1 [-Version "1.1.0"]
  输出：仓库根目录 codex-zh-cn-agent-v<版本>.zip（*.zip 已被 .gitignore 忽略）
  维护者后续操作：打 tag v<版本>，上传 zip，并在 Release 说明里写明已测试的 Codex 版本。
#>
param([string]$Version = "1.1.0")

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$repoRoot = Split-Path -Parent $PSScriptRoot
$staging = Join-Path $env:TEMP ("codex-zh-cn-publish-" + [guid]::NewGuid().ToString("N"))
$pkgDir = Join-Path $staging ("codex-zh-cn-agent-v" + $Version)
New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null

# 复制文件：bat、scripts（含测试）、文档、LICENSE、versions.json
Get-ChildItem -LiteralPath $repoRoot -Filter *.bat | Copy-Item -Destination $pkgDir -Force
foreach ($name in @("README.md","AGENTS.md","使用说明.txt","LICENSE","versions.json")) {
    $p = Join-Path $repoRoot $name
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $pkgDir -Force }
}
$scriptsDst = Join-Path $pkgDir "scripts"
New-Item -ItemType Directory -Path $scriptsDst -Force | Out-Null
Copy-Item -Path (Join-Path $repoRoot "scripts\*") -Destination $scriptsDst -Recurse -Force

# 在发布副本中写入工具版本
$vfile = Join-Path $pkgDir "versions.json"
$vj = Get-Content -Raw -Encoding UTF8 $vfile | ConvertFrom-Json
$vj.toolVersion = $Version
[System.IO.File]::WriteAllText($vfile, ($vj | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

$zip = Join-Path $repoRoot ("codex-zh-cn-agent-v" + $Version + ".zip")
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $pkgDir "*") -DestinationPath $zip -CompressionLevel Optimal

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash
Write-Host ""
Write-Host "ZIP: $zip" -ForegroundColor Green
Write-Host "SHA256: $hash" -ForegroundColor Green
Write-Host ""
Write-Host "下一步（维护者手动）：" -ForegroundColor Yellow
Write-Host "  1. git tag v$Version && git push origin v$Version"
Write-Host "  2. 在 GitHub Releases 创建 v$Version，上传上面的 zip"
Write-Host "  3. Release 说明中写明已测试的 Codex 版本（见 versions.json）"

Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
