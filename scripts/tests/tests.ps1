#requires -version 5.1
<#
  离线测试（零依赖断言）。用法：
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tests\tests.ps1
  或经由安装器：install-zh-cn.ps1 -Action test -NoPause
  全部通过时退出码 0，否则退出码 1。
#>
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# 挂载安装器中的纯函数（入口已被 dot-source 守卫跳过）
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) "install-zh-cn.ps1"
. $installer

$script:passCount = 0
$script:failCount = 0

function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    if ($Expected -eq $Actual) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passCount++
    } else {
        Write-Host "  [FAIL] $Name（期望: $Expected，实际: $Actual）" -ForegroundColor Red
        $script:failCount++
    }
}

function Assert-True {
    param([string]$Name, [bool]$Condition)
    Assert-Equal -Name $Name -Expected $true -Actual $Condition
}

function Assert-NotNull {
    param([string]$Name, $Value)
    Assert-True -Name $Name -Condition ($null -ne $Value)
}

Write-Host "========== Codex 汉化工具离线测试 ==========" -ForegroundColor Cyan

# ---------- 夹具 ----------
$fixtures = Join-Path $PSScriptRoot "fixtures"
$origText = Get-Content -Raw -Encoding UTF8 (Join-Path $fixtures "original.txt")
$patchedText = Get-Content -Raw -Encoding UTF8 (Join-Path $fixtures "patched.txt")
$unsupportedText = Get-Content -Raw -Encoding UTF8 (Join-Path $fixtures "unsupported.txt")
$markers = $script:defaultMarkers

# ---------- 状态识别 ----------
Write-Host ""
Write-Host "【状态识别】" -ForegroundColor Yellow
Assert-Equal "original 识别为 original" "original" (Get-I18nStateFromText -Text $origText -Markers $markers)
Assert-Equal "patched 识别为 patched" "patched" (Get-I18nStateFromText -Text $patchedText -Markers $markers)
Assert-Equal "unsupported 识别为 unsupported" "unsupported" (Get-I18nStateFromText -Text $unsupportedText -Markers $markers)

# ---------- 等长补丁与幂等性 ----------
Write-Host ""
Write-Host "【补丁逻辑】" -ForegroundColor Yellow
$patchedOut = Invoke-PatchText -Text $origText -Markers $markers
Assert-Equal "补丁后字符长度不变" $origText.Length $patchedOut.Length
$enc = [System.Text.Encoding]::GetEncoding(28591)
Assert-Equal "补丁后 Latin-1 字节长度不变" $enc.GetBytes($origText).Length $enc.GetBytes($patchedOut).Length
Assert-Equal "补丁结果识别为 patched" "patched" (Get-I18nStateFromText -Text $patchedOut -Markers $markers)
Assert-Equal "再次补丁幂等（结果不变）" $patchedOut (Invoke-PatchText -Text $patchedOut -Markers $markers)

# ---------- 通用探测 ----------
Write-Host ""
Write-Host "【通用特征探测】" -ForegroundColor Yellow
Assert-NotNull "original 能通用探测到特征串" (Find-GenericMarkers -Text $origText)
Assert-True "unsupported 探测结果为空" ($null -eq (Find-GenericMarkers -Text $unsupportedText))
Assert-True "patched 不再命中原始特征串" ($null -eq (Find-GenericMarkers -Text $patchedText))
$ambiguous = $origText + 'var again="enable_i18n`,!1)";'
Assert-True "特征串出现两次时拒绝（保守）" ($null -eq (Find-GenericMarkers -Text $ambiguous))
Assert-True "unsupported 不会解析出特征串（不落盘修改）" ($null -eq (Resolve-Markers -Text $unsupportedText -CodexVersion "99.0.0.0"))
Assert-NotNull "原版可解析出特征串" (Resolve-Markers -Text $origText -CodexVersion "99.0.0.0")

# ---------- 诊断文件 ----------
Write-Host ""
Write-Host "【诊断文件】" -ForegroundColor Yellow
$diagPath = Join-Path ([System.IO.Path]::GetTempPath()) ("zhcn-diag-" + [guid]::NewGuid().ToString("N") + ".txt")
$saved = Save-Diagnostic -CodexVersion "99.0.0.0" -Snippet "enable_i18n probe" -OutPath $diagPath
Assert-Equal "诊断文件已生成" $diagPath $saved
Assert-True "诊断文件内容包含片段" ((Get-Content -Raw $diagPath) -match 'enable_i18n probe')
Remove-Item -LiteralPath $diagPath -Force -ErrorAction SilentlyContinue

# ---------- 配置写入 ----------
Write-Host ""
Write-Host "【config.toml 写入】" -ForegroundColor Yellow
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("zhcn-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $cfg = Join-Path $tmp "config.toml"
    # 空文件
    Set-LocaleOverrideZhCn -ConfigPathOverride $cfg
    Assert-True "空配置写入 zh-CN" ((Get-Content -Raw $cfg) -match 'localeOverride\s*=\s*"zh-CN"')
    Assert-True "空配置不生成备份" (-not (Test-Path "$cfg.bak-zhcn"))
    # 已有 [desktop] 段
    Set-Content -Path $cfg -Value "[desktop]`r`nmodel_provider = `"openai`"" -Encoding UTF8
    Set-LocaleOverrideZhCn -ConfigPathOverride $cfg
    $c2 = Get-Content -Raw $cfg
    Assert-True "已有 [desktop] 段时保留原内容" ($c2 -match 'model_provider\s*=\s*"openai"')
    Assert-True "已有 [desktop] 段时追加 zh-CN" ($c2 -match 'localeOverride\s*=\s*"zh-CN"')
    Assert-True "已有配置生成备份" (Test-Path "$cfg.bak-zhcn")
    # 替换已有 localeOverride
    Set-Content -Path $cfg -Value "localeOverride = `"en-US`"" -Encoding UTF8
    Set-LocaleOverrideZhCn -ConfigPathOverride $cfg
    $c3 = Get-Content -Raw $cfg
    Assert-True "替换已有 localeOverride 为 zh-CN" (($c3 -match 'localeOverride\s*=\s*"zh-CN"') -and ($c3 -notmatch 'en-US'))
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------- versions.json ----------
Write-Host ""
Write-Host "【versions.json】" -ForegroundColor Yellow
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vfile = Join-Path $repoRoot "versions.json"
Assert-True "versions.json 存在" (Test-Path -LiteralPath $vfile)
$vj = Get-Content -Raw -Encoding UTF8 $vfile | ConvertFrom-Json
Assert-Equal "schema 为 1" 1 $vj.schema
Assert-True "toolVersion 非空" ([bool]$vj.toolVersion)
Assert-True "已收录 26.803.5235.0" ([bool](@($vj.tested) | Where-Object { $_.version -eq "26.803.5235.0" }))
Assert-NotNull "按版本查到特征串" (Get-TestedMarkers -CodexVersion "26.803.5235.0" -VersionsFile $vfile)
Assert-True "未知版本查表返回空" ($null -eq (Get-TestedMarkers -CodexVersion "99.9.9.9" -VersionsFile $vfile))

# ---------- 汇总 ----------
Write-Host ""
Write-Host ("TEST SUMMARY: {0} passed, {1} failed" -f $script:passCount, $script:failCount) -ForegroundColor Cyan
if ($script:failCount -gt 0) { exit 1 }
exit 0
