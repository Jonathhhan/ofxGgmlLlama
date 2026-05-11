@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "TEST_PS1=%SCRIPT_DIR%test-launch-dry-run.ps1"

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%TEST_PS1%" %*
exit /b %ERRORLEVEL%
