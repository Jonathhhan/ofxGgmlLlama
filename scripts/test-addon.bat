@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "RUN_PS1=%SCRIPT_DIR%test-addon.ps1"
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
	pwsh -NoProfile -ExecutionPolicy Bypass -File "%RUN_PS1%" %*
) else (
	powershell -NoProfile -ExecutionPolicy Bypass -File "%RUN_PS1%" %*
)
exit /b %ERRORLEVEL%
