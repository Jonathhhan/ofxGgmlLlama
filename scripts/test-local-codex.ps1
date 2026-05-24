param(
	[string]$Endpoint = $(if ($env:OFXGGML_CODEX_BASE_URL) { $env:OFXGGML_CODEX_BASE_URL } else { "http://127.0.0.1:8001/v1" }),
	[string]$Model = $(if ($env:OFXGGML_CODEX_MODEL) { $env:OFXGGML_CODEX_MODEL } else { "" }),
	[Alias("Profile")]
	[string]$CodexProfile = $(if ($env:OFXGGML_CODEX_PROFILE) { $env:OFXGGML_CODEX_PROFILE } else { "ofxggml_local" }),
	[string]$ConfigPath = $(if ($env:OFXGGML_CODEX_CONFIG_PATH) { $env:OFXGGML_CODEX_CONFIG_PATH } else { "" }),
	[string]$CodexExe = $(if ($env:OFXGGML_CODEX_EXE) { $env:OFXGGML_CODEX_EXE } else { "" }),
	[int]$ModelContextWindow = $(if ($env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW) { [int]$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW } else { 262144 }),
	[int]$ModelAutoCompactTokenLimit = $(if ($env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT } else { 220000 }),
	[int]$ToolOutputTokenLimit = $(if ($env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT } else { 12000 }),
	[Alias("AgentMaxAgents", "MaxAgents", "AgentMaxThreads", "MaxAgentThreads")]
	[int]$AgentMaxConcurrentThreads = $(if ($env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS } elseif ($env:OFXGGML_CODEX_AGENT_MAX_THREADS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_THREADS } elseif ($env:OFXGGML_CODEX_AGENT_MAX_AGENTS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_AGENTS } else { 0 }),
	[int]$AgentMaxDepth = $(if ($env:OFXGGML_CODEX_AGENT_MAX_DEPTH) { [int]$env:OFXGGML_CODEX_AGENT_MAX_DEPTH } else { 0 }),
	[string]$ExpectedMarker = "LOCAL_CODEX_OK",
	[string]$Prompt = "",
	[int]$TimeoutSeconds = 120,
	[string]$CodexSandbox = $(if ($env:OFXGGML_CODEX_SANDBOX) { $env:OFXGGML_CODEX_SANDBOX } else { "read-only" }),
	[switch]$UseServedModel,
	[switch]$SkipAgentRoleFiles,
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
		$processInfo = [System.Diagnostics.ProcessStartInfo]::new()
		$processInfo.FileName = $Exe
		$processInfo.Arguments = Join-CodexArguments $Arguments
		$processInfo.UseShellExecute = $false
		$processInfo.RedirectStandardOutput = $true
		$processInfo.RedirectStandardError = $true
		$processInfo.CreateNoWindow = $true

		$process = [System.Diagnostics.Process]::new()
		$process.StartInfo = $processInfo
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


function Get-CodexAgentRoleToml {
	param(
		[string]$Role,
		[string]$Model,
		[string]$Provider
	)

	$description = if ($Role -eq "explorer") {
		"Read-only local codebase explorer using llama.cpp."
	} else {
		"Execution-focused local worker using llama.cpp."
	}
	$instructions = if ($Role -eq "explorer") {
		"Use the explorer role for narrow, read-only codebase questions. Use rg first, read exact files before answering, cite paths or lines when useful, and return concise findings. Do not edit files and avoid spawning more agents unless explicitly asked."
	} else {
		"Use the worker role for bounded code changes. Read local patterns first, follow openFrameworks addon conventions, preserve existing dirty files, keep edits scoped, use apply_patch for manual edits, run the smallest useful validation, and report residual risk."
	}
	$lines = @(
		"# Generated by ofxGgmlLlama test-local-codex.ps1.",
		"name = `"$Role`"",
		"description = `"$description`"",
		"model = `"$Model`"",
		"model_provider = `"$Provider`""
	)
	if ($Role -eq "explorer") {
		$lines += "sandbox_mode = `"read-only`""
	}
	$lines += "developer_instructions = `"$instructions`""
	return (($lines -join "`n") + "`n")
}

function Ensure-CodexAgentRoleFiles {
	param(
		[string]$ConfigFile,
		[string]$Model,
		[string]$Provider = "llama_cpp"
	)

	$result = [ordered]@{
		ConfigPath = $ConfigFile
		Checked = $false
		Written = @()
		Existing = @()
		Skipped = @()
	}
	if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
		$result.Skipped += "config path is empty"
		return [pscustomobject]$result
	}
	if ([string]::IsNullOrWhiteSpace($Model)) {
		$result.Skipped += "model alias is empty"
		return [pscustomobject]$result
	}
	$result.Checked = $true
	$configDirectory = Split-Path -Parent $ConfigFile
	$agentDirectory = Join-Path $configDirectory "agents"
	$roles = @(
		@{ Role = "explorer"; File = Join-Path $agentDirectory "explorer.toml" },
		@{ Role = "worker"; File = Join-Path $agentDirectory "worker.toml" }
	)
	foreach ($role in $roles) {
		New-Item -ItemType Directory -Path (Split-Path -Parent $role.File) -Force | Out-Null
		Set-Content -LiteralPath $role.File -Value (Get-CodexAgentRoleToml -Role $role.Role -Model $Model -Provider $Provider) -Encoding UTF8
		if (Test-Path -LiteralPath $role.File -PathType Leaf) {
			$result.Written += $role.File
		}
	}
	return [pscustomobject]$result
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
if ($UseServedModel) {
	$planArgs.UseServedModel = $true
}

$planJson = & $planScript @planArgs
if ($LASTEXITCODE -ne 0) {
	throw "Local Codex planner failed with exit code $LASTEXITCODE"
}
$plan = $planJson | ConvertFrom-Json
$resolvedCodex = if ($plan.CodexExe) { [string]$plan.CodexExe } else { "codex" }
$resolvedModel = if ($plan.Model) { [string]$plan.Model } else { $Model }
$resolvedApiRoot = if ($plan.ApiRoot) { [string]$plan.ApiRoot } else { $Endpoint.TrimEnd("/") }
$arguments = @(
	"-a", "never",
	"exec",
	"--json",
	"--ephemeral",
	"--skip-git-repo-check",
	"--disable", "apps",
	"--disable", "image_generation",
	"--disable", "browser_use",
	"--disable", "computer_use",
	"--disable", "tool_search",
	"-c", "web_search=`"live`"",
	"-c", "model_provider=llama_cpp",
	"-c", "model_providers.llama_cpp.name=`"llama.cpp local`"",
	"-c", "model_providers.llama_cpp.base_url=`"$resolvedApiRoot`"",
	"-c", "model_providers.llama_cpp.wire_api=`"responses`"",
	"-c", "model_providers.llama_cpp.stream_idle_timeout_ms=10000000",
	"-c", "model_context_window=$ModelContextWindow",
	"-c", "model_auto_compact_token_limit=$ModelAutoCompactTokenLimit",
	"-c", "tool_output_token_limit=$ToolOutputTokenLimit",
	"-c", "model_reasoning_effort=medium",
	"-c", "model_reasoning_summary=none",
	"-c", "hide_agent_reasoning=true"
)
if ($plan.Config.HasProfile) {
	$arguments = @("-a", "never", "exec", "--json", "--ephemeral", "--skip-git-repo-check", "-p", $CodexProfile) + @($arguments | Select-Object -Skip 6)
}
if ($AgentMaxConcurrentThreads -gt 0) {
	$arguments += @("-c", "agents.max_threads=$AgentMaxConcurrentThreads")
}
if ($AgentMaxDepth -gt 0) {
	$arguments += @("-c", "agents.max_depth=$AgentMaxDepth")
}

if (![string]::IsNullOrWhiteSpace($resolvedModel)) {
	$arguments += @("--model", $resolvedModel)
}
if (![string]::IsNullOrWhiteSpace($CodexSandbox)) {
	$arguments += @("--sandbox", $CodexSandbox)
}
$arguments += @($Prompt)
$command = "`"$resolvedCodex`" $(Join-CodexArguments $arguments)"
$agentRoleFiles = [pscustomobject]@{
	ConfigPath = $plan.Config.Path
	Checked = $false
	Written = @()
	Existing = @()
	Skipped = @("pending-smoke")
}

$baseSummary = @{
	Name = "ofxGgmlLlama local Codex smoke"
	Root = $addonRoot.Path
	Endpoint = $Endpoint
	Model = $resolvedModel
	Profile = $CodexProfile
	CodexExe = $resolvedCodex
	ExpectedMarker = $ExpectedMarker
	Command = $command
	PlanReady = [bool]$plan.Ready
	PlanBlockers = @($plan.Blockers)
	SuggestedModel = if ($plan.SuggestedModel) { [string]$plan.SuggestedModel } else { "" }
	ServedModels = $plan.ServedModels
	LocalLlamaServer = $plan.LocalLlamaServer
	AgentRoleFiles = $agentRoleFiles
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
	Write-Host "Model:   $resolvedModel"
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

if (!$SkipAgentRoleFiles) {
	$agentRoleFiles = Ensure-CodexAgentRoleFiles -ConfigFile $plan.Config.Path -Model $resolvedModel
	$baseSummary.AgentRoleFiles = $agentRoleFiles
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
