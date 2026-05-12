param(
	[string]$Prompt = "openFrameworks local inference",
	[string]$PromptFile = "",
	[string]$ModelPath = $(if ($env:OFXGGML_EMBEDDING_MODEL) { $env:OFXGGML_EMBEDDING_MODEL } elseif ($env:OFXGGML_TEXT_MODEL) { $env:OFXGGML_TEXT_MODEL } else { "" }),
	[string]$EmbeddingExe = $(if ($env:OFXGGML_LLAMA_EMBEDDING) { $env:OFXGGML_LLAMA_EMBEDDING } else { "" }),
	[string]$GpuLayers = "28",
	[int]$ContextSize = 4096,
	[ValidateSet("none", "mean", "cls", "last", "rank")]
	[string]$Pooling = "mean",
	[int]$Normalize = 2,
	[ValidateSet("", "array", "json", "json+", "raw")]
	[string]$Format = "json",
	[switch]$Raw,
	[switch]$DryRun
)

$ErrorActionPreference = "Stop"

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")

function Resolve-FirstFile {
	param([string[]]$Candidates)
	foreach ($candidate in $Candidates) {
		if (![string]::IsNullOrWhiteSpace($candidate) -and
			(Test-Path -LiteralPath $candidate -PathType Leaf)) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}
	return ""
}

function Find-FirstModel {
	param([string[]]$Directories)
	foreach ($directory in $Directories) {
		if (!(Test-Path -LiteralPath $directory -PathType Container)) {
			continue
		}
		$model = Get-ChildItem -LiteralPath $directory -Filter "*.gguf" -File -ErrorAction SilentlyContinue |
			Sort-Object Name |
			Select-Object -First 1
		if ($model) {
			return $model.FullName
		}
	}
	return ""
}

function Join-ProcessArguments {
	param([string[]]$Arguments)
	$quoted = foreach ($argument in $Arguments) {
		if ($null -eq $argument) {
			'""'
		} elseif ($argument -match '[\s"]') {
			'"' + ($argument.Replace('"', '\"')) + '"'
		} else {
			$argument
		}
	}
	return ($quoted -join " ")
}

if (![string]::IsNullOrWhiteSpace($PromptFile)) {
	if (!(Test-Path -LiteralPath $PromptFile -PathType Leaf)) {
		throw "Prompt file was not found: $PromptFile"
	}
	$PromptFile = (Resolve-Path -LiteralPath $PromptFile).Path
	if (!$PSBoundParameters.ContainsKey("Prompt")) {
		$Prompt = ""
	}
}

if ($PSBoundParameters.ContainsKey("Prompt") -and
	![string]::IsNullOrWhiteSpace($Prompt) -and
	![string]::IsNullOrWhiteSpace($PromptFile)) {
	throw "Pass either -Prompt or -PromptFile, not both."
}

if ([string]::IsNullOrWhiteSpace($EmbeddingExe)) {
	$embeddingName = if ($IsLinux -or $IsMacOS) { "llama-embedding" } else { "llama-embedding.exe" }
	$EmbeddingExe = Resolve-FirstFile @(
		(Join-Path $addonRoot "libs\llama\bin\$embeddingName"),
		(Join-Path $addonRoot "libs\llama.cpp\build\bin\Release\$embeddingName"),
		(Join-Path $addonRoot "libs\llama.cpp\build\bin\$embeddingName"),
		(Join-Path $addonRoot "libs\llama.cpp\build\$embeddingName")
	)
}
if ([string]::IsNullOrWhiteSpace($EmbeddingExe)) {
	throw "Could not find llama-embedding. Build it with scripts\build-llama-server.bat or pass -EmbeddingExe."
}

if ([string]::IsNullOrWhiteSpace($ModelPath)) {
	$ModelPath = Find-FirstModel @(
		(Join-Path $addonRoot "ofxGgmlTextExample\bin\data\models"),
		(Join-Path $addonRoot "ofxGgmlTextExample\bin\data"),
		(Join-Path $addonRoot "ofxGgmlTextExample\models"),
		(Join-Path $addonRoot "ofxGgmlChatExample\bin\data\models"),
		(Join-Path $addonRoot "ofxGgmlChatExample\bin\data"),
		(Join-Path $addonRoot "ofxGgmlChatExample\models"),
		(Join-Path $addonRoot "models"),
		(Join-Path (Split-Path -Parent $addonRoot) "models")
	)
}
if ([string]::IsNullOrWhiteSpace($ModelPath)) {
	throw "Could not find a GGUF model. Pass -ModelPath or set OFXGGML_EMBEDDING_MODEL."
}
if (!(Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
	throw "Model file was not found: $ModelPath"
}

$ModelPath = (Resolve-Path -LiteralPath $ModelPath).Path
$EmbeddingExe = (Resolve-Path -LiteralPath $EmbeddingExe).Path

$outputFormat = if ($Raw) { "raw" } else { $Format }
$arguments = @(
	"-m", $ModelPath,
	"-ngl", $GpuLayers,
	"-c", ([Math]::Max(512, $ContextSize)).ToString(),
	"--pooling", $Pooling,
	"--embd-normalize", $Normalize.ToString()
)

if (![string]::IsNullOrWhiteSpace($outputFormat)) {
	$arguments += @("--embd-output-format", $outputFormat)
}

if (![string]::IsNullOrWhiteSpace($PromptFile)) {
	$arguments += @("-f", $PromptFile)
} else {
	$arguments += @("-p", $Prompt)
}

Write-Host "Running llama-embedding"
Write-Host "  exe:       $EmbeddingExe"
Write-Host "  model:     $ModelPath"
Write-Host "  prompt:    $(if (![string]::IsNullOrWhiteSpace($PromptFile)) { $PromptFile } else { $Prompt })"
Write-Host "  ngl:       $GpuLayers"
Write-Host "  ctx:       $ContextSize"
Write-Host "  pooling:   $Pooling"
Write-Host "  normalize: $Normalize"
Write-Host "  format:    $(if ([string]::IsNullOrWhiteSpace($outputFormat)) { '(default)' } else { $outputFormat })"
Write-Host ""
Write-Host ("`"$EmbeddingExe`" " + (Join-ProcessArguments $arguments))

if ($DryRun) {
	return
}

Write-Host ""
& $EmbeddingExe @arguments
