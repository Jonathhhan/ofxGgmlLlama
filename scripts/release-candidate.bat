@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0release-candidate.ps1" %*
