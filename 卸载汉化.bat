@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-zh-cn.ps1" -Action uninstall
exit /b %errorLevel%
