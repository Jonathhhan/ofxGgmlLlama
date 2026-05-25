@echo off
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0install-ollama.ps1" %*
