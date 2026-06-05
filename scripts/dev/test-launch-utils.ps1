param()

$ErrorActionPreference = "Stop"

. (Join-Path (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")) "ofxGgml-launch-utils.ps1")

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Assert-Equal {
	param(
		[object]$Actual,
		[object]$Expected,
		[string]$Label
	)
	if ($Actual -ne $Expected) {
		throw "$Label expected '$Expected' but got '$Actual'"
	}
}

function Assert-True {
	param(
		[bool]$Value,
		[string]$Label
	)
	if (!$Value) {
		throw "$Label expected true"
	}
}

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$scratchRoot = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ofxGgmlLlama-launch-smoke")
if (Test-Path -LiteralPath $scratchRoot) {
	Remove-Item -LiteralPath $scratchRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null

Write-Step "Checking path normalization"
Assert-Equal (Normalize-OfxGgmlPathText '  "C:\models\local.gguf"  ') "C:\models\local.gguf" "quoted path normalization"
Assert-Equal (Normalize-OfxGgmlPathText "   ") "" "blank path normalization"

Write-Step "Checking local model aliases"
Assert-Equal (Get-OfxGgmlLocalModelAlias "C:\models\local model Q4.gguf") "local/local-model-Q4" "local model alias slug"
Assert-Equal (Get-OfxGgmlLocalModelAlias "C:\models\dry-run-model.gguf") "local/dry-run-model" "local model alias filename"
Assert-Equal (Get-OfxGgmlLocalModelAlias "") "" "empty local model alias"

Write-Step "Checking first-file resolution"
$fileA = Join-Path $scratchRoot "a.txt"
New-Item -ItemType File -Path $fileA | Out-Null
Assert-Equal `
	(Resolve-OfxGgmlFirstFile @((Join-Path $scratchRoot "missing.txt"), $fileA)) `
	(Resolve-Path -LiteralPath $fileA).Path `
	"first existing file"
Assert-Equal (Resolve-OfxGgmlFirstFile @()) "" "empty first-file candidates"

Write-Step "Checking model discovery order"
$modelDirA = Join-Path $scratchRoot "models-a"
$modelDirB = Join-Path $scratchRoot "models-b"
New-Item -ItemType Directory -Force -Path $modelDirA, $modelDirB | Out-Null
$modelB = Join-Path $modelDirB "b-model.gguf"
$modelA = Join-Path $modelDirB "a-model.gguf"
New-Item -ItemType File -Path $modelB, $modelA | Out-Null
Assert-Equal `
	(Find-OfxGgmlFirstModel @($modelDirA, $modelDirB)) `
	(Resolve-Path -LiteralPath $modelA).Path `
	"first model sorted by name in first populated directory"
$uniqueModelDirs = @(Get-OfxGgmlUniqueDirectories @($modelDirB, $modelDirB, ""))
Assert-Equal $uniqueModelDirs.Count 1 "unique model directory count"
$modelFiles = @(Get-OfxGgmlModelFiles @($modelDirA, $modelDirB, $modelDirB))
Assert-Equal $modelFiles.Count 2 "deduplicated model file enumeration count"
Assert-Equal $modelFiles[0].FullName (Resolve-Path -LiteralPath $modelA).Path "model file enumeration sorted first"
Assert-Equal $modelFiles[1].FullName (Resolve-Path -LiteralPath $modelB).Path "model file enumeration sorted second"

Write-Step "Checking model search directory layout"
$exampleRoot = Join-Path $scratchRoot "Example"
$searchDirs = Get-OfxGgmlModelSearchDirectories `
	-AddonRoot $scratchRoot `
	-ExampleRoot $exampleRoot `
	-ExtraExampleNames @("OtherExample")
Assert-Equal $searchDirs[0] (Join-Path $exampleRoot "bin\data") "example bin data search dir"
Assert-Equal $searchDirs[1] (Join-Path $exampleRoot "bin\data\models") "example bin data models search dir"
Assert-Equal $searchDirs[2] (Join-Path $exampleRoot "models") "example models search dir"
Assert-True ($searchDirs -contains (Join-Path $scratchRoot "models")) "addon models search dir"
Assert-True ($searchDirs -contains (Join-Path (Split-Path -Parent $scratchRoot) "models")) "sibling models search dir"

Write-Step "Checking llama CLI discovery"
$exampleCliRoot = Join-Path $scratchRoot "ExampleCli"
$llamaBin = Join-Path $scratchRoot "libs\llama\bin"
New-Item -ItemType Directory -Force -Path $llamaBin, $exampleCliRoot | Out-Null
$cliName = if (($env:OS -eq "Windows_NT") -or ($PSVersionTable.PSEdition -eq "Desktop" -and !$IsLinux -and !$IsMacOS)) {
	"llama-cli.exe"
} else {
	"llama-cli"
}
$cliPath = Join-Path $llamaBin $cliName
New-Item -ItemType File -Path $cliPath | Out-Null
Assert-Equal `
	(Find-OfxGgmlLlamaCli -AddonRoot $scratchRoot -ExampleRoot $exampleCliRoot) `
	(Resolve-Path -LiteralPath $cliPath).Path `
	"bundled llama CLI discovery"

Write-Step "Checking server endpoint parsing"
$endpoint = Get-OfxGgmlServerEndpoint "http://localhost:9090/v1"
Assert-Equal $endpoint.HostName "localhost" "endpoint host"
Assert-Equal $endpoint.Port 9090 "endpoint port"

Assert-True (Test-OfxGgmlLocalServerUrl "https://example.com") "remote server URL should not be probed as local"

Write-Step "Checking Codex launch arguments"
$codexArgs = @(
	Get-OfxGgmlCodexLocalProviderArguments `
		-ApiRoot "http://127.0.0.1:9001/v1" `
		-ModelContextWindow 40960 `
		-ModelAutoCompactTokenLimit 30000 `
		-ToolOutputTokenLimit 5000 `
		-AgentMaxConcurrentThreads 2 `
		-AgentMaxDepth 3
)
Assert-True ($codexArgs -contains "--disable") "Codex launch args include tool guard switches"
Assert-True ($codexArgs -contains "web_search=`"live`"") "Codex launch args include web search override"
Assert-True ($codexArgs -contains "model_provider=llama_cpp") "Codex launch args include provider override"
Assert-True ($codexArgs -contains "model_providers.llama_cpp.base_url=`"http://127.0.0.1:9001/v1`"") "Codex launch args include endpoint override"
Assert-True ($codexArgs -contains "model_context_window=40960") "Codex launch args include context window"
Assert-True ($codexArgs -contains "agents.max_threads=2") "Codex launch args include agent thread cap"
Assert-True ($codexArgs -contains "agents.max_depth=3") "Codex launch args include agent depth cap"

$codexGuardOnlyArgs = @(
	Get-OfxGgmlCodexLocalProviderArguments `
		-SkipProviderOverrides `
		-AgentMaxConcurrentThreads 1
)
Assert-True ($codexGuardOnlyArgs -contains "web_search=`"live`"") "Codex guard-only args keep tool compatibility overrides"
Assert-True ($codexGuardOnlyArgs -notcontains "model_provider=llama_cpp") "Codex guard-only args omit provider override"
Assert-True ($codexGuardOnlyArgs -contains "agents.max_threads=1") "Codex guard-only args keep agent cap"

Write-Step "Launch utility coverage passed"
