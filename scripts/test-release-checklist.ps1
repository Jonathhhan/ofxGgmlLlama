param()

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$checklistPath = Join-Path $addonRoot "docs\RELEASE_CHECKLIST.md"

if (!(Test-Path -LiteralPath $checklistPath -PathType Leaf)) {
	throw "Release checklist was not found: $checklistPath"
}

$content = Get-Content -LiteralPath $checklistPath -Raw
$matches = [regex]::Matches($content, '(?<![\w./-])(?:\.\/)?scripts[\\/][A-Za-z0-9_.-]+')
$scriptRefs = @($matches | ForEach-Object {
	$_.Value.TrimStart(".", "/", "\") -replace "/", "\"
} | Sort-Object -Unique)

if ($scriptRefs.Count -eq 0) {
	throw "Release checklist does not reference any scripts."
}

Write-Step "Checking release checklist script references"
foreach ($scriptRef in $scriptRefs) {
	$path = Join-Path $addonRoot $scriptRef
	if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
		throw "Release checklist references missing script: $scriptRef"
	}
}

foreach ($required in @(
	"scripts\build-llama-server.bat",
	"scripts\build-llama-server.sh",
	"scripts\list-models.bat",
	"scripts\list-models.sh",
	"scripts\run-text-example.bat",
	"scripts\run-chat-example.bat",
	"scripts\run-embedding-example.bat",
	"scripts\validate-local.bat",
	"scripts\validate-local.sh")) {
	if ($scriptRefs -notcontains $required) {
		throw "Release checklist is missing required command: $required"
	}
}

Write-Step "Release checklist command coverage passed"
