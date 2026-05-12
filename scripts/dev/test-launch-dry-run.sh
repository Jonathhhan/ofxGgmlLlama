#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_ps1="$script_dir/test-launch-dry-run.ps1"

if command -v pwsh >/dev/null 2>&1; then
	pwsh -NoProfile -File "$test_ps1" "$@"
elif command -v powershell >/dev/null 2>&1; then
	powershell -NoProfile -File "$test_ps1" "$@"
else
	echo "PowerShell 7+ is required to run test-launch-dry-run.ps1" >&2
	exit 1
fi
