@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-llama-runtime-smoke.ps1" %*
