@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "RUN_PS1=%SCRIPT_DIR%release-candidate.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RUN_PS1%" %*
exit /b %ERRORLEVEL%
