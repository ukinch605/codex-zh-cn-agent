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
    # 注释行不替换；单引号写法替换；带缩进行替换
    Set-Content -Path $cfg -Value "# localeOverride = `"en-US`"`r`n  localeOverride = 'fr-FR'`r`nother = 1" -Encoding UTF8
    Set-LocaleOverrideZhCn -ConfigPathOverride $cfg
    $c4 = Get-Content -Raw $cfg
    Assert-True "注释掉的 localeOverride 不被替换" ($c4 -match '# localeOverride = "en-US"')
    Assert-True "单引号 localeOverride 被替换为 zh-CN" (($c4 -match 'localeOverride = "zh-CN"') -and ($c4 -notmatch 'fr-FR'))
    # 候选特征串导出（未收录版本安装成功后自动生成）
    $savedLogDir = $logDir
    $logDir = Join-Path $tmp "logs"
    Export-CandidateMarkers -CodexVersion "26.999.1234.0" -Markers $markers
    $cand = Join-Path $logDir "candidate-26.999.1234.0.json"
    Assert-True "候选特征串文件已生成" (Test-Path -LiteralPath $cand)
    $cj = Get-Content -Raw -Encoding UTF8 $cand | ConvertFrom-Json
    Assert-Equal "候选特征串 version" "26.999.1234.0" ([string]$cj.version)
    Assert-True "候选特征串含 markers" ([bool]$cj.markers.enableI18nFrom)
    $logDir = $savedLogDir
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
Assert-True "已收录 26.818.5229.0" ([bool](@($vj.tested) | Where-Object { $_.version -eq "26.818.5229.0" }))
Assert-NotNull "按版本查到 26.818.5229.0 特征串" (Get-TestedMarkers -CodexVersion "26.818.5229.0" -VersionsFile $vfile)
Assert-True "已收录 26.818.8289.0" ([bool](@($vj.tested) | Where-Object { $_.version -eq "26.818.8289.0" }))
Assert-NotNull "按版本查到 26.818.8289.0 特征串" (Get-TestedMarkers -CodexVersion "26.818.8289.0" -VersionsFile $vfile)
Assert-True "已收录 26.820.7780.0" ([bool](@($vj.tested) | Where-Object { $_.version -eq "26.820.7780.0" }))
Assert-NotNull "按版本查到 26.820.7780.0 特征串" (Get-TestedMarkers -CodexVersion "26.820.7780.0" -VersionsFile $vfile)
Assert-True "已收录 26.831.1445.0" ([bool](@($vj.tested) | Where-Object { $_.version -eq "26.831.1445.0" }))
Assert-NotNull "按版本查到 26.831.1445.0 特征串" (Get-TestedMarkers -CodexVersion "26.831.1445.0" -VersionsFile $vfile)
Assert-True "未知版本查表返回空" ($null -eq (Get-TestedMarkers -CodexVersion "99.9.9.9" -VersionsFile $vfile))
Assert-True "localeOnlyFrom 存在" ([bool]$vj.localeOnlyFrom)
Assert-Equal "localeOnlyFrom 为 26.900.0.0" "26.900.0.0" ([string]$vj.localeOnlyFrom)
Assert-True "26.803 线走补丁模式" (-not (Test-LocaleOnlyVersion -Version "26.803.5235.0"))
Assert-True "26.818 线走补丁模式" (-not (Test-LocaleOnlyVersion -Version "26.818.5229.0"))
Assert-True "26.831 线走补丁模式" (-not (Test-LocaleOnlyVersion -Version "26.831.1445.0"))
Assert-True "26.900 起走 locale-only" (Test-LocaleOnlyVersion -Version "26.900.0.0")
Assert-True "26.901 走 locale-only" (Test-LocaleOnlyVersion -Version "26.901.2854.0")
Assert-True "未来更高版本走 locale-only" (Test-LocaleOnlyVersion -Version "99.0.0.0")

# ---------- 监督式启动（launch-zh-cn.ps1） ----------
Write-Host ""
Write-Host "【监督式启动】" -ForegroundColor Yellow
$launcherFile = Join-Path (Split-Path -Parent $PSScriptRoot) "launch-zh-cn.ps1"
Assert-True "launch-zh-cn.ps1 存在" (Test-Path -LiteralPath $launcherFile)
. $launcherFile

# 进程分类
$fakePatched = "C:\Users\VMuser\.codex\zh-cn-patched\abc123\app"
Assert-Equal "汉化副本路径识别为 patched" "patched" (Get-ProcessKind -Path (Join-Path $fakePatched "ChatGPT.exe") -PatchedAppDir $fakePatched)
Assert-Equal "原版路径识别为 original" "original" (Get-ProcessKind -Path "C:\Program Files\WindowsApps\OpenAI.Codex_1.0.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe" -PatchedAppDir $fakePatched)
Assert-Equal "空路径识别为 unknown" "unknown" (Get-ProcessKind -Path "" -PatchedAppDir $fakePatched)
Assert-Equal "路径大小写不敏感" "patched" (Get-ProcessKind -Path "C:\USERS\VMUSER\.CODEX\ZH-CN-PATCHED\ABC123\APP\codex.exe" -PatchedAppDir $fakePatched)

# 守护决策表
Assert-Equal "仅汉化运行 -> ok" "ok" (Get-GuardAction -Patched 3 -NonPatched 0)
Assert-Equal "仅原版运行 -> close" "close" (Get-GuardAction -Patched 0 -NonPatched 2)
Assert-Equal "汉化与原版并存 -> close" "close" (Get-GuardAction -Patched 1 -NonPatched 1)
Assert-Equal "无任何进程 -> start" "start" (Get-GuardAction -Patched 0 -NonPatched 0)

# 汉化副本定位
$tmpLaunch = Join-Path ([System.IO.Path]::GetTempPath()) ("zhcn-launch-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $tmpLaunch "app") -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $tmpLaunch "app\ChatGPT.exe") -Force | Out-Null
$activeTmp = Join-Path $tmpLaunch "active.txt"
Set-Content -LiteralPath $activeTmp -Value "$tmpLaunch`r`nC:\fake\original\app" -Encoding UTF8
$paths = Resolve-LaunchPaths -ActiveFileOverride $activeTmp
Assert-Equal "副本定位返回 app 目录" (Join-Path $tmpLaunch "app") $paths.AppDir
Assert-Equal "副本定位返回启动程序" (Join-Path $tmpLaunch "app\ChatGPT.exe") $paths.ExePath
Assert-True "副本定位返回副本根目录" ($paths.PatchedRoot -eq $tmpLaunch)

# 结果文件协议
$logDir = Join-Path $tmpLaunch "logs"
$resultTmp = Join-Path $tmpLaunch "launch-result.json"
$logTmp = Join-Path $tmpLaunch "launch-test.log"
Write-LaunchResult -Status "ok" -Code "LAUNCH_OK" -PatchedDir $tmpLaunch -Attempts 2 -LogFile $logTmp -ResultFileOverride $resultTmp
$lr = Get-Content -Raw -Encoding UTF8 $resultTmp | ConvertFrom-Json
Assert-Equal "结果文件 status" "ok" ([string]$lr.status)
Assert-Equal "结果文件 code" "LAUNCH_OK" ([string]$lr.code)
Assert-True "结果文件 attempts 为 2" ($lr.attempts -eq 2)
Assert-True "结果文件记录日志路径" ([string]$lr.logFile -eq $logTmp)
Assert-True "结果文件 updatedAt 非空" ([bool]$lr.updatedAt)

$resultTmp2 = Join-Path $tmpLaunch "launch-result-fail.json"
Write-LaunchResult -Status "fail" -Code "LAUNCH_FAILED" -Message "超时" -ResultFileOverride $resultTmp2
$lr2 = Get-Content -Raw -Encoding UTF8 $resultTmp2 | ConvertFrom-Json
Assert-Equal "失败结果 status" "fail" ([string]$lr2.status)
Assert-Equal "失败结果 code" "LAUNCH_FAILED" ([string]$lr2.code)
Assert-True "失败结果记录 message" ([string]$lr2.message -eq "超时")

Remove-Item -LiteralPath $tmpLaunch -Recurse -Force -ErrorAction SilentlyContinue

# ---------- 旧副本清理 ----------
Write-Host ""
Write-Host "【旧副本清理】" -ForegroundColor Yellow
$tmpClean = Join-Path ([System.IO.Path]::GetTempPath()) ("zhcn-clean-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $tmpClean "root1\app") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmpClean "root2\app") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tmpClean "active\app") -Force | Out-Null
$stale1 = @(Get-StalePatchedRoots -BaseDir $tmpClean -ActiveRoot (Join-Path $tmpClean "active"))
Assert-True "清理列表排除当前副本" ($stale1.Count -eq 2 -and ($stale1 -notcontains (Join-Path $tmpClean "active")))
Assert-True "清理列表包含旧副本" (($stale1 -contains (Join-Path $tmpClean "root1")) -and ($stale1 -contains (Join-Path $tmpClean "root2")))
$stale2 = @(Get-StalePatchedRoots -BaseDir $tmpClean -ActiveRoot "")
Assert-True "无当前副本时全部视为待清理" ($stale2.Count -eq 3)
Assert-True "目录不存在时返回空" (@(Get-StalePatchedRoots -BaseDir (Join-Path $tmpClean "nope") -ActiveRoot "").Count -eq 0)
Remove-Item -LiteralPath $tmpClean -Recurse -Force -ErrorAction SilentlyContinue

# ---------- 入口自动切换助手（entry-guard.ps1） ----------
Write-Host ""
Write-Host "【入口自动切换助手】" -ForegroundColor Yellow
$guardFile = Join-Path (Split-Path -Parent $PSScriptRoot) "entry-guard.ps1"
Assert-True "entry-guard.ps1 存在" (Test-Path -LiteralPath $guardFile)
. $guardFile
$ErrorActionPreference = "Stop"
$guardLauncherFile = Join-Path (Split-Path -Parent $PSScriptRoot) "entry-guard-launcher.vbs"
Assert-True "入口助手启动器 vbs 存在" (Test-Path -LiteralPath $guardLauncherFile)
$vbsContent = Get-Content -Raw -Encoding ASCII $guardLauncherFile
Assert-True "启动器以隐藏窗口运行" ($vbsContent -match 'shell\.Run .*0, False')
Assert-True "启动器指向 entry-guard.ps1" ($vbsContent -match 'entry-guard\.ps1')
Assert-True "启动器为纯 ASCII" (-not ([regex]::IsMatch($vbsContent, '[^\x00-\x7F]')))

$fakePatched = "C:\Users\VMuser\.codex\zh-cn-patched\abc123\app"
Assert-Equal "助手:汉化副本路径识别为 patched" "patched" (Get-EntryProcessKind -Path (Join-Path $fakePatched "ChatGPT.exe") -PatchedAppDir $fakePatched)
Assert-Equal "助手:原版路径识别为 original" "original" (Get-EntryProcessKind -Path "C:\Program Files\WindowsApps\OpenAI.Codex_1.0.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe" -PatchedAppDir $fakePatched)
Assert-Equal "助手:空路径识别为 unknown" "unknown" (Get-EntryProcessKind -Path "" -PatchedAppDir $fakePatched)
Assert-Equal "助手:决策 仅汉化 -> none" "none" (Get-EntryAction -Patched 3 -NonPatched 0)
Assert-Equal "助手:决策 无进程 -> none" "none" (Get-EntryAction -Patched 0 -NonPatched 0)
Assert-Equal "助手:决策 仅原版 -> switch" "switch" (Get-EntryAction -Patched 0 -NonPatched 2)
Assert-Equal "助手:决策 并存 -> close-only" "close-only" (Get-EntryAction -Patched 1 -NonPatched 1)

$tmpGuard = Join-Path ([System.IO.Path]::GetTempPath()) ("zhcn-guard-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $tmpGuard "app") -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $tmpGuard "app\ChatGPT.exe") -Force | Out-Null
$activeGuard = Join-Path $tmpGuard "active.txt"
Set-Content -LiteralPath $activeGuard -Value "$tmpGuard`r`nC:\fake\original\app" -Encoding UTF8
$gp = Get-EntryActivePaths -ActiveFileOverride $activeGuard
Assert-Equal "助手:副本定位返回启动程序" (Join-Path $tmpGuard "app\ChatGPT.exe") $gp.ExePath
Assert-True "助手:副本文件缺失时返回空" ($null -eq (Get-EntryActivePaths -ActiveFileOverride (Join-Path $tmpGuard "nope.txt")))
Remove-Item -LiteralPath $tmpGuard -Recurse -Force -ErrorAction SilentlyContinue

# 单实例互斥（自愈触发）
$script:GuardMutex = $null
$mutexName = "TestZhCnEntryGuardMutex"
Assert-True "助手:首次获取互斥成功" (Test-GuardSingleInstance -MutexName $mutexName)
Assert-True "助手:已有实例时检测为冲突" (-not (Test-GuardSingleInstance -MutexName $mutexName))
try { $script:GuardMutex.Dispose(); $script:GuardMutex = $null } catch {}
Assert-True "助手:释放互斥后可再次获取" (Test-GuardSingleInstance -MutexName $mutexName)
try { $script:GuardMutex.Dispose(); $script:GuardMutex = $null } catch {}
$mutexPerUser = Get-GuardMutexName
Assert-True "助手:互斥锁名按用户隔离" ($mutexPerUser -like "CodexZhCnEntryGuardMutex_*")
Assert-True "助手:互斥锁名非空" ([bool]$mutexPerUser)

# ---------- 快捷方式命名（非中文系统兼容） ----------
Write-Host ""
Write-Host "【快捷方式命名】" -ForegroundColor Yellow
Assert-Equal "简体中文代码页用中文快捷方式名" "Codex 汉化版.lnk" (Get-DesktopShortcutName -CodePage 936)
Assert-Equal "英文代码页回退 ASCII 名" "Codex zh-CN.lnk" (Get-DesktopShortcutName -CodePage 1252)
Assert-True "日文代码页回退 ASCII 名" ((Get-DesktopShortcutName -CodePage 932) -eq "Codex zh-CN.lnk")
Assert-True "默认(当前系统)也能返回名称" ([bool](Get-DesktopShortcutName))

# ---------- 目录复制（robocopy） ----------
Write-Host ""
Write-Host "【目录复制】" -ForegroundColor Yellow
Assert-True "Copy-AppDirectory 已定义" ([bool](Get-Command Copy-AppDirectory -ErrorAction SilentlyContinue))
$tmpCopy = Join-Path ([System.IO.Path]::GetTempPath()) ("zhcn-copy-" + [guid]::NewGuid().ToString("N"))
$srcC = Join-Path $tmpCopy "src"
$dstC = Join-Path $tmpCopy "dst"
New-Item -ItemType Directory -Path $srcC -Force | Out-Null
Set-Content -Path (Join-Path $srcC "a.txt") -Value "hello" -Encoding ASCII -NoNewline
Copy-AppDirectory -Source $srcC -Destination $dstC
Assert-True "robocopy 复制成功" (Test-Path -LiteralPath (Join-Path $dstC "a.txt"))
Assert-True "复制内容一致" ((Get-Content -Raw (Join-Path $dstC "a.txt")) -eq "hello")
Remove-Item -LiteralPath $tmpCopy -Recurse -Force -ErrorAction SilentlyContinue

# ---------- locale-only 进程路径判定 ----------
Write-Host ""
Write-Host "【locale-only 进程路径】" -ForegroundColor Yellow
Assert-True "原版 WindowsApps 路径允许" (Test-LocaleAllowedProcessPath -Path "C:\Program Files\WindowsApps\OpenAI.Codex_26.901.4073.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe")
Assert-True "AppData CLI 后端允许" (Test-LocaleAllowedProcessPath -Path "C:\Users\vboxuser\AppData\Local\OpenAI\Codex\bin\1e3e57cdf0634c02\codex.exe")
Assert-True ".codex 路径允许" (Test-LocaleAllowedProcessPath -Path "C:\Users\vboxuser\.codex\zh-cn-agent\scripts\codex.exe")
Assert-True "空路径允许" (Test-LocaleAllowedProcessPath -Path "")
Assert-True "随机系统路径拒绝" (-not (Test-LocaleAllowedProcessPath -Path "C:\Windows\System32\notepad.exe"))

# ---------- freeze / officialLocaleSince ----------
Write-Host ""
Write-Host "【商店冻结与官方语言检测】" -ForegroundColor Yellow
Assert-True "商店冻结判定:null->false" (-not (Test-StoreUpdatesFrozen $null))
Assert-True "商店冻结判定:0->false" (-not (Test-StoreUpdatesFrozen 0))
Assert-True "商店冻结判定:2->true" (Test-StoreUpdatesFrozen 2)
Assert-True "商店冻结判定:4->false" (-not (Test-StoreUpdatesFrozen 4))
$tmpOl = Join-Path ([System.IO.Path]::GetTempPath()) ("zhcn-ol-" + [guid]::NewGuid().ToString("N") + ".json")
Set-Content -Path $tmpOl -Value '{"toolVersion":"1.4.0"}' -Encoding UTF8
Assert-True "officialLocaleSince 缺省为空" ((Get-OfficialLocaleSince -VersionsFileOverride $tmpOl) -eq "")
Set-Content -Path $tmpOl -Value '{"toolVersion":"1.4.0","officialLocaleSince":"26.901.4073.0"}' -Encoding UTF8
Assert-Equal "officialLocaleSince 有值解析" "26.901.4073.0" (Get-OfficialLocaleSince -VersionsFileOverride $tmpOl)
Remove-Item -LiteralPath $tmpOl -Force -ErrorAction SilentlyContinue

# ---------- 汇总 ----------
Write-Host ""
Write-Host ("TEST SUMMARY: {0} passed, {1} failed" -f $script:passCount, $script:failCount) -ForegroundColor Cyan
if ($script:failCount -gt 0) { exit 1 }
exit 0
