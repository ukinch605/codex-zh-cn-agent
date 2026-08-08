@echo off
setlocal
cd /d "%~dp0"
title »Ö¸´Ó¢ÎÄÔ­°æ Codex
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\restore-original.ps1"
exit /b %errorLevel%