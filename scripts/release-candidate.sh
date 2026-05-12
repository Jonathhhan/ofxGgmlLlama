#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v pwsh >/dev/null 2>&1; then
	pwsh -NoProfile -File "$script_dir/release-candidate.ps1" "$@"
elif command -v powershell >/dev/null 2>&1; then
	powershell -NoProfile -ExecutionPolicy Bypass -File "$script_dir/release-candidate.ps1" "$@"
else
	echo "PowerShell 7+ is required to run release-candidate.sh" >&2
	exit 1
fi
