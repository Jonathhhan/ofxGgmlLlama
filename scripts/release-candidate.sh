#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if command -v pwsh >/dev/null 2>&1; then
	exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/release-candidate.ps1" "$@"
fi
exec powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/release-candidate.ps1" "$@"
