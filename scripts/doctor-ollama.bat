@echo off
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0doctor-ollama.ps1" %*
