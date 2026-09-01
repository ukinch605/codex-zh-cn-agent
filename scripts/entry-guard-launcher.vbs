' Entry guard hidden launcher: prevents console flash from scheduled task triggers.
' The registered task runs wscript.exe with this file; window style 0 = fully hidden.
Option Explicit
Dim shell, dir, ps1, args
Set shell = CreateObject("WScript.Shell")
dir = Left(WScript.ScriptFullName, Len(WScript.ScriptFullName) - Len(WScript.ScriptName))
ps1 = dir & "entry-guard.ps1"
args = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
shell.Run args, 0, False