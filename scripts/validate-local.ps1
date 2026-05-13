param()

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Assert-Path {
	param(
		[string]$Path,
		[string]$Label,
		[switch]$Directory
	)

	if ($Directory) {
		if (!(Test-Path -LiteralPath $Path -PathType Container)) {
			throw "$Label was not found: $Path"
		}
	} elseif (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
		throw "$Label was not found: $Path"
	}
}

function Assert-FileContains {
	param(
		[string]$Path,
		[string]$Pattern,
		[string]$Label
	)
	$content = Get-Content -LiteralPath $Path -Raw
	if ($content -notmatch $Pattern) {
		throw "$Label did not contain expected pattern: $Pattern"
	}
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Split-Path -Parent $scriptRoot
$addonsRoot = Split-Path -Parent $addonRoot

Write-Step "Checking addon skeleton"
Assert-Path (Join-Path $addonRoot "addon_config.mk") "addon config"
Assert-Path (Join-Path $addonRoot "README.md") "README"
Assert-Path (Join-Path $addonRoot "LICENSE") "license"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlLlama.h") "public header"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlLlamaVersion.h") "version header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlamaVersion.h") "OFXGGML_LLAMA_VERSION_STRING" "version header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlama.h") "ofxGgmlLlamaVersion.h" "public header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlama.h") "ofxGgmlLlamaCliTextBackend.h" "public header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlama.h") "ofxGgmlLlamaServerTextBackend.h" "public header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlama.h") "ofxGgmlLlamaServerEmbeddingBackend.h" "public header"
Assert-FileContains (Join-Path $addonRoot "addon_config.mk") "ADDON_DEPENDENCIES\s*\+=\s*ofxGgmlCore" "addon config"
Assert-FileContains (Join-Path $addonRoot "addon_config.mk") "\.\./ofxGgmlCore/src" "addon config"
Assert-Path (Join-Path $addonRoot "tests\CMakeLists.txt") "test CMakeLists"
Assert-Path (Join-Path $addonRoot "tests\test_main.cpp") "test source"

Write-Step "Checking dependency layout"
Assert-Path (Join-Path $addonsRoot "ofxGgmlCore") "sibling ofxGgmlCore addon" -Directory

Write-Step "Checking example layout"
foreach ($example in @("ofxGgmlTextExample", "ofxGgmlChatExample", "ofxGgmlEmbeddingExample")) {
	$exampleRoot = Join-Path $addonRoot $example
	Assert-Path $exampleRoot "$example root" -Directory
	Assert-Path (Join-Path $exampleRoot "addons.make") "$example addons.make"
	Assert-Path (Join-Path $exampleRoot "src\main.cpp") "$example main.cpp"
	Assert-Path (Join-Path $exampleRoot "src\ofApp.h") "$example ofApp.h"
	Assert-Path (Join-Path $exampleRoot "src\ofApp.cpp") "$example ofApp.cpp"
}

foreach ($scriptName in @(
	"build-example.ps1",
	"build-llama-server.ps1",
	"doctor-llama.ps1",
	"start-llama-server.ps1",
	"stop-llama-server.ps1",
	"status-llama-server.ps1",
	"list-models.ps1",
	"run-example.ps1",
	"test-doctor-llama.ps1",
	"dev\release-candidate.ps1",
	"dev\test-addon.ps1",
	"dev\test-launch-utils.ps1",
	"dev\test-release-checklist.ps1",
	"dev\test-launch-dry-run.ps1",
	"dev\test-artifact-hygiene.ps1")) {
	Assert-Path (Join-Path $scriptRoot $scriptName) "$scriptName"
}

Write-Step "Checking generated artifact hygiene"
& (Join-Path $scriptRoot "dev\test-artifact-hygiene.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Artifact hygiene failed with exit code $LASTEXITCODE"
}

Write-Step "Checking launch utility helpers"
& (Join-Path $scriptRoot "dev\test-launch-utils.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Launch utility helper tests failed with exit code $LASTEXITCODE"
}

Write-Step "Checking release checklist commands"
& (Join-Path $scriptRoot "dev\test-release-checklist.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Release checklist command tests failed with exit code $LASTEXITCODE"
}

Write-Step "Checking generated project repair"
& (Join-Path $scriptRoot "dev\test-example-project-repair.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Generated project repair tests failed with exit code $LASTEXITCODE"
}

Write-Step "Checking launch dry-runs"
& (Join-Path $scriptRoot "dev\test-launch-dry-run.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Launch dry-runs failed with exit code $LASTEXITCODE"
}

Write-Step "Checking Llama doctor"
& (Join-Path $scriptRoot "test-doctor-llama.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Llama doctor smoke test failed with exit code $LASTEXITCODE"
}

Write-Step "Running headless tests"
& (Join-Path $scriptRoot "dev\test-addon.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Headless tests failed with exit code $LASTEXITCODE"
}

Write-Step "ofxGgmlLlama local validation passed"
