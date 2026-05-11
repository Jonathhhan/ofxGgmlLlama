#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stop_ps1="$script_dir/stop-llama-server.ps1"

if command -v pwsh >/dev/null 2>&1; then
	exec pwsh -NoProfile -File "$stop_ps1" "$@"
fi

if command -v powershell >/dev/null 2>&1; then
	exec powershell -NoProfile -File "$stop_ps1" "$@"
fi

echo "Could not find pwsh or powershell." >&2
echo "Install PowerShell 7+, then rerun this script." >&2
exit 1
