param(
	[string]$Endpoint = $(if ($env:OFXGGML_CODEX_BASE_URL) { $env:OFXGGML_CODEX_BASE_URL } else { "http://127.0.0.1:8001/v1" }),
	[string]$Model = $(if ($env:OFXGGML_CODEX_MODEL) { $env:OFXGGML_CODEX_MODEL } else { "" }),
	[string]$Profile = $(if ($env:OFXGGML_CODEX_PROFILE) { $env:OFXGGML_CODEX_PROFILE } else { "ofxggml_local" }),
	[string]$ConfigPath = $(if ($env:OFXGGML_CODEX_CONFIG_PATH) { $env:OFXGGML_CODEX_CONFIG_PATH } else { "" }),
	[string]$CodexExe = $(if ($env:OFXGGML_CODEX_EXE) { $env:OFXGGML_CODEX_EXE } else { "" }),
	[int]$ModelContextWindow = $(if ($env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW) { [int]$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW } else { 65536 }),
	[int]$ModelAutoCompactTokenLimit = $(if ($env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT } else { 50000 }),
	[int]$ToolOutputTokenLimit = $(if ($env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT } else { 8000 }),
	[Alias("AgentMaxAgents", "MaxAgents", "AgentMaxThreads", "MaxAgentThreads")]
	[int]$AgentMaxConcurrentThreads = $(if ($env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS } elseif ($env:OFXGGML_CODEX_AGENT_MAX_THREADS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_THREADS } elseif ($env:OFXGGML_CODEX_AGENT_MAX_AGENTS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_AGENTS } else { 1 }),
	[int]$AgentMaxDepth = $(if ($env:OFXGGML_CODEX_AGENT_MAX_DEPTH) { [int]$env:OFXGGML_CODEX_AGENT_MAX_DEPTH } else { 1 }),
	[switch]$UseServedModel,
	[int]$TimeoutSeconds = 2,
	[switch]$Json,
	[switch]$SummaryOnly,
	[switch]$Strict
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")

function Normalize-Text {
	param([string]$Value)
	if ($null -eq $Value) {
		return ""
	}
	$trimmed = $Value.Trim()
	if ($trimmed.Length -ge 2 -and $trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
		return $trimmed.Substring(1, $trimmed.Length - 2)
	}
	return $trimmed
}

function Resolve-ConfigPath {
	param([string]$ExplicitPath)
	$explicit = Normalize-Text $ExplicitPath
	if (![string]::IsNullOrWhiteSpace($explicit)) {
		return [System.IO.Path]::GetFullPath($explicit)
	}
	$candidates = New-Object System.Collections.Generic.List[string]
	if ($env:CODEX_HOME) {
		$candidates.Add((Join-Path $env:CODEX_HOME "config.toml"))
	}
	if ($env:USERPROFILE) {
		$candidates.Add((Join-Path $env:USERPROFILE ".codex\config.toml"))
	}
	if ($env:LOCALAPPDATA) {
		$candidates.Add((Join-Path $env:LOCALAPPDATA "OpenAI\Codex\config.toml"))
	}
	if ($env:APPDATA) {
		$candidates.Add((Join-Path $env:APPDATA "OpenAI\Codex\config.toml"))
	}
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}
	if ($candidates.Count -gt 0) {
		return [System.IO.Path]::GetFullPath($candidates[0])
	}
	return ""
}

function Resolve-CodexExe {
	param([string]$ExplicitPath)
	$explicit = Normalize-Text $ExplicitPath
	if (![string]::IsNullOrWhiteSpace($explicit)) {
		if (Test-Path -LiteralPath $explicit -PathType Leaf) {
			return (Resolve-Path -LiteralPath $explicit).Path
		}
		return $explicit
	}
	$known = @()
	if ($env:LOCALAPPDATA) {
		$known += (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin\codex.exe")
	}
	if ($env:USERPROFILE) {
		$known += (Join-Path $env:USERPROFILE "AppData\Local\OpenAI\Codex\bin\codex.exe")
	}
	foreach ($candidate in $known) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}
	$where = ""
	try {
		$where = (& where.exe codex 2>$null | Select-Object -First 1)
	} catch {
		$where = ""
	}
	if (![string]::IsNullOrWhiteSpace($where)) {
		return (Normalize-Text $where)
	}
	return ""
}

function Get-ServerRoot {
	param([string]$Value)
	$normalized = (Normalize-Text $Value).TrimEnd("/")
	if ($normalized.EndsWith("/v1", [System.StringComparison]::OrdinalIgnoreCase)) {
		return $normalized.Substring(0, $normalized.Length - 3)
	}
	return $normalized
}

function Test-Url {
	param([string]$Url)
	$result = [ordered]@{
		Url = $Url
		Reachable = $false
		Ready = $false
		StatusCode = 0
		Message = ""
	}
	if ([string]::IsNullOrWhiteSpace($Url)) {
		$result.Message = "URL is empty"
		return [pscustomobject]$result
	}
	try {
		$response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec ([Math]::Max(1, $TimeoutSeconds)) -ErrorAction Stop
		$result.Reachable = $true
		$result.Ready = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300)
		$result.StatusCode = [int]$response.StatusCode
		$result.Message = ($response.Content | Out-String).Trim()
	} catch {
		if ($_.Exception.Response) {
			$result.Reachable = $true
			$result.StatusCode = [int]$_.Exception.Response.StatusCode
			$result.Message = $_.Exception.Message
		} else {
			$result.Message = $_.Exception.Message
		}
	}
	return [pscustomobject]$result
}

function Get-ServedModelEvidence {
	param(
		[string]$ApiRoot,
		[string]$ExpectedModel
	)

	$result = [ordered]@{
		Url = ($ApiRoot.TrimEnd("/") + "/models")
		Reachable = $false
		Models = @()
		ExpectedModelServed = $false
		Message = ""
	}
	try {
		$response = Invoke-RestMethod -Uri $result.Url -Method Get -TimeoutSec ([Math]::Max(1, $TimeoutSeconds)) -ErrorAction Stop
		$modelIds = New-Object System.Collections.Generic.List[string]
		if ($response.PSObject.Properties["data"]) {
			foreach ($item in @($response.data)) {
				if ($item.PSObject.Properties["id"] -and ![string]::IsNullOrWhiteSpace([string]$item.id)) {
					$modelIds.Add([string]$item.id)
				}
				if ($item.PSObject.Properties["aliases"]) {
					foreach ($alias in @($item.aliases)) {
						if (![string]::IsNullOrWhiteSpace([string]$alias)) {
							$modelIds.Add([string]$alias)
						}
					}
				}
			}
		}
		if ($response.PSObject.Properties["models"]) {
			foreach ($item in @($response.models)) {
				foreach ($property in @("model", "name", "id")) {
					if ($item.PSObject.Properties[$property] -and ![string]::IsNullOrWhiteSpace([string]$item.$property)) {
						$modelIds.Add([string]$item.$property)
					}
				}
			}
		}
		$models = @($modelIds.ToArray() | Sort-Object -Unique)
		$result.Reachable = $true
		$result.Models = @($models)
		$result.ExpectedModelServed = @($models) -contains $ExpectedModel
	} catch {
		$result.Message = $_.Exception.Message
	}
	return [pscustomobject]$result
}

function Get-CommandLineValue {
	param(
		[string]$CommandLine,
		[string[]]$Names
	)

	foreach ($name in @($Names)) {
		$escaped = [regex]::Escape($name)
		$quoted = [regex]::Match($CommandLine, "(?i)(?:^|\s)$escaped\s+`"([^`"]+)`"")
		if ($quoted.Success) {
			return $quoted.Groups[1].Value
		}
		$plain = [regex]::Match($CommandLine, "(?i)(?:^|\s)$escaped\s+([^\s]+)")
		if ($plain.Success) {
			return $plain.Groups[1].Value
		}
	}
	return ""
}

function Get-ModelFamilyToken {
	param([string]$Value)
	$lower = $Value.ToLowerInvariant()
	foreach ($token in @("glm", "qwen", "llama", "mistral", "gemma", "phi", "deepseek", "codellama")) {
		if ($lower.Contains($token)) {
			return $token
		}
	}
	return ""
}

function Get-LocalLlamaServerEvidence {
	param(
		[int]$Port,
		[string]$ExpectedModel
	)

	$records = New-Object System.Collections.Generic.List[object]
	try {
		$processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
			$_.Name -ieq "llama-server.exe" -and $_.CommandLine -match "(^|\s)--port\s+$Port(\s|$)"
		})
		foreach ($process in @($processes)) {
			$commandLine = [string]$process.CommandLine
			$modelPath = Get-CommandLineValue -CommandLine $commandLine -Names @("-m", "--model")
			$alias = Get-CommandLineValue -CommandLine $commandLine -Names @("--alias")
			$modelFile = if (![string]::IsNullOrWhiteSpace($modelPath)) { [System.IO.Path]::GetFileName($modelPath) } else { "" }
			$aliasFamily = Get-ModelFamilyToken $alias
			$fileFamily = Get-ModelFamilyToken $modelFile
			$familyMismatch = (
				![string]::IsNullOrWhiteSpace($aliasFamily) -and
				![string]::IsNullOrWhiteSpace($fileFamily) -and
				$aliasFamily -ne $fileFamily
			)
			$records.Add([pscustomobject]@{
				ProcessId = [int]$process.ProcessId
				ModelPath = $modelPath
				ModelFile = $modelFile
				Alias = $alias
				AliasMatchesExpectedModel = ($alias -eq $ExpectedModel)
				ModelAliasFamilyMismatch = [bool]$familyMismatch
			})
		}
	} catch {
		return [pscustomobject]@{
			Available = $false
			Error = $_.Exception.Message
			Processes = @()
		}
	}

	return [pscustomobject]@{
		Available = $true
		Error = ""
		Processes = @($records.ToArray())
	}
}

function Test-CodexHelp {
	param([string]$Exe)
	$result = [ordered]@{
		Found = $false
		SupportsModel = $false
		SupportsProfile = $false
		SupportsConfig = $false
		SupportsNoAltScreen = $false
		SupportsDisable = $false
		Message = ""
	}
	if ([string]::IsNullOrWhiteSpace($Exe)) {
		$result.Message = "codex executable was not found"
		return [pscustomobject]$result
	}

	$exeExists = $false
	if ($Exe -eq "codex") {
		$exeExists = $null -ne (Get-Command codex -ErrorAction SilentlyContinue)
	} else {
		$exeExists = Test-Path -LiteralPath $Exe -PathType Leaf
	}
	if ($exeExists) {
		$result.Found = $true
	}

	try {
		$previousErrorActionPreference = $ErrorActionPreference
		$ErrorActionPreference = "Continue"
		$output = & $Exe --help 2>&1 | ForEach-Object { $_.ToString() }
		$ErrorActionPreference = $previousErrorActionPreference
		$text = $output -join "`n"
		$result.Found = $true
		$result.SupportsModel = $text -match "--model| -m,"
		$result.SupportsProfile = $text -match "--profile| -p,"
		$result.SupportsConfig = $text -match "--config| -c,"
		$result.SupportsNoAltScreen = $text -match "--no-alt-screen"
		$result.SupportsDisable = $text -match "--disable"
		if ($result.SupportsModel -or $result.SupportsProfile -or $result.SupportsConfig -or $result.SupportsDisable) {
			$result.Message = "codex --help succeeded"
		} elseif ($result.Found) {
			$result.SupportsModel = $true
			$result.SupportsProfile = $true
			$result.SupportsConfig = $true
			$result.SupportsNoAltScreen = $true
			$result.SupportsDisable = $true
			$result.Message = "codex executable found; help output did not expose flags, assuming current Codex CLI"
		}
	} catch {
		if ($result.Found) {
			$result.SupportsModel = $true
			$result.SupportsProfile = $true
			$result.SupportsConfig = $true
			$result.SupportsNoAltScreen = $true
			$result.SupportsDisable = $true
			$result.Message = "codex executable found; help check failed, assuming current Codex CLI: " +
				$_.Exception.Message
		} else {
			$result.Message = $_.Exception.Message
		}
	} finally {
		if ($previousErrorActionPreference) {
			$ErrorActionPreference = $previousErrorActionPreference
		}
	}
	return [pscustomobject]$result
}

function Format-LaunchArgument {
	param([string]$Value)
	if ($Value -match "[\s`"']") {
		return "'" + ($Value -replace "'", "''") + "'"
	}
	return $Value
}

$resolvedEndpoint = Normalize-Text $Endpoint
$serverRoot = Get-ServerRoot $resolvedEndpoint
$apiRoot = if ($resolvedEndpoint.EndsWith("/v1", [System.StringComparison]::OrdinalIgnoreCase)) { $resolvedEndpoint.TrimEnd("/") } else { ($resolvedEndpoint.TrimEnd("/") + "/v1") }
$resolvedModel = Normalize-Text $Model
$resolvedProfile = Normalize-Text $Profile
$resolvedConfig = Resolve-ConfigPath $ConfigPath
$resolvedCodex = Resolve-CodexExe $CodexExe
$codexHelp = Test-CodexHelp $resolvedCodex
$health = Test-Url ($serverRoot.TrimEnd("/") + "/health")
$responsesProbe = Test-Url ($apiRoot.TrimEnd("/") + "/responses")
$chatProbe = Test-Url ($apiRoot.TrimEnd("/") + "/chat/completions")
$servedModels = Get-ServedModelEvidence -ApiRoot $apiRoot -ExpectedModel $resolvedModel
if (($UseServedModel -or [string]::IsNullOrWhiteSpace($resolvedModel) -or ($servedModels.Reachable -and !$servedModels.ExpectedModelServed)) -and $servedModels.Reachable -and @($servedModels.Models).Count -eq 1) {
	$resolvedModel = [string]@($servedModels.Models)[0]
	$servedModels.ExpectedModelServed = $true
}
$endpointUri = [System.Uri]$serverRoot
$localProcessEvidence = Get-LocalLlamaServerEvidence -Port $endpointUri.Port -ExpectedModel $resolvedModel
$configText = if (![string]::IsNullOrWhiteSpace($resolvedConfig) -and (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) {
	Get-Content -LiteralPath $resolvedConfig -Raw
} else {
	""
}
$configState = [ordered]@{
	Path = $resolvedConfig
	Exists = (![string]::IsNullOrWhiteSpace($resolvedConfig) -and (Test-Path -LiteralPath $resolvedConfig -PathType Leaf))
	HasProvider = ($configText -match "\[model_providers\.llama_cpp\]")
	HasProfile = ($configText -match "\[profiles\.$([regex]::Escape($resolvedProfile))\]")
	HasModelProviderSelection = ($configText -match "model_provider\s*=\s*`"llama_cpp`"")
	ProviderOverrideProvided = $true
}
$launchArguments = @(
	"--no-alt-screen",
	"-p", $resolvedProfile,
	"--disable", "apps",
	"--disable", "image_generation",
	"--disable", "browser_use",
	"--disable", "computer_use",
	"--disable", "tool_search",
	"-c", "web_search=`"disabled`"",
	"-c", "model_provider=llama_cpp",
	"-c", "model_providers.llama_cpp.name=`"llama.cpp local`"",
	"-c", "model_providers.llama_cpp.base_url=`"$apiRoot`"",
	"-c", "model_providers.llama_cpp.wire_api=`"responses`"",
	"-c", "model_providers.llama_cpp.stream_idle_timeout_ms=10000000",
	"-c", "model_context_window=$ModelContextWindow",
	"-c", "model_auto_compact_token_limit=$ModelAutoCompactTokenLimit",
	"-c", "tool_output_token_limit=$ToolOutputTokenLimit",
	"-c", "model_reasoning_effort=medium",
	"-c", "model_reasoning_summary=none",
	"-c", "hide_agent_reasoning=true",
	"-c", "agents.max_threads=$AgentMaxConcurrentThreads",
	"-c", "agents.max_depth=$AgentMaxDepth"
)
if (![string]::IsNullOrWhiteSpace($resolvedModel)) {
	$launchArguments += @("--model", $resolvedModel)
}
$launchCommand = "codex " + (($launchArguments | ForEach-Object { Format-LaunchArgument $_ }) -join " ")
$blockers = New-Object System.Collections.Generic.List[string]
if (!$codexHelp.Found) {
	$blockers.Add("codex executable not found")
}
if (!$codexHelp.SupportsConfig) {
	$blockers.Add("codex CLI does not report -c/--config support")
}
if (!$codexHelp.SupportsProfile) {
	$blockers.Add("codex CLI does not report -p/--profile support")
}
if (!$codexHelp.SupportsModel) {
	$blockers.Add("codex CLI does not report --model support")
}
if (!$codexHelp.SupportsDisable) {
	$blockers.Add("codex CLI does not report --disable support needed for llama-server tool compatibility")
}
if (!$health.Ready) {
	$blockers.Add("llama-server health endpoint is not ready")
}
if ($health.Ready -and $servedModels.Reachable -and !$servedModels.ExpectedModelServed) {
	$suggestion = if (@($servedModels.Models).Count -eq 1) {
		"; retry with -UseServedModel or -Model $(@($servedModels.Models)[0])"
	} else {
		""
	}
	$blockers.Add("llama-server does not advertise requested model alias: $resolvedModel$suggestion")
}
if ($localProcessEvidence.Available -and @($localProcessEvidence.Processes).Count -gt 1) {
	$blockers.Add("multiple llama-server processes target the Codex port; stop stale servers or use Force new before Codex work")
}
$result = [ordered]@{
	Name = "ofxGgmlLlama local Codex plan"
	Root = $addonRoot.Path
	Endpoint = $resolvedEndpoint
	ServerRoot = $serverRoot
	ApiRoot = $apiRoot
	Model = $resolvedModel
	UseServedModel = [bool]$UseServedModel
	SuggestedModel = if ($servedModels.Reachable -and @($servedModels.Models).Count -eq 1) { [string]@($servedModels.Models)[0] } else { "" }
	Profile = $resolvedProfile
	CodexExe = $resolvedCodex
	Codex = $codexHelp
	Config = [pscustomobject]$configState
	Health = $health
	ServedModels = $servedModels
	LocalLlamaServer = $localProcessEvidence
	Responses = $responsesProbe
	Chat = $chatProbe
	LaunchCommand = $launchCommand
	CodexSettings = [pscustomobject]@{
		ModelContextWindow = [int]$ModelContextWindow
		ModelAutoCompactTokenLimit = [int]$ModelAutoCompactTokenLimit
		ToolOutputTokenLimit = [int]$ToolOutputTokenLimit
		ModelReasoningEffort = "medium"
		ModelReasoningSummary = "none"
		HideAgentReasoning = $true
		AgentMaxConcurrentThreads = [int]$AgentMaxConcurrentThreads
		AgentMaxDepth = [int]$AgentMaxDepth
	}
	UsesOssFlag = ($launchCommand -match "\s--oss(\s|$)")
	Blockers = @($blockers)
	Ready = ($blockers.Count -eq 0)
}

if ($Json) {
	$output = [ordered]@{}
	foreach ($key in $result.Keys) {
		if ($SummaryOnly -and $key -in @("Responses", "Chat")) {
			continue
		}
		$output[$key] = $result[$key]
	}
	[pscustomobject]$output | ConvertTo-Json -Depth 6
} else {
	Write-Host "ofxGgmlLlama local Codex plan"
	Write-Host "  root:    $($result.Root)"
	Write-Host "  endpoint:$($result.Endpoint)"
	Write-Host "  model:   $($result.Model)"
	Write-Host "  profile: $($result.Profile)"
	Write-Host "  codex:   $(if ($result.CodexExe) { $result.CodexExe } else { '(not found)' })"
	Write-Host "  config:  $(if ($result.Config.Path) { $result.Config.Path } else { '(not resolved)' })"
	Write-Host "  server:  $(if ($result.Health.Ready) { 'ready' } elseif ($result.Health.Reachable) { 'reachable' } else { 'down' })"
	if ($result.ServedModels.Reachable) {
		Write-Host "  served:  $(@($result.ServedModels.Models) -join ', ')"
	}
	$localProcesses = @($result.LocalLlamaServer.Processes)
	if ($localProcesses.Count -gt 0) {
		Write-Host "  loaded:  $($localProcesses[0].ModelFile)"
		if ($localProcesses[0].ModelAliasFamilyMismatch) {
			Write-Host "  warning: alias/model family mismatch: $($localProcesses[0].Alias) -> $($localProcesses[0].ModelFile)"
		}
	}
	Write-Host ""
	Write-Host "Launch command:"
	Write-Host "  $($result.LaunchCommand)"
	Write-Host ""
	if ($result.Ready) {
		Write-Host "Ready for local Codex."
	} else {
		Write-Host "Blockers:"
		foreach ($blocker in $result.Blockers) {
			Write-Host "  - $blocker"
		}
	}
}

if ($Strict -and !$result.Ready) {
	exit 1
}
$global:LASTEXITCODE = 0
