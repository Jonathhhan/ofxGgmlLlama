param(
	[switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$releaseCandidate = Join-Path $scriptRoot "dev\release-candidate.ps1"

& $releaseCandidate @PSBoundParameters
if (!$?) {
	throw "release-candidate.ps1 failed."
}
