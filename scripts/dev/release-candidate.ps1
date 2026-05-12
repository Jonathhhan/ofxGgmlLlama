param(
	[switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Invoke-Checked {
	param(
		[string]$Label,
		[string]$Command,
		[string[]]$Arguments = @()
	)
	Write-Step $Label
	& $Command @Arguments
	if ($LASTEXITCODE -ne 0) {
		throw "$Label failed with exit code $LASTEXITCODE"
	}
}

function Get-GitLines {
	param([string[]]$Arguments)
	$output = & git @Arguments 2>&1
	if ($LASTEXITCODE -ne 0) {
		throw "git $($Arguments -join ' ') failed: $($output -join "`n")"
	}
	return @($output | ForEach-Object { $_.ToString() })
}

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")

Push-Location $addonRoot
try {
	Invoke-Checked "Running local validation" (Join-Path $scriptRoot "validate-local.ps1")

	Write-Step "Checking release docs"
	foreach ($path in @(
		"CHANGELOG.md",
		"docs\MIGRATION.md",
		"docs\RELEASE_CHECKLIST.md",
		"docs\RELEASE_NOTES_TEMPLATE.md",
		"docs\RELEASE_POLICY.md")) {
		if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
			throw "Required release document is missing: $path"
		}
	}

	Write-Step "Checking staged changes"
	$staged = Get-GitLines @("diff", "--cached", "--name-only")
	if ($staged.Count -gt 0) {
		throw "Release candidate check requires an empty index. Staged files:`n$($staged -join "`n")"
	}

	Write-Step "Checking working tree status"
	$status = Get-GitLines @("status", "--short")
	if ($status.Count -gt 0 -and !$AllowDirty) {
		throw "Working tree has uncommitted changes. Commit them or rerun with -AllowDirty:`n$($status -join "`n")"
	}

	Write-Step "Checking generated artifact status"
	Invoke-Checked "Artifact hygiene" (Join-Path $scriptRoot "dev\test-artifact-hygiene.ps1")

	Write-Step "Release candidate pass completed"
} finally {
	Pop-Location
}
