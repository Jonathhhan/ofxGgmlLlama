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
if ($json.SmokeKind -ne "model-backed-cli-text" -or $json.InferenceChecked) {
	throw "Llama runtime smoke JSON did not expose dry-run inference smoke metadata."
}
if (($json.NextCommands -join "`n") -notmatch "run-llama-runtime-smoke\.bat -Backend cpu") {
	throw "Llama runtime smoke JSON did not include the CPU runtime command."
}

$modelJsonOutput = & (Join-Path $scriptRoot "list-models.ps1") -Json -SummaryOnly *>&1 | ForEach-Object { $_.ToString() }
if ($LASTEXITCODE -ne 0) {
	throw "list-models.ps1 -Json -SummaryOnly failed."
}
$modelJson = ($modelJsonOutput -join "`n") | ConvertFrom-Json
if (!$modelJson.SummaryOnly -or !$modelJson.Summary) {
	throw "list-models summary JSON did not expose the compact summary contract."
}
foreach ($property in @("ModelCount", "TextModelCount", "EmbeddingModelCount", "TinyTextModelCount", "HasTinyTextModel", "FirstTinyTextModel")) {
	if (!$modelJson.Summary.PSObject.Properties[$property]) {
		throw "list-models summary JSON did not include $property."
	}
}
if ($modelJson.PSObject.Properties["Models"]) {
	throw "list-models summary JSON should omit the full model list."
}

if ($modelJson.Summary.HasTinyTextModel -and [string]::IsNullOrWhiteSpace($modelJson.Summary.FirstTinyTextModel) -eq $false) {
	$smokeOutput = & $smokeScript -Backend cpu -Model $modelJson.Summary.FirstTinyTextModel -SummaryOnly -Json -MaxTokens 4 -Threads 2 *>&1 | ForEach-Object { $_.ToString() }
	if ($LASTEXITCODE -ne 0) {
		throw "run-llama-runtime-smoke.ps1 failed for tiny model inference smoke."
	}
	$smokeJson = ($smokeOutput -join "`n") | ConvertFrom-Json
	if (!$smokeJson.Summary.Passed) {
		throw "Llama runtime smoke execution did not pass for tiny model: $($smokeJson.Summary.Error)"
	}
	if (!$smokeJson.Summary.InferenceChecked -or $smokeJson.Summary.Backend -ne "cpu" -or $smokeJson.Summary.SmokeKind -ne "model-backed-cli-text") {
		throw "Llama runtime smoke inference evidence did not include expected evidence contract fields."
	}
} else {
	Write-Host "No tiny text model detected in local model search; skipping live runtime inference smoke."
}

Write-Host "Llama runtime smoke contract passed"
