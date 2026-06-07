param(
	[string]$Endpoint = $(if ($env:OFXGGML_CODEX_BASE_URL) { $env:OFXGGML_CODEX_BASE_URL } else { "http://127.0.0.1:8001/v1" }),
	[string]$Model = $(if ($env:OFXGGML_CODEX_MODEL) { $env:OFXGGML_CODEX_MODEL } else { "local/Qwen3.6-27B-Q4_0" }),
	[Alias("Profile")]
	[string]$CodexProfile = $(if ($env:OFXGGML_CODEX_PROFILE) { $env:OFXGGML_CODEX_PROFILE } else { "ofxggml_local" }),
	[string]$ConfigPath = $(if ($env:OFXGGML_CODEX_CONFIG_PATH) { $env:OFXGGML_CODEX_CONFIG_PATH } else { "" }),
	[string]$CodexExe = $(if ($env:OFXGGML_CODEX_EXE) { $env:OFXGGML_CODEX_EXE } else { "" }),
	[int]$ModelContextWindow = $(if ($env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW) { [int]$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW } else { 65536 }),
	[int]$ModelAutoCompactTokenLimit = $(if ($env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT } else { 56000 }),
	[int]$ToolOutputTokenLimit = $(if ($env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT } else { 12000 }),
	[string]$WebSearch = $(if ($env:OFXGGML_CODEX_WEB_SEARCH) { $env:OFXGGML_CODEX_WEB_SEARCH } else { "disabled" }),
	[Alias("AgentMaxAgents", "MaxAgents", "AgentMaxThreads", "MaxAgentThreads")]
	[int]$AgentMaxConcurrentThreads = $(if ($env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS } elseif ($env:OFXGGML_CODEX_AGENT_MAX_THREADS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_THREADS } elseif ($env:OFXGGML_CODEX_AGENT_MAX_AGENTS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_AGENTS } else { 1 }),
	[int]$AgentMaxDepth = $(if ($env:OFXGGML_CODEX_AGENT_MAX_DEPTH) { [int]$env:OFXGGML_CODEX_AGENT_MAX_DEPTH } else { 0 }),
	[string]$ExpectedMarker = "LOCAL_CODEX_OK",
	[string]$Prompt = "",
	[int]$TimeoutSeconds = 120,
	[string]$CodexSandbox = $(if ($env:OFXGGML_CODEX_SANDBOX) { $env:OFXGGML_CODEX_SANDBOX } else { "workspace-write" }),
	[switch]$UseServedModel,
	[switch]$WriteConfigOnly,
	[switch]$SkipConfigWrite,
	[switch]$SkipAgentRoleFiles,
	[switch]$DryRun,
	[switch]$Json,
	[switch]$SummaryOnly,
	[string]$ResultPath = ""
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$planScript = Join-Path $scriptRoot "plan-local-codex.ps1"
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")

function ConvertTo-CodexSmokeJson {
	param([hashtable]$Value)
	return ($Value | ConvertTo-Json -Depth 8)
}

function Write-CodexSmokeJson {
	param([object]$Value)
	$jsonText = ($Value | ConvertTo-Json -Depth 8)
	if (![string]::IsNullOrWhiteSpace($ResultPath)) {
		$parent = Split-Path -Parent $ResultPath
		if (![string]::IsNullOrWhiteSpace($parent) -and !(Test-Path -LiteralPath $parent -PathType Container)) {
			New-Item -ItemType Directory -Path $parent -Force | Out-Null
		}
		Set-Content -LiteralPath $ResultPath -Value $jsonText -Encoding UTF8
	}
	if ($Json) {
		$jsonText
	}
}

function Invoke-CodexProcess {
	param(
		[string]$Exe,
		[string[]]$Arguments,
		[int]$Timeout
	)

	try {
		$processInfo = [System.Diagnostics.ProcessStartInfo]::new()
		$processInfo.FileName = $Exe
		$processInfo.Arguments = Join-OfxGgmlCommandArguments $Arguments
		$processInfo.UseShellExecute = $false
		$processInfo.RedirectStandardOutput = $true
		$processInfo.RedirectStandardError = $true
		$processInfo.CreateNoWindow = $true

		$process = [System.Diagnostics.Process]::new()
		$process.StartInfo = $processInfo
		[void]$process.Start()
		$stdoutTask = $process.StandardOutput.ReadToEndAsync()
		$stderrTask = $process.StandardError.ReadToEndAsync()
		if (-not $process.WaitForExit([Math]::Max(1, $Timeout) * 1000)) {
			try {
				$process.Kill()
			} catch {
			}
			try {
				$process.WaitForExit()
			} catch {
			}
			[void]$stdoutTask.Wait(5000)
			[void]$stderrTask.Wait(5000)
			return [pscustomobject]@{
				ExitCode = 124
				TimedOut = $true
				Stdout = if ($stdoutTask.IsCompleted) { [string]$stdoutTask.Result } else { "" }
				Stderr = if ($stderrTask.IsCompleted) { [string]$stderrTask.Result } else { "" }
			}
		}
		$process.WaitForExit()
		[void]$stdoutTask.Wait(5000)
		[void]$stderrTask.Wait(5000)
		$stdout = if ($stdoutTask.IsCompleted) { [string]$stdoutTask.Result } else { "" }
		$stderr = if ($stderrTask.IsCompleted) { [string]$stderrTask.Result } else { "" }
		return [pscustomobject]@{
			ExitCode = [int]$process.ExitCode
			TimedOut = $false
			Stdout = $stdout
			Stderr = $stderr
		}
	} finally {
		if ($process) {
			$process.Dispose()
		}
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

function ConvertTo-CodexTomlString {
	param([string]$Value)
	return $Value.Replace("\", "\\").Replace('"', '\"')
}

function Remove-CodexTomlSection {
	param(
		[string]$Text,
		[string]$Section
	)

	if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Section)) {
		return $Text
	}
	$escaped = [regex]::Escape($Section)
	$pattern = "(?ms)^\[$escaped\]\s*\r?\n.*?(?=^\[|\z)"
	return ([regex]::Replace($Text, $pattern, "")).TrimEnd()
}

function Get-CodexProviderProfileToml {
	param(
		[string]$ApiRoot,
		[string]$Model,
		[string]$Profile,
		[string]$WebSearch
	)

	$lines = @(
		"[model_providers.llama_cpp]",
		"name = `"llama.cpp local`"",
		"base_url = `"$(ConvertTo-CodexTomlString $ApiRoot)`"",
		"wire_api = `"responses`"",
		"stream_idle_timeout_ms = 10000000",
		"",
		"[profiles.$Profile]",
		"model = `"$(ConvertTo-CodexTomlString $Model)`"",
		"model_provider = `"llama_cpp`"",
		"web_search = `"$(ConvertTo-CodexTomlString $WebSearch)`"",
		"model_reasoning_effort = `"medium`"",
		"model_reasoning_summary = `"none`""
	)
	return (($lines -join "`n") + "`n")
}

function Ensure-CodexProviderProfile {
	param(
		[string]$ConfigFile,
		[string]$ApiRoot,
		[string]$Model,
		[string]$Profile,
		[string]$WebSearch
	)

	$result = [ordered]@{
		ConfigPath = $ConfigFile
		Checked = $false
		Written = $false
		Skipped = @()
		Provider = "llama_cpp"
		Profile = $Profile
		ReadyForLocalAgents = $false
	}
	if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
		$result.Skipped += "config path is empty"
		return [pscustomobject]$result
	}
	if ([string]::IsNullOrWhiteSpace($Model)) {
		$result.Skipped += "model alias is empty"
		return [pscustomobject]$result
	}
	if ([string]::IsNullOrWhiteSpace($Profile)) {
		$result.Skipped += "profile is empty"
		return [pscustomobject]$result
	}

	$result.Checked = $true
	$configDirectory = Split-Path -Parent $ConfigFile
	if (![string]::IsNullOrWhiteSpace($configDirectory)) {
		New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
	}
	$existing = if (Test-Path -LiteralPath $ConfigFile -PathType Leaf) {
		Get-Content -LiteralPath $ConfigFile -Raw
	} else {
		""
	}
	$updated = Remove-CodexTomlSection -Text $existing -Section "model_providers.llama_cpp"
	$updated = Remove-CodexTomlSection -Text $updated -Section "profiles.$Profile"
	$snippet = Get-CodexProviderProfileToml `
		-ApiRoot $ApiRoot `
		-Model $Model `
		-Profile $Profile `
		-WebSearch $WebSearch
	if (![string]::IsNullOrWhiteSpace($updated)) {
		$updated = $updated.TrimEnd() + "`n`n" + $snippet
	} else {
		$updated = $snippet
	}
	Set-Content -LiteralPath $ConfigFile -Value $updated -Encoding UTF8
	$after = Get-Content -LiteralPath $ConfigFile -Raw
	$result.Written = $true
	$result.ReadyForLocalAgents =
		($after -match "\[model_providers\.llama_cpp\]") -and
		($after -match "\[profiles\.$([regex]::Escape($Profile))\]")
	return [pscustomobject]$result
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
	} else {
		$lines += "sandbox_mode = `"workspace-write`""
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
$planArgs.WebSearch = $WebSearch
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
	"--skip-git-repo-check"
)
if ($plan.Config.HasProfile -or !$SkipConfigWrite) {
	$arguments += @("-p", $CodexProfile)
}
$arguments += @(
	Get-OfxGgmlCodexLocalProviderArguments `
		-ApiRoot $resolvedApiRoot `
		-ModelContextWindow $ModelContextWindow `
		-ModelAutoCompactTokenLimit $ModelAutoCompactTokenLimit `
		-ToolOutputTokenLimit $ToolOutputTokenLimit `
		-WebSearch $WebSearch `
		-AgentMaxConcurrentThreads $AgentMaxConcurrentThreads `
		-AgentMaxDepth $AgentMaxDepth
)

if (![string]::IsNullOrWhiteSpace($resolvedModel)) {
	$arguments += @("--model", $resolvedModel)
}
if (![string]::IsNullOrWhiteSpace($CodexSandbox)) {
	$arguments += @("--sandbox", $CodexSandbox)
}
$lastMessagePath = Join-Path ([System.IO.Path]::GetTempPath()) (
	"ofxggml-codex-last-message-" + [System.Guid]::NewGuid().ToString("N") + ".txt")
$arguments += @("--output-last-message", $lastMessagePath)
$arguments += @($Prompt)
$command = "$(Format-OfxGgmlCommandArgument $resolvedCodex) $(Join-OfxGgmlCommandArguments $arguments)"
$agentRoleFiles = [pscustomobject]@{
	ConfigPath = $plan.Config.Path
	Checked = $false
	Written = @()
	Existing = @()
	Skipped = @("pending-smoke")
}
$configWrite = [pscustomobject]@{
	ConfigPath = $plan.Config.Path
	Checked = $true
	Written = $false
	Skipped = @("pending-smoke")
	Provider = "llama_cpp"
	Profile = $CodexProfile
	ReadyForLocalAgents = [bool]($plan.Config.HasProvider -and $plan.Config.HasProfile)
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
	ConfigWrite = $configWrite
	AgentRoleFiles = $agentRoleFiles
	SmokeKind = "local-codex-llama-server"
	InferenceCheck = if ($DryRun) { "dry-run" } else { "codex-exec" }
	InferenceChecked = $false
	Passed = $false
}

if ($DryRun) {
	$baseSummary.ConfigWrite = [pscustomobject]@{
		ConfigPath = $plan.Config.Path
		Checked = $true
		Written = $false
		Skipped = @("dry-run")
		Provider = "llama_cpp"
		Profile = $CodexProfile
		ReadyForLocalAgents = [bool]($plan.Config.HasProvider -and $plan.Config.HasProfile)
	}
	if ($Json) {
		Write-CodexSmokeJson -Value $baseSummary
	} else {
		Write-Host "ofxGgmlLlama local Codex smoke plan"
		Write-Host "Ready:   $($baseSummary.PlanReady)"
		Write-Host "Codex:   $resolvedCodex"
	Write-Host "Model:   $resolvedModel"
		Write-Host "Command: $command"
	}
	exit 0
}

if ($WriteConfigOnly) {
	if ($SkipConfigWrite) {
		throw "-WriteConfigOnly cannot be combined with -SkipConfigWrite"
	}
	$configWrite = Ensure-CodexProviderProfile `
		-ConfigFile $plan.Config.Path `
		-ApiRoot $resolvedApiRoot `
		-Model $resolvedModel `
		-Profile $CodexProfile `
		-WebSearch $WebSearch
	$baseSummary.ConfigWrite = $configWrite
	if (!$configWrite.ReadyForLocalAgents) {
		throw "Codex config was not ready for local agents after write: $($plan.Config.Path)"
	}
	if (!$SkipAgentRoleFiles) {
		$agentRoleFiles = Ensure-CodexAgentRoleFiles -ConfigFile $plan.Config.Path -Model $resolvedModel
		$baseSummary.AgentRoleFiles = $agentRoleFiles
	}
	$baseSummary.InferenceCheck = "config-write"
	$baseSummary.Passed = [bool]$configWrite.ReadyForLocalAgents
	if ($Json) {
		Write-CodexSmokeJson -Value $baseSummary
	} else {
		Write-Host "Wrote Codex local provider/profile config: $($configWrite.ConfigPath)"
	}
	exit 0
}

if (!$SkipConfigWrite) {
	$configWrite = Ensure-CodexProviderProfile `
		-ConfigFile $plan.Config.Path `
		-ApiRoot $resolvedApiRoot `
		-Model $resolvedModel `
		-Profile $CodexProfile `
		-WebSearch $WebSearch
	$baseSummary.ConfigWrite = $configWrite
	if (!$configWrite.ReadyForLocalAgents) {
		throw "Codex config was not ready for local agents after write: $($plan.Config.Path)"
	}
} else {
	$baseSummary.ConfigWrite = [pscustomobject]@{
		ConfigPath = $plan.Config.Path
		Checked = $true
		Written = $false
		Skipped = @("skip-config-write")
		Provider = "llama_cpp"
		Profile = $CodexProfile
		ReadyForLocalAgents = [bool]($plan.Config.HasProvider -and $plan.Config.HasProfile)
	}
}
$localAgentConfigBlocker = "Codex config does not define the llama_cpp provider/profile required by local agents"
$remainingBlockers = if ($baseSummary.ConfigWrite.ReadyForLocalAgents) {
	@($baseSummary.PlanBlockers | Where-Object { $_ -ne $localAgentConfigBlocker })
} else {
	@($baseSummary.PlanBlockers)
}
if ($remainingBlockers.Count -gt 0) {
	throw "Local Codex preflight is not ready: $($remainingBlockers -join '; ')"
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
$lastMessageText = ""
$lastMessageCaptured = $false
if (Test-Path -LiteralPath $lastMessagePath -PathType Leaf) {
	$lastMessageText = (Get-Content -LiteralPath $lastMessagePath -Raw).Trim()
	$lastMessageCaptured = ![string]::IsNullOrWhiteSpace($lastMessageText)
	if ([string]::IsNullOrWhiteSpace($agentText)) {
		$agentText = $lastMessageText
	}
	Remove-Item -LiteralPath $lastMessagePath -Force -ErrorAction SilentlyContinue
}
$markerMatched = $agentText.Contains($ExpectedMarker)
$passed = ($result.ExitCode -eq 0 -and !$result.TimedOut -and $markerMatched)

$summary = $baseSummary.Clone()
$summary.ElapsedMs = [Math]::Round($elapsedMs, 3)
$summary.ExitCode = [int]$result.ExitCode
$summary.TimedOut = [bool]$result.TimedOut
$summary.InferenceChecked = [bool]$passed
$summary.Passed = [bool]$passed
$summary.LastMessageCaptureRequested = $true
$summary.LastMessageCaptured = [bool]$lastMessageCaptured
$summary.MarkerMatched = [bool]$markerMatched
$summary.AgentText = if ($SummaryOnly) { "" } else { $agentText }
$summary.LastMessage = if ($SummaryOnly) { "" } else { $lastMessageText }
$summary.Stderr = if ($SummaryOnly) { "" } else { $result.Stderr.Trim() }

if ($Json) {
	Write-CodexSmokeJson -Value $summary
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
