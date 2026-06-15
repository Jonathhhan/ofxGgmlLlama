param()

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$smokeScript = Join-Path $scriptRoot "run-llama-runtime-smoke.ps1"

$textOutput = & $smokeScript -DryRun -Backend cpu *>&1 | ForEach-Object { $_.ToString() }
if ($LASTEXITCODE -ne 0) {
	throw "run-llama-runtime-smoke.ps1 -DryRun failed."
}
$text = $textOutput -join "`n"
foreach ($expected in @(
	"ofxGgmlLlama runtime smoke plan",
	"Executable:",
	"Model:",
	"Backend:    cpu",
	"Ready:"
)) {
	if ($text -notmatch [regex]::Escape($expected)) {
		throw "Llama runtime smoke dry-run output did not contain expected text: $expected"
	}
}

$jsonOutput = & $smokeScript -DryRun -Backend cuda -Json -SummaryOnly *>&1 | ForEach-Object { $_.ToString() }
if ($LASTEXITCODE -ne 0) {
	throw "run-llama-runtime-smoke.ps1 -DryRun -Json failed."
}
$json = ($jsonOutput -join "`n") | ConvertFrom-Json
if ($json.Name -ne "ofxGgmlLlama runtime smoke") {
	throw "Llama runtime smoke JSON did not include the expected Name."
}
if ($json.Backend -ne "cuda" -or $json.GpuLayers -ne "99") {
	throw "Llama runtime smoke JSON did not preserve CUDA backend planning."
}
if (($json.NextCommands -join "`n") -notmatch "run-llama-runtime-smoke\.bat -Backend cpu") {
	throw "Llama runtime smoke JSON did not include the CPU runtime command."
}

Write-Host "Llama runtime smoke contract passed"
