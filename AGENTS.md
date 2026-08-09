# Agent Guide: Localize Codex Desktop to Chinese (zh-CN)

## Mission

Install the Chinese UI localization for **Codex Desktop** on this Windows machine by running the scripts in this repository. The user asked for this in one sentence; do the whole job for them: fetch the latest repo, detect, install, restart, verify, and report.

The restart is a **transitional supervised restart** (a few seconds; no background process remains). The launcher (`scripts/launch-zh-cn.ps1`) writes `%USERPROFILE%\.codex\zh-cn-agent\launch-result.json`; the agent reads it after the window restarts.

## Hard safety boundaries (never violate)

- Never modify files under `C:\Program Files\WindowsApps` directly. The installer copies the app first.
- Never read, write, print, or send `auth.json`, API keys, tokens, or `config.toml` secrets.
- Never change `model_provider`, `model`, or any model/API settings in `config.toml`.
- Never make network calls to OpenAI. Installation works fully offline.
- The tool intentionally installs one logon task — the "入口自动切换助手" (entry auto-switch guard, `scripts/entry-guard.ps1`) — so Codex opens in Chinese from any entry point. Install it as the installer does, never remove it during install, and never create any additional persistent watchers. It is removed automatically by restore/uninstall.
- The installer stops and restarts Codex processes (including this session). That is expected; tell the user the window will restart in Chinese.

## Prerequisites

- Windows 10/11, Codex Desktop installed from Microsoft Store. Detect it:

```powershell
Get-AppxPackage | Where-Object { $_.Name -match 'Codex|OpenAI' } | Select-Object Name, Version, InstallLocation
```

- If not found: tell the user to install Codex from Microsoft Store first, then stop.

## Step 0 - Get the repository (always use the latest)

```powershell
git clone https://github.com/ukinch605/codex-zh-cn-agent.git
cd codex-zh-cn-agent
```

If `git clone` fails due to network, fall back to the zip archive (same content):

```powershell
$tmpZip = Join-Path $env:TEMP "codex-zh-cn-agent.zip"
Invoke-WebRequest -Uri "https://codeload.github.com/ukinch605/codex-zh-cn-agent/zip/refs/heads/main" -OutFile $tmpZip
Expand-Archive -Path $tmpZip -DestinationPath . -Force
cd codex-zh-cn-agent-main
```

## Step 1 - Notify the user before installing

Tell the user (in Chinese): 接下来会请求一次管理员权限（UAC 弹窗请点「是」）；安装完成后当前窗口会自动以中文版重启（过渡监督式，几秒完成），并安装一个登录自启的入口自动切换助手，以后从任何入口打开 Codex 都是中文版。

## Step 2 - Run the installer

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\install-zh-cn.ps1" -Action install -NoPause
```

The parent process writes `status: pending` to `%USERPROFILE%\.codex\zh-cn-agent\install-result.json`, requests UAC elevation, and **exits immediately**. Do not assume failure.

The elevated install process calls the supervised launcher at the end; the current window restarts as the localized app (a few seconds). The agent session may be interrupted during this restart; the thread resumes afterwards and the agent continues.

## Step 3 - Poll the result file (up to 5 minutes, every 10 seconds)

```powershell
$rf = Join-Path $env:USERPROFILE ".codex\zh-cn-agent\install-result.json"
$start = Get-Date
$r = $null
do {
    Start-Sleep -Seconds 10
    if (Test-Path $rf) { $r = Get-Content -Raw -Encoding UTF8 $rf | ConvertFrom-Json }
} until (($r -and $r.status -in @("ok","fail")) -or ((Get-Date) - $start).TotalMinutes -ge 5)
```

Interpret the result:

- `ok` → continue to Step 4.
- `fail` → read `$r.code`, `$r.message`, `$r.diagFile` and handle per the table below.
- Still `pending` after 5 minutes → the user most likely clicked **No** on the UAC prompt. Tell them: 请在 UAC 弹窗中点击「是」，然后重新发送这条指令。Then stop.

After the window restarts, also read `%USERPROFILE%\.codex\zh-cn-agent\launch-result.json`:

- `status: ok`（`LAUNCH_OK` or `ALREADY_RUNNING`）→ continue to Step 4.
- `status: fail` → handle per the `LAUNCH_FAILED` row in the failure table below.

Note: the restart may interrupt the agent session, and the thread does not always auto-resume afterwards. If the agent did not continue on its own after the window came back, ask the user to send a short message (e.g., 继续) to trigger the final verify; `install-result.json` and `launch-result.json` already contain the state needed to report even without further tool calls.

## Step 4 - Verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\install-zh-cn.ps1" -Action verify -NoPause
```

Expect every line to read `VERIFY: <item>=OK` and the last line `VERIFY: OVERALL=OK`.
If any item is FAIL: the installer normally auto-launches the localized app; if no Codex window is open, run `启动汉化版.bat` (or `scripts\launch-zh-cn.ps1`). If verify still fails, rerun the installer once; if it fails again, report the log path.

Note: verify includes a `last-launch` item that reflects the most recent `launch-result.json`; it only fails if the most recent supervised launch failed.

## Step 5 - Confirm with the user

Ask the user to confirm the left sidebar (新聊天 / 项目 / 计划 / 插件) and the top menus are Chinese. If they cannot tell yet, wait for the app to finish loading.

Note: after v1.3, opening Codex from any entry (Start menu, taskbar, Store tile) auto-switches to the localized version within 1-2 seconds; a brief English window that then closes is expected.

## Failure handling

| `code` | Meaning | Action |
| --- | --- | --- |
| `CODEX_NOT_FOUND` | Store version not detected | Ask user to install Codex from Microsoft Store first |
| `VERSION_UNSUPPORTED` | Code structure not recognized | Read `$r.diagFile` (or `%USERPROFILE%\.codex\zh-cn-agent\logs\diagnostic-*.txt`), show its content, and tell the user to open an issue in this repository with the full file |
| `ASAR_NOT_FOUND` / `ASAR_PARSE_FAILED` | app.asar missing/unreadable | Report the message and the log path |
| `COPY_FAILED` / `PATCH_FAILED` / `PATCH_LENGTH_MISMATCH` / `PATCH_VERIFY_FAILED` | Patch pipeline issue | Rerun install once; if it repeats, report `%USERPROFILE%\.codex\zh-cn-agent\logs\install-*.log` |
| `LAUNCH_FAILED` | Localized app did not stabilize after install (or the most recent launch failed) | Read `launch-result.json` and `logs\launch-*.log`; rerun install once if it is the first failure; if it repeats, report both files' content |
| `UNKNOWN` | Unexpected error | Report the exact console message and the latest install log |

## Cleanup / rollback (only if the user asks)

- Restore English: run `scripts\restore-original.ps1` (or `恢复原版.bat`), then start Codex from the Start menu.
- Full uninstall: `卸载汉化.bat` (confirmation + UAC), or `install-zh-cn.ps1 -Action uninstall -Force -NoPause` if the user explicitly confirmed. This deletes the patched copy, restores config, removes the shortcut and the tool directory.

## Update strategy

- After a Codex Store update, the localization may need re-installation; the installer automatically rebuilds the patched copy when the version changed.
- The tool supports new versions via the `versions.json` table plus generic detection. If `VERSION_UNSUPPORTED` occurs, the diagnostic file is the input for a repository issue.
- Optional online update (`检查更新.bat` / `-Action check-update`) is off by default and only runs when the user explicitly asks.
