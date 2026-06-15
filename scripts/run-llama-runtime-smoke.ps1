param(
	[string]$Model = $(if ($env:OFXGGML_TEXT_MODEL) { $env:OFXGGML_TEXT_MODEL } else { "" }),
	[string]$LlamaCli = $(if ($env:OFXGGML_LLAMA_CLI) { $env:OFXGGML_LLAMA_CLI } else { "" }),
	[ValidateSet("cpu", "cuda")]
	[string]$Backend = $(if ($env:OFXGGML_LLAMA_RUNTIME_BACKEND) { $env:OFXGGML_LLAMA_RUNTIME_BACKEND } else { "cpu" }),
	[string]$Prompt = "Reply with exactly OFXGGML_LLAMA_SMOKE_OK and no other words.",
	[int]$MaxTokens = 16,
	[int]$Threads = 4,
	[int]$ContextSize = 512,
	[int]$TimeoutSeconds = 120,
	[switch]$DryRun,
	[switch]$Json,
	[switch]$SummaryOnly
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")

function Write-Step {
	param([string]$Message)
	if (-not $Json) {
		Write-Host "==> $Message"
	}
}

function ConvertTo-SmokeJson {
	param([hashtable]$Value)
	return ($Value | ConvertTo-Json -Depth 6)
}

function Find-LlamaCli {
	if (![string]::IsNullOrWhiteSpace($LlamaCli)) {
		$resolved = Normalize-OfxGgmlPathText $LlamaCli
		if (Test-Path -LiteralPath $resolved -PathType Leaf) {
			return (Resolve-Path -LiteralPath $resolved).Path
		}
		return $resolved
	}

	$cliName = if ($IsLinux -or $IsMacOS) { "llama-cli" } else { "llama-cli.exe" }
	return Resolve-OfxGgmlFirstFile @(
		(Join-Path $addonRoot "libs\llama\bin\$cliName"),
		(Join-Path $addonRoot "libs\llama.cpp\build\bin\Release\$cliName"),
		(Join-Path $addonRoot "libs\llama.cpp\build\bin\$cliName"),
		(Join-Path $addonRoot "libs\llama.cpp\build\$cliName")
	)
}

function Find-SmokeModel {
	if (![string]::IsNullOrWhiteSpace($Model)) {
		$resolved = Normalize-OfxGgmlPathText $Model
		if (Test-Path -LiteralPath $resolved -PathType Leaf) {
			return (Resolve-Path -LiteralPath $resolved).Path
		}
		return $resolved
	}
	return Find-OfxGgmlFirstModel (Get-OfxGgmlModelSearchDirectories `
		-AddonRoot $addonRoot `
		-ExampleRoot (Join-Path $addonRoot "ofxGgmlTextExample") `
		-ExtraExampleNames @("ofxGgmlChatExample", "ofxGgmlEmbeddingExample"))
}

function Join-SmokeArguments {
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

function Invoke-LlamaCliSmoke {
	param(
		[string]$Exe,
		[string[]]$Arguments,
		[int]$Timeout
	)

	$psi = [System.Diagnostics.ProcessStartInfo]::new()
	$psi.FileName = $Exe
	$psi.UseShellExecute = $false
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.CreateNoWindow = $true
	if ($null -ne $psi.ArgumentList) {
		foreach ($argument in $Arguments) {
			[void]$psi.ArgumentList.Add($argument)
		}
	} else {
		$psi.Arguments = Join-SmokeArguments $Arguments
	}

	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $psi
	[void]$process.Start()
	if (-not $process.WaitForExit([Math]::Max(1, $Timeout) * 1000)) {
		$process.Kill()
		$process.WaitForExit()
		return [pscustomobject]@{
			ExitCode = 124
			TimedOut = $true
			Stdout = $process.StandardOutput.ReadToEnd()
			Stderr = $process.StandardError.ReadToEnd()
		}
	}
	$stdout = $process.StandardOutput.ReadToEnd()
	$stderr = $process.StandardError.ReadToEnd()
	return [pscustomobject]@{
		ExitCode = [int]$process.ExitCode
		TimedOut = $false
		Stdout = $stdout
		Stderr = $stderr
	}
}

function Get-SmokeText {
	param([string]$Text)
	if ($Text.Contains("OFXGGML_LLAMA_SMOKE_OK")) {
		return "OFXGGML_LLAMA_SMOKE_OK"
	}
	$lines = @($Text -split "`r?`n" | Where-Object {
		$trimmed = $_.Trim()
		![string]::IsNullOrWhiteSpace($trimmed) -and
		$trimmed -notmatch "^(ggml_|llama_|common_|sampling:|system_info:|build\s*:|main:|load_|print_info:|generate:|Loading model|available commands:|/exit|/regen|/clear|/read|/glob|Exiting|>|modalities\s*:|model\s*:)"
	})
	return (($lines -join "`n").Trim())
}

$resolvedCli = Find-LlamaCli
$resolvedModel = Find-SmokeModel
$gpuLayers = if ($Backend -eq "cuda") { "99" } else { "0" }
$arguments = @(
	"-m", $resolvedModel,
	"-p", $Prompt,
	"-n", ([Math]::Max(1, $MaxTokens)).ToString(),
	"--temp", "0",
	"-c", ([Math]::Max(256, $ContextSize)).ToString(),
	"-t", ([Math]::Max(1, $Threads)).ToString(),
	"-ngl", $gpuLayers,
	"--seed", "1",
	"--log-disable",
	"--no-display-prompt",
	"--no-show-timings",
	"--no-warmup",
	"--simple-io",
	"--color", "off",
	"--single-turn"
)

$plan = @{
	Name = "ofxGgmlLlama runtime smoke"
	Root = $addonRoot.Path
	Executable = $resolvedCli
	Model = $resolvedModel
	Backend = $Backend
	GpuLayers = $gpuLayers
	Threads = [Math]::Max(1, $Threads)
	ContextSize = [Math]::Max(256, $ContextSize)
	MaxTokens = [Math]::Max(1, $MaxTokens)
	Ready = (
		![string]::IsNullOrWhiteSpace($resolvedCli) -and
		(Test-Path -LiteralPath $resolvedCli -PathType Leaf) -and
		![string]::IsNullOrWhiteSpace($resolvedModel) -and
		(Test-Path -LiteralPath $resolvedModel -PathType Leaf)
	)
	Command = if (![string]::IsNullOrWhiteSpace($resolvedCli)) {
		"`"$resolvedCli`" $(Join-SmokeArguments $arguments)"
	} else {
		""
	}
	NextCommands = @(
		"scripts\run-llama-runtime-smoke.bat -DryRun",
		"scripts\run-llama-runtime-smoke.bat -Backend cpu -Json -SummaryOnly",
		"scripts\run-llama-runtime-smoke.bat -Backend cuda -Json -SummaryOnly"
	)
}

if ($DryRun) {
	if ($Json) {
		ConvertTo-SmokeJson -Value $plan
	} else {
		Write-Host "ofxGgmlLlama runtime smoke plan"
		Write-Host "Executable: $resolvedCli"
		Write-Host "Model:      $resolvedModel"
		Write-Host "Backend:    $Backend"
		Write-Host "GpuLayers:  $gpuLayers"
		Write-Host "Ready:      $($plan.Ready)"
		Write-Host "Next:       scripts\run-llama-runtime-smoke.bat -Backend $Backend -Json -SummaryOnly"
	}
	exit 0
}

if ([string]::IsNullOrWhiteSpace($resolvedCli) -or !(Test-Path -LiteralPath $resolvedCli -PathType Leaf)) {
	throw "Could not find llama-cli. Run scripts\build-llama-server.bat or pass -LlamaCli."
}
if ([string]::IsNullOrWhiteSpace($resolvedModel) -or !(Test-Path -LiteralPath $resolvedModel -PathType Leaf)) {
	throw "Could not find a GGUF model. Put one under addons\models, ofxGgmlLlama\models, or pass -Model."
}

Write-Step "Running llama.cpp CLI runtime smoke"
$started = Get-Date
$result = Invoke-LlamaCliSmoke -Exe $resolvedCli -Arguments $arguments -Timeout $TimeoutSeconds
$elapsedMs = ((Get-Date) - $started).TotalMilliseconds
$text = Get-SmokeText $result.Stdout
$expectedMarker = "OFXGGML_LLAMA_SMOKE_OK"
$passed = ($result.ExitCode -eq 0 -and !$result.TimedOut -and $text.Contains($expectedMarker))
$summary = @{
	SummaryOnly = [bool]$SummaryOnly
	Summary = @{
		Passed = [bool]$passed
		Backend = $Backend
		ModelPath = $resolvedModel
		Executable = $resolvedCli
		GpuLayers = $gpuLayers
		Threads = [Math]::Max(1, $Threads)
		MaxTokens = [Math]::Max(1, $MaxTokens)
		ElapsedMs = [Math]::Round($elapsedMs, 3)
		ExitCode = [int]$result.ExitCode
		TimedOut = [bool]$result.TimedOut
		TextLength = [int]$text.Length
		Text = if ($SummaryOnly) { "" } else { $text }
		Stderr = if ($SummaryOnly) { "" } else { $result.Stderr.Trim() }
		Error = if ($passed) { "" } elseif ($result.TimedOut) { "llama-cli timed out" } elseif ($result.ExitCode -ne 0) { "llama-cli exited with code $($result.ExitCode)" } else { "llama-cli did not return the expected smoke marker" }
	}
}

if ($Json) {
	ConvertTo-SmokeJson -Value $summary
} else {
	Write-Host "ofxGgmlLlama runtime smoke"
	Write-Host "Passed:    $passed"
	Write-Host "Backend:   $Backend"
	Write-Host "Model:     $resolvedModel"
	Write-Host "Text:      $text"
	Write-Host "ElapsedMs: $([Math]::Round($elapsedMs, 1))"
	if (!$passed) {
		Write-Host "Error:     $($summary.Summary.Error)"
	}
}

if (!$passed) {
	exit 1
}
