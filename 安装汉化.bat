@echo off
setlocal
cd /d "%~dp0"
net session >nul 2>&1
if not %errorLevel%==0 (
    echo.
    echo   需要管理员权限，正在请求 UAC 提升...
    echo   请在弹窗中点击「是」以继续。
    echo.
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b 0
)
title Codex 一键汉化安装
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-zh-cn.ps1" -Action menu
exit /b %errorLevel%