@echo off
rem Collects system information for bug reports.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose.ps1" %*
