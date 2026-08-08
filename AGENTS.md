# Agent Guide: Localize Codex Desktop to Chinese (zh-CN)

## Mission

Install the Chinese UI localization for **Codex Desktop** on this Windows machine by running the scripts in this repository. The user asked for this in one sentence; do the whole job for them.

## Hard safety boundaries (never violate)

- Never modify files under `C:\Program Files\WindowsApps` directly. The installer copies the app first.
- Never read, write, print, or send `auth.json`, API keys, tokens, or `config.toml` secrets.
- Never change `model_provider`, `model`, or any model/API settings in `config.toml`.
- Never make network calls to OpenAI. This works fully offline.
- The installer stops and restarts Codex processes (including this session). That is expected; tell the user the window will restart in Chinese.

## Prerequisites

- Windows 10/11.
- Codex Desktop installed from Microsoft Store. Detect it:

```powershell
powershell -NoProfile -Command "Get-AppxPackage | Where-Object { $_.Name -match 'Codex|OpenAI' } | Select-Object Name, Version, InstallLocation"
```

If not found: tell the user to install Codex from Microsoft Store first, then stop.

## Steps

1. **Run the installer**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\install-zh-cn.ps1" -Action install -NoPause
```

- If a UAC prompt appears, ask the user to click **Yes** (admin is required only to copy from the Store install location).
- Expected success output ends with: `RESULT: INSTALL_OK`
- On failure the script prints `RESULT: INSTALL_FAIL` plus a reason. Capture and report the exact message.
- If the script self-elevates and exits (parent process), continue to verification in step 2 instead of assuming failure.

2. **Verify**

- `%USERPROFILE%\.codex\zh-cn-patched-active.txt` exists and contains the patched copy path.
- `%USERPROFILE%\.codex\config.toml` contains `localeOverride = "zh-CN"`.

3. **Launch the localized app**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\launch-zh-cn.ps1"
```

Or ask the user to double-click `启动汉化版.bat` / the desktop shortcut `Codex 汉化版`.

4. **Confirm with the user**

After the window opens, ask the user to confirm the left sidebar (新聊天 / 项目 / 计划 / 插件) and the top menus are Chinese. If they cannot tell yet, wait for the app to finish loading.

## Failure handling

- `RESULT: INSTALL_FAIL` containing “无法自动识别” / “无法识别”: the Codex version structure changed. Report the exact snippet and suggest the user open an issue in this repository (include the snippet).
- The patched app does not start: make sure **no** Codex/ChatGPT processes are running (the app is single-instance), then run the launch script again.
- “Already patched” messages: safe to reuse; just launch.

## Cleanup / rollback (only if the user asks)

- Restore English: run `scripts\restore-original.ps1` (or `恢复原版.bat`), then start Codex from the Start menu.
- Full uninstall: `卸载汉化.bat` (admin), which deletes the patched copy, restores config, and removes the desktop shortcut.