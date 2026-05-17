param(
	[string]$Endpoint = $(if ($env:OFXGGML_CODEX_BASE_URL) { $env:OFXGGML_CODEX_BASE_URL } else { "http://127.0.0.1:8001/v1" }),
	[string]$Model = $(if ($env:OFXGGML_CODEX_MODEL) { $env:OFXGGML_CODEX_MODEL } else { "local/GLM-4.7-Flash-UD-Q4_K_XL" }),
	[Alias("Profile")]
	[string]$CodexProfile = $(if ($env:OFXGGML_CODEX_PROFILE) { $env:OFXGGML_CODEX_PROFILE } else { "ofxggml_local" }),
	[string]$ConfigPath = $(if ($env:OFXGGML_CODEX_CONFIG_PATH) { $env:OFXGGML_CODEX_CONFIG_PATH } else { "" }),
	[string]$CodexExe = $(if ($env:OFXGGML_CODEX_EXE) { $env:OFXGGML_CODEX_EXE } else { "" }),
	[int]$ModelContextWindow = $(if ($env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW) { [int]$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW } else { 40960 }),
	[int]$ModelAutoCompactTokenLimit = $(if ($env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT } else { 30000 }),
	[int]$ToolOutputTokenLimit = $(if ($env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT } else { 5000 }),
	[Alias("AgentMaxAgents", "MaxAgents")]
	[int]$AgentMaxConcurrentThreads = $(if ($env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS } elseif ($env:OFXGGML_CODEX_AGENT_MAX_AGENTS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_AGENTS } else { 1 }),
	[int]$AgentMaxDepth = $(if ($env:OFXGGML_CODEX_AGENT_MAX_DEPTH) { [int]$env:OFXGGML_CODEX_AGENT_MAX_DEPTH } else { 1 }),
	[int]$AgentMinWaitMs = $(if ($env:OFXGGML_CODEX_AGENT_MIN_WAIT_MS) { [int]$env:OFXGGML_CODEX_AGENT_MIN_WAIT_MS } else { 2500 }),
	[int]$AgentMaxWaitMs = $(if ($env:OFXGGML_CODEX_AGENT_MAX_WAIT_MS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_WAIT_MS } else { 120000 }),
	[int]$AgentDefaultWaitMs = $(if ($env:OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS) { [int]$env:OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS } else { 30000 }),
	[string]$ExpectedMarker = "LOCAL_CODEX_OK",
	[string]$Prompt = "",
	[int]$TimeoutSeconds = 120,
	[switch]$DisableMultiAgentV2,
	[switch]$DryRun,
	[switch]$Json,
	[switch]$SummaryOnly
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$planScript = Join-Path $scriptRoot "plan-local-codex.ps1"

function ConvertTo-CodexSmokeJson {
	param([hashtable]$Value)
	return ($Value | ConvertTo-Json -Depth 8)
}

function Join-CodexArguments {
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

function Invoke-CodexProcess {
	param(
		[string]$Exe,
		[string[]]$Arguments,
		[int]$Timeout
	)

	$tempRoot = [System.IO.Path]::GetTempPath()
	$stamp = [System.Guid]::NewGuid().ToString("N")
	$stdoutPath = Join-Path $tempRoot "ofxggml-codex-smoke-$stamp.out"
	$stderrPath = Join-Path $tempRoot "ofxggml-codex-smoke-$stamp.err"
	try {
		$process = Start-Process `
			-FilePath $Exe `
			-ArgumentList (Join-CodexArguments $Arguments) `
			-RedirectStandardOutput $stdoutPath `
			-RedirectStandardError $stderrPath `
			-NoNewWindow `
			-PassThru
		if (-not $process.WaitForExit([Math]::Max(1, $Timeout) * 1000)) {
			$process.Kill()
			$process.WaitForExit()
			return [pscustomobject]@{
				ExitCode = 124
				TimedOut = $true
				Stdout = if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
				Stderr = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
			}
		}
		return [pscustomobject]@{
			ExitCode = [int]$process.ExitCode
			TimedOut = $false
			Stdout = if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
			Stderr = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
		}
	} finally {
		Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
		Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
	}
}

function Get-CodexAgentText {
	param([string]$Stdout)
	$messages = New-Object System.Collections.Generic.List[string]
	foreach ($line in ($Stdout -split "`r?`n")) {
		$trimmed = $line.Trim()
		if ([string]::IsNullOrWhiteSpace($trimmed)) {
			continue
		}
		try {
			$item = $trimmed | ConvertFrom-Json
			if ($item.type -eq "agent_message" -and $item.message) {
				$messages.Add([string]$item.message)
			} elseif ($item.type -eq "agent_message" -and $item.text) {
				$messages.Add([string]$item.text)
			} elseif ($item.type -eq "item.completed" -and $item.item -and $item.item.type -eq "agent_message" -and $item.item.text) {
				$messages.Add([string]$item.item.text)
			} elseif ($item.type -eq "response_item" -and $item.item -and $item.item.content) {
				foreach ($content in $item.item.content) {
					if ($content.text) {
						$messages.Add([string]$content.text)
					}
				}
			}
		} catch {
			if ($trimmed.Contains($ExpectedMarker)) {
				$messages.Add($trimmed)
			}
		}
	}
	return (($messages -join "`n").Trim())
}

if ([string]::IsNullOrWhiteSpace($Prompt)) {
	$Prompt = "Reply with exactly $ExpectedMarker and do not run any tools."
}

$planArgs = @{
	Endpoint = $Endpoint
	Model = $Model
	Profile = $CodexProfile
	Json = $true
	SummaryOnly = $true
}
if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
	$planArgs.ConfigPath = $ConfigPath
}
if (![string]::IsNullOrWhiteSpace($CodexExe)) {
	$planArgs.CodexExe = $CodexExe
}
$planArgs.ModelContextWindow = $ModelContextWindow
$planArgs.ModelAutoCompactTokenLimit = $ModelAutoCompactTokenLimit
$planArgs.ToolOutputTokenLimit = $ToolOutputTokenLimit
$planArgs.AgentMaxConcurrentThreads = $AgentMaxConcurrentThreads
$planArgs.AgentMaxDepth = $AgentMaxDepth
$planArgs.AgentMinWaitMs = $AgentMinWaitMs
$planArgs.AgentMaxWaitMs = $AgentMaxWaitMs
$planArgs.AgentDefaultWaitMs = $AgentDefaultWaitMs
if ($DisableMultiAgentV2) {
	$planArgs.DisableMultiAgentV2 = $true
}

$planJson = & $planScript @planArgs
if ($LASTEXITCODE -ne 0) {
	throw "Local Codex planner failed with exit code $LASTEXITCODE"
}
$plan = $planJson | ConvertFrom-Json
$resolvedCodex = if ($plan.CodexExe) { [string]$plan.CodexExe } else { "codex" }
$codexMultiAgentV2 = if ($DisableMultiAgentV2) {
	$false
} elseif ($env:OFXGGML_CODEX_MULTI_AGENT_V2) {
	$env:OFXGGML_CODEX_MULTI_AGENT_V2 -ne "0"
} else {
	$true
}
$arguments = @(
	"-a", "never",
	"exec",
	"--json",
	"--ephemeral",
	"--skip-git-repo-check",
	"-p", $CodexProfile,
	"--disable", "apps",
	"--disable", "image_generation",
	"--disable", "browser_use",
	"--disable", "computer_use",
	"--disable", "tool_search",
	"-c", "web_search=`"disabled`"",
	"-c", "model_provider=llama_cpp",
	"-c", "model_context_window=$ModelContextWindow",
	"-c", "model_auto_compact_token_limit=$ModelAutoCompactTokenLimit",
	"-c", "tool_output_token_limit=$ToolOutputTokenLimit",
	"-c", "features.multi_agent_v2.enabled=$(if ($codexMultiAgentV2) { 'true' } else { 'false' })",
	"-c", "features.multi_agent_v2.max_concurrent_threads_per_session=$AgentMaxConcurrentThreads",
	"-c", "features.multi_agent_v2.min_wait_timeout_ms=$AgentMinWaitMs",
	"-c", "features.multi_agent_v2.max_wait_timeout_ms=$AgentMaxWaitMs",
	"-c", "features.multi_agent_v2.default_wait_timeout_ms=$AgentDefaultWaitMs",
	"-c", "agents.max_depth=$AgentMaxDepth",
	"--model", $Model,
	"--sandbox", "read-only",
	$Prompt
)
if (!$codexMultiAgentV2) {
	$arguments = $arguments[0..($arguments.Count - 6)] +
		@("-c", "agents.max_threads=$AgentMaxConcurrentThreads") +
		$arguments[($arguments.Count - 5)..($arguments.Count - 1)]
}

$command = "`"$resolvedCodex`" $(Join-CodexArguments $arguments)"
$baseSummary = @{
	Name = "ofxGgmlLlama local Codex smoke"
	Root = $addonRoot.Path
	Endpoint = $Endpoint
	Model = $Model
	Profile = $CodexProfile
	CodexExe = $resolvedCodex
	ExpectedMarker = $ExpectedMarker
	Command = $command
	PlanReady = [bool]$plan.Ready
	PlanBlockers = @($plan.Blockers)
	ServedModels = $plan.ServedModels
	LocalLlamaServer = $plan.LocalLlamaServer
	SmokeKind = "local-codex-llama-server"
	InferenceCheck = if ($DryRun) { "dry-run" } else { "codex-exec" }
	InferenceChecked = $false
	Passed = $false
}

if ($DryRun) {
	if ($Json) {
		ConvertTo-CodexSmokeJson -Value $baseSummary
	} else {
		Write-Host "ofxGgmlLlama local Codex smoke plan"
		Write-Host "Ready:   $($baseSummary.PlanReady)"
		Write-Host "Codex:   $resolvedCodex"
		Write-Host "Model:   $Model"
		Write-Host "Command: $command"
	}
	exit 0
}

if (!$plan.Ready) {
	throw "Local Codex preflight is not ready: $($baseSummary.PlanBlockers -join '; ')"
}
if (!(Test-Path -LiteralPath $resolvedCodex -PathType Leaf) -and $resolvedCodex -ne "codex") {
	throw "Codex executable was not found: $resolvedCodex"
}

if (-not $Json) {
	Write-Host "==> Running local Codex exec smoke"
}
$started = Get-Date
$result = Invoke-CodexProcess -Exe $resolvedCodex -Arguments $arguments -Timeout $TimeoutSeconds
$elapsedMs = ((Get-Date) - $started).TotalMilliseconds
$agentText = Get-CodexAgentText -Stdout $result.Stdout
$passed = ($result.ExitCode -eq 0 -and !$result.TimedOut -and $agentText.Contains($ExpectedMarker))

$summary = $baseSummary.Clone()
$summary.ElapsedMs = [Math]::Round($elapsedMs, 3)
$summary.ExitCode = [int]$result.ExitCode
$summary.TimedOut = [bool]$result.TimedOut
$summary.InferenceChecked = [bool]$passed
$summary.Passed = [bool]$passed
$summary.AgentText = if ($SummaryOnly) { "" } else { $agentText }
$summary.Stderr = if ($SummaryOnly) { "" } else { $result.Stderr.Trim() }

if ($Json) {
	ConvertTo-CodexSmokeJson -Value $summary
} else {
	Write-Host "Passed:  $passed"
	Write-Host "Elapsed: $([Math]::Round($elapsedMs, 3)) ms"
	if (!$SummaryOnly -and ![string]::IsNullOrWhiteSpace($agentText)) {
		Write-Host "Text:    $agentText"
	}
}

if (!$passed) {
	exit 1
}
