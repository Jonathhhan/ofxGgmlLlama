param(
	[string]$Endpoint = $(if ($env:OFXGGML_CODEX_BASE_URL) { $env:OFXGGML_CODEX_BASE_URL } else { "http://127.0.0.1:8001/v1" }),
	[string]$Model = $(if ($env:OFXGGML_CODEX_MODEL) { $env:OFXGGML_CODEX_MODEL } else { "local/Qwen3.6-27B-Q4_0" }),
	[string]$Profile = $(if ($env:OFXGGML_CODEX_PROFILE) { $env:OFXGGML_CODEX_PROFILE } else { "ofxggml_local" }),
	[string]$ConfigPath = $(if ($env:OFXGGML_CODEX_CONFIG_PATH) { $env:OFXGGML_CODEX_CONFIG_PATH } else { "" }),
	[string]$CodexExe = $(if ($env:OFXGGML_CODEX_EXE) { $env:OFXGGML_CODEX_EXE } else { "" }),
	[int]$ModelContextWindow = $(if ($env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW) { [int]$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW } else { 65536 }),
	[int]$ModelAutoCompactTokenLimit = $(if ($env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT } else { 56000 }),
	[int]$ToolOutputTokenLimit = $(if ($env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT } else { 12000 }),
	[string]$WebSearch = $(if ($env:OFXGGML_CODEX_WEB_SEARCH) { $env:OFXGGML_CODEX_WEB_SEARCH } else { "live" }),
	[string]$ModelVerbosity = $(if ($env:OFXGGML_CODEX_MODEL_VERBOSITY) { $env:OFXGGML_CODEX_MODEL_VERBOSITY } else { "low" }),
	[Alias("AgentMaxAgents", "MaxAgents", "AgentMaxThreads", "MaxAgentThreads")]
	[int]$AgentMaxConcurrentThreads = $(if ($env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS } elseif ($env:OFXGGML_CODEX_AGENT_MAX_THREADS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_THREADS } elseif ($env:OFXGGML_CODEX_AGENT_MAX_AGENTS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_AGENTS } else { 1 }),
	[int]$AgentMaxDepth = $(if ($env:OFXGGML_CODEX_AGENT_MAX_DEPTH) { [int]$env:OFXGGML_CODEX_AGENT_MAX_DEPTH } else { 0 }),
	[switch]$UseServedModel,
	[int]$TimeoutSeconds = 2,
	[switch]$Json,
	[switch]$SummaryOnly,
	[switch]$Strict
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")

function Resolve-ConfigPath {
	param([string]$ExplicitPath)
	$explicit = Normalize-OfxGgmlPathText $ExplicitPath
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
	$explicit = Normalize-OfxGgmlPathText $ExplicitPath
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
		return (Normalize-OfxGgmlPathText $where)
	}
	return ""
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

function Get-ModelRoleHint {
	param([string]$Name)
	$lower = $Name.ToLowerInvariant()
	if ($lower -match "embed|embedding|bge|e5|gte|nomic|jina") {
		return "embedding"
	}
	return "text"
}

function Test-TinyModelHint {
	param(
		[string]$Name,
		[long]$Bytes
	)
	$lower = $Name.ToLowerInvariant()
	if ($lower -match "tiny|smoke|test|mini|0\.5b|0_5b|1\.5b|1_5b") {
		return $true
	}
	return $Bytes -gt 0 -and $Bytes -le 2GB
}

function Get-LocalTextModelCandidate {
	param([string]$PreferredAlias = "")

	$directories = Get-OfxGgmlModelSearchDirectories `
		-AddonRoot $addonRoot `
		-ExampleRoot (Join-Path $addonRoot "ofxGgmlTextExample") `
		-ExtraExampleNames @("ofxGgmlChatExample", "ofxGgmlEmbeddingExample")
	$candidates = New-Object System.Collections.Generic.List[object]
	foreach ($modelFile in (Get-OfxGgmlModelFiles $directories)) {
		if ((Get-ModelRoleHint $modelFile.Name) -eq "text") {
			$candidates.Add([pscustomobject]@{
				Path = $modelFile.FullName
				Name = $modelFile.Name
				Alias = Get-OfxGgmlLocalModelAlias -ModelPath $modelFile.FullName
				TinyCandidate = Test-TinyModelHint -Name $modelFile.Name -Bytes ([long]$modelFile.Length)
			})
		}
	}
	if (![string]::IsNullOrWhiteSpace($PreferredAlias)) {
		$preferred = @($candidates | Where-Object {
			$_.Alias.Equals($PreferredAlias, [System.StringComparison]::OrdinalIgnoreCase)
		} | Select-Object -First 1)
		if ($preferred.Count -gt 0) {
			return $preferred[0]
		}
	}
	$tiny = @($candidates | Where-Object { $_.TinyCandidate } | Select-Object -First 1)
	if ($tiny.Count -gt 0) {
		return $tiny[0]
	}
	$first = @($candidates | Select-Object -First 1)
	if ($first.Count -gt 0) {
		return $first[0]
	}
	return $null
}

function Get-CodexServerCommand {
	param(
		[string]$ServerRootValue,
		[object]$ModelCandidate,
		[string]$AliasValue,
		[switch]$Detached,
		[switch]$NoHealthCheck,
		[int]$StartupTimeoutSeconds = 600
	)
	$endpoint = Get-OfxGgmlServerEndpoint $ServerRootValue
	$arguments = @(
		".\scripts\start-llama-server.ps1",
		"-HostName", $endpoint.HostName,
		"-Port", $endpoint.Port.ToString(),
		"-ContextSize", $ModelContextWindow.ToString(),
		"-GpuLayers", "all",
		"-Parallel", "1",
		"-BatchSize", "1024",
		"-UBatchSize", "256",
		"-CacheReuse", "256",
		"-KvCacheKeyType", "q4_0",
		"-KvCacheValueType", "q4_0",
		"-Temperature", "0.2",
		"-TopP", "0.85",
		"-MinP", "0.03",
		"-ChatTemplateKwargs", '{"enable_thinking": false}',
		"-Reasoning", "off",
		"-ReasoningBudget", "0",
		"-Jinja",
		"-FlashAttention"
	)
	if ($Detached) {
		$arguments += @(
			"-Detached",
			"-StartupTimeoutSeconds", ([Math]::Max(1, $StartupTimeoutSeconds)).ToString(),
			"-LogDir", ".\ofxGgmlLlamaCodexLocalExample\bin\data\logs"
		)
	}
	if ($NoHealthCheck) {
		$arguments += "-NoHealthCheck"
	}
	if ($null -ne $ModelCandidate -and ![string]::IsNullOrWhiteSpace($ModelCandidate.Path)) {
		$arguments += @("-ModelPath", [string]$ModelCandidate.Path)
		$alias = if (![string]::IsNullOrWhiteSpace($AliasValue)) {
			$AliasValue
		} else {
			[string]$ModelCandidate.Alias
		}
		$arguments += @("-Alias", $alias)
	}
	return (($arguments | ForEach-Object { Format-OfxGgmlCommandArgument $_ }) -join " ")
}

$resolvedEndpoint = Normalize-OfxGgmlPathText $Endpoint
$serverRoot = Get-OfxGgmlServerRootUrl $resolvedEndpoint
$apiRoot = if ($resolvedEndpoint.EndsWith("/v1", [System.StringComparison]::OrdinalIgnoreCase)) { $resolvedEndpoint.TrimEnd("/") } else { ($resolvedEndpoint.TrimEnd("/") + "/v1") }
$resolvedModel = Normalize-OfxGgmlPathText $Model
$resolvedProfile = Normalize-OfxGgmlPathText $Profile
$resolvedConfig = Resolve-ConfigPath $ConfigPath
$resolvedCodex = Resolve-CodexExe $CodexExe
$codexHelp = Test-CodexHelp $resolvedCodex
$health = Test-OfxGgmlUrl -Url ($serverRoot.TrimEnd("/") + "/health") -TimeoutSeconds $TimeoutSeconds
$responsesProbe = Test-OfxGgmlUrl -Url ($apiRoot.TrimEnd("/") + "/responses") -TimeoutSeconds $TimeoutSeconds
$chatProbe = Test-OfxGgmlUrl -Url ($apiRoot.TrimEnd("/") + "/chat/completions") -TimeoutSeconds $TimeoutSeconds
$servedModels = Get-OfxGgmlServedModelEvidence -ApiRoot $apiRoot -ExpectedModel $resolvedModel -TimeoutSeconds $TimeoutSeconds
if (($UseServedModel -or [string]::IsNullOrWhiteSpace($resolvedModel) -or ($servedModels.Reachable -and !$servedModels.ExpectedModelServed)) -and $servedModels.Reachable -and @($servedModels.Models).Count -eq 1) {
	$resolvedModel = [string]@($servedModels.Models)[0]
	$servedModels.ExpectedModelServed = $true
}
$endpointUri = [System.Uri]$serverRoot
$localProcessEvidence = Get-LocalLlamaServerEvidence -Port $endpointUri.Port -ExpectedModel $resolvedModel
$modelCandidate = Get-LocalTextModelCandidate -PreferredAlias $resolvedModel
if ([string]::IsNullOrWhiteSpace($resolvedModel) -and $null -ne $modelCandidate) {
	$resolvedModel = [string]$modelCandidate.Alias
}
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
	ProviderOverrideProvided = $false
	ReadyForLocalAgents = $false
}
$configState.ReadyForLocalAgents = [bool]($configState.HasProvider -and $configState.HasModelProviderSelection)
$launchArguments = @(
	"--no-alt-screen",
	"--disable", "apps",
	"--disable", "image_generation",
	"--disable", "browser_use",
	"--disable", "computer_use",
	"--disable", "tool_search",
	"--disable", "tool_search_always_defer_mcp_tools",
	"-c", "mcp_servers.node_repl.enabled=false",
	"-c", "web_search=`"$WebSearch`""
)
if ($AgentMaxConcurrentThreads -gt 0) {
	$launchArguments += @("-c", "agents.max_threads=$AgentMaxConcurrentThreads")
}
if ($AgentMaxDepth -gt 0) {
	$launchArguments += @("-c", "agents.max_depth=$AgentMaxDepth")
}
if (![string]::IsNullOrWhiteSpace($ModelVerbosity)) {
	$launchArguments += @("-c", "model_verbosity=$ModelVerbosity")
}
if (![string]::IsNullOrWhiteSpace($resolvedModel)) {
	$launchArguments += @("--model", $resolvedModel)
}
$launchCommand = "codex " + (($launchArguments | ForEach-Object { Format-OfxGgmlPowerShellArgument $_ }) -join " ")
$blockers = New-Object System.Collections.Generic.List[string]
if (!$codexHelp.Found) {
	$blockers.Add("codex executable not found")
}
if (!$codexHelp.SupportsConfig) {
	$blockers.Add("codex CLI does not report -c/--config support")
}
if (!$codexHelp.SupportsModel) {
	$blockers.Add("codex CLI does not report --model support")
}
if (!$codexHelp.SupportsDisable) {
	$blockers.Add("codex CLI does not report --disable support needed for llama-server tool compatibility")
}
if (!$configState.ReadyForLocalAgents) {
	$blockers.Add("Codex config does not define the llama_cpp provider/selection required by local agents")
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
$startServerCommand = Get-CodexServerCommand `
	-ServerRootValue $serverRoot `
	-ModelCandidate $modelCandidate `
	-AliasValue $resolvedModel `
	-Detached `
	-StartupTimeoutSeconds 600
$manualServerCommand = Get-CodexServerCommand `
	-ServerRootValue $serverRoot `
	-ModelCandidate $modelCandidate `
	-AliasValue $resolvedModel
$detachedNoHealthCheckCommand = Get-CodexServerCommand `
	-ServerRootValue $serverRoot `
	-ModelCandidate $modelCandidate `
	-AliasValue $resolvedModel `
	-Detached `
	-NoHealthCheck
$statusCommand = ".\scripts\status-llama-server.ps1 -CodexServerUrl " +
	(Format-OfxGgmlCommandArgument $serverRoot) + " -Json -SummaryOnly"
$waitCommand = ".\scripts\status-llama-server.ps1 -CodexServerUrl " +
	(Format-OfxGgmlCommandArgument $serverRoot) +
	" -WaitReady -WaitLabel codex -WaitTimeoutSeconds 600 -PollSeconds 2 -Json -SummaryOnly"
$smokeCommandArguments = @(
	".\scripts\test-local-codex.ps1",
	"-Endpoint", $apiRoot
)
if (![string]::IsNullOrWhiteSpace($resolvedModel)) {
	$smokeCommandArguments += @("-Model", $resolvedModel)
}
$smokeCommandArguments += @("-WebSearch", $WebSearch)
$smokeCommandArguments += @("-Json", "-SummaryOnly")
$smokeCommand = (($smokeCommandArguments | ForEach-Object { Format-OfxGgmlCommandArgument $_ }) -join " ")
$configWriteCommandArguments = @(
	".\scripts\test-local-codex.ps1",
	"-Endpoint", $apiRoot
)
if (![string]::IsNullOrWhiteSpace($resolvedModel)) {
	$configWriteCommandArguments += @("-Model", $resolvedModel)
}
$configWriteCommandArguments += @("-Profile", $resolvedProfile, "-WebSearch", $WebSearch, "-WriteConfigOnly", "-Json", "-SummaryOnly")
$configWriteCommand = (($configWriteCommandArguments | ForEach-Object { Format-OfxGgmlCommandArgument $_ }) -join " ")
$recommendedActions = New-Object System.Collections.Generic.List[string]
if (!$configState.ReadyForLocalAgents) {
	$recommendedActions.Add("Write the local Codex provider selection before launching agents: $configWriteCommand")
}
if (!$health.Ready) {
	$recommendedActions.Add("Start the Codex llama-server endpoint: $startServerCommand")
	$recommendedActions.Add("If automatic startup times out, run the foreground manual command: $manualServerCommand")
	$recommendedActions.Add("Wait for readiness: $waitCommand")
	$recommendedActions.Add("Check readiness: $statusCommand")
}
if ($health.Ready -and $servedModels.Reachable -and !$servedModels.ExpectedModelServed) {
	$recommendedActions.Add("Use the served model alias or restart llama-server with -Alias $resolvedModel")
}
if ($blockers.Count -eq 0) {
	$recommendedActions.Add("Run the local Codex smoke: $smokeCommand")
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
	SuggestedStartModel = if ($null -ne $modelCandidate) { [string]$modelCandidate.Path } else { "" }
	SuggestedStartAlias = if (![string]::IsNullOrWhiteSpace($resolvedModel)) { $resolvedModel } elseif ($null -ne $modelCandidate) { [string]$modelCandidate.Alias } else { "" }
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
	StartServerCommand = $startServerCommand
	ManualServerCommand = $manualServerCommand
	DetachedNoHealthCheckCommand = $detachedNoHealthCheckCommand
	StatusCommand = $statusCommand
	WaitCommand = $waitCommand
	SmokeCommand = $smokeCommand
	ConfigWriteCommand = $configWriteCommand
	CodexSettings = [pscustomobject]@{
		ModelContextWindow = [int]$ModelContextWindow
		ModelAutoCompactTokenLimit = [int]$ModelAutoCompactTokenLimit
		ToolOutputTokenLimit = [int]$ToolOutputTokenLimit
		WebSearch = $WebSearch
		ModelVerbosity = $ModelVerbosity
		ModelReasoningEffort = "medium"
		ModelReasoningSummary = "none"
		HideAgentReasoning = $true
		AgentMaxConcurrentThreads = [int]$AgentMaxConcurrentThreads
		AgentMaxDepth = [int]$AgentMaxDepth
	}
	UsesOssFlag = ($launchCommand -match "\s--oss(\s|$)")
	Blockers = @($blockers)
	RecommendedActions = @($recommendedActions.ToArray())
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
	Write-Host "Server command:"
	Write-Host "  $($result.StartServerCommand)"
	Write-Host ""
	Write-Host "Manual server command:"
	Write-Host "  $($result.ManualServerCommand)"
	Write-Host ""
	if ($result.Ready) {
		Write-Host "Ready for local Codex."
	} else {
		Write-Host "Blockers:"
		foreach ($blocker in $result.Blockers) {
			Write-Host "  - $blocker"
		}
		if (@($result.RecommendedActions).Count -gt 0) {
			Write-Host ""
			Write-Host "Next actions:"
			foreach ($action in $result.RecommendedActions) {
				Write-Host "  - $action"
			}
		}
	}
}

if ($Strict -and !$result.Ready) {
	exit 1
}
$global:LASTEXITCODE = 0
