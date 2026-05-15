#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v pwsh >/dev/null 2>&1; then
	exec pwsh -NoProfile -File "$SCRIPT_DIR/run-llama-runtime-smoke.ps1" "$@"
fi
exec powershell -NoProfile -File "$SCRIPT_DIR/run-llama-runtime-smoke.ps1" "$@"
