#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
run_ps1="$script_dir/validate-local.ps1"

if command -v pwsh >/dev/null 2>&1; then
	exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$run_ps1" "$@"
fi

if command -v powershell >/dev/null 2>&1; then
	exec powershell -NoProfile -ExecutionPolicy Bypass -File "$run_ps1" "$@"
fi

echo "PowerShell 7+ is required to run validate-local.sh" >&2
exit 1
