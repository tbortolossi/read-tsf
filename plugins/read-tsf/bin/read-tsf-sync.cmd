@echo off
rem Windows launcher for read-tsf-sync.ps1. No execution-policy bypass: see the .ps1 header.
powershell.exe -NoProfile -File "%~dp0read-tsf-sync.ps1" %*
