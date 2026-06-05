param(
	[string]$Endpoint = $(if ($env:OFXGGML_OPENCODE_BASE_URL) { $env:OFXGGML_OPENCODE_BASE_URL } elseif ($env:OFXGGML_CODEX_BASE_URL) { $env:OFXGGML_CODEX_BASE_URL } else { "http://127.0.0.1:8001/v1" }),
	[string]$Model = $(if ($env:OFXGGML_OPENCODE_MODEL) { $env:OFXGGML_OPENCODE_MODEL } elseif ($env:OFXGGML_CODEX_MODEL) { $env:OFXGGML_CODEX_MODEL } else { "local/GLM-4.7-Flash-UD-Q4_K_XL" }),
	[string]$ProviderId = $(if ($env:OFXGGML_OPENCODE_PROVIDER_ID) { $env:OFXGGML_OPENCODE_PROVIDER_ID } else { "llama_cpp" }),
	[string]$ProviderName = $(if ($env:OFXGGML_OPENCODE_PROVIDER_NAME) { $env:OFXGGML_OPENCODE_PROVIDER_NAME } else { "llama.cpp local" }),
	[string]$ConfigPath = $(if ($env:OPENCODE_CONFIG) { $env:OPENCODE_CONFIG } elseif ($env:OFXGGML_OPENCODE_CONFIG_PATH) { $env:OFXGGML_OPENCODE_CONFIG_PATH } else { "" }),
	[string]$OpenCodeExe = $(if ($env:OFXGGML_OPENCODE_EXE) { $env:OFXGGML_OPENCODE_EXE } else { "" }),
	[int]$ContextSize = $(if ($env:OFXGGML_OPENCODE_CONTEXT_SIZE) { [int]$env:OFXGGML_OPENCODE_CONTEXT_SIZE } elseif ($env:OFXGGML_CODEX_CONTEXT_SIZE) { [int]$env:OFXGGML_CODEX_CONTEXT_SIZE } else { 65536 }),
	[int]$OutputTokens = $(if ($env:OFXGGML_OPENCODE_OUTPUT_TOKENS) { [int]$env:OFXGGML_OPENCODE_OUTPUT_TOKENS } elseif ($env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT } else { 8000 }),
	[int]$TimeoutMs = $(if ($env:OFXGGML_OPENCODE_TIMEOUT_MS) { [int]$env:OFXGGML_OPENCODE_TIMEOUT_MS } else { 600000 }),
	[int]$ChunkTimeoutMs = $(if ($env:OFXGGML_OPENCODE_CHUNK_TIMEOUT_MS) { [int]$env:OFXGGML_OPENCODE_CHUNK_TIMEOUT_MS } else { 60000 }),
	[double]$Temperature = $(if ($env:OFXGGML_OPENCODE_TEMP) { [double]$env:OFXGGML_OPENCODE_TEMP } elseif ($env:OFXGGML_CODEX_TEMP) { [double]$env:OFXGGML_CODEX_TEMP } else { 0.7 }),
	[double]$TopP = $(if ($env:OFXGGML_OPENCODE_TOP_P) { [double]$env:OFXGGML_OPENCODE_TOP_P } elseif ($env:OFXGGML_CODEX_TOP_P) { [double]$env:OFXGGML_CODEX_TOP_P } else { 0.9 }),
	[string]$DefaultAgent = $(if ($env:OFXGGML_OPENCODE_DEFAULT_AGENT) { $env:OFXGGML_OPENCODE_DEFAULT_AGENT } else { "build" }),
	[switch]$KeepBuiltInProviders,
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

function Resolve-OpenCodeConfigPath {
	param([string]$ExplicitPath)
	$explicit = Normalize-OfxGgmlPathText $ExplicitPath
	if (![string]::IsNullOrWhiteSpace($explicit)) {
		return [System.IO.Path]::GetFullPath($explicit)
	}
	if ($env:USERPROFILE) {
		return [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ".config\opencode\opencode.json"))
	}
	if ($env:HOME) {
		return [System.IO.Path]::GetFullPath((Join-Path $env:HOME ".config/opencode/opencode.json"))
	}
	return ""
}

function Resolve-OpenCodeExe {
	param([string]$ExplicitPath)
	$explicit = Normalize-OfxGgmlPathText $ExplicitPath
	if (![string]::IsNullOrWhiteSpace($explicit)) {
		if (Test-Path -LiteralPath $explicit -PathType Leaf) {
			return (Resolve-Path -LiteralPath $explicit).Path
		}
		return $explicit
	}
	$where = ""
	try {
		$where = (& where.exe opencode 2>$null | Select-Object -First 1)
	} catch {
		$where = ""
	}
	if (![string]::IsNullOrWhiteSpace($where)) {
		return (Normalize-OfxGgmlPathText $where)
	}
	return ""
}

function Test-OpenCodeHelp {
	param([string]$Exe)
	$result = [ordered]@{
		Found = $false
		SupportsRun = $false
		SupportsModels = $false
		Message = ""
	}
	if ([string]::IsNullOrWhiteSpace($Exe)) {
		$result.Message = "opencode executable was not found"
		return [pscustomobject]$result
	}
	try {
		$output = & $Exe --help 2>&1 | ForEach-Object { $_.ToString() }
		$text = $output -join "`n"
		$result.Found = $true
		$result.SupportsRun = $text -match "(?i)\brun\b"
		$result.SupportsModels = $text -match "(?i)models|/models"
		$result.Message = "opencode --help succeeded"
	} catch {
		$result.Message = $_.Exception.Message
	}
	return [pscustomobject]$result
}

function Get-OpenCodeModelParts {
	param(
		[string]$Provider,
		[string]$ModelValue
	)
	$providerPrefix = $Provider + "/"
	if ($ModelValue.StartsWith($providerPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
		$modelId = $ModelValue.Substring($providerPrefix.Length)
	} else {
		$modelId = $ModelValue
	}
	return [pscustomobject]@{
		ProviderModelId = $modelId
		FullModelId = "$Provider/$modelId"
	}
}

function New-OpenCodePermission {
	param(
		[string]$Edit,
		[string]$Bash,
		[string]$Task
	)
	return [ordered]@{
		read = "allow"
		glob = "allow"
		grep = "allow"
		list = "allow"
		edit = $Edit
		bash = $Bash
		task = $Task
		external_directory = "ask"
		webfetch = "deny"
		websearch = "allow"
	}
}

function New-OpenCodeConfigSnippet {
	param(
		[string]$Provider,
		[string]$Name,
		[string]$ApiRoot,
		[string]$ProviderModelId,
		[string]$FullModelId,
		[string]$PrimaryAgent,
		[bool]$DisableBuiltInProviders
	)

	$modelConfig = [ordered]@{
		name = ($ProviderModelId -replace "^local/", "")
		limit = [ordered]@{
			context = [int]$ContextSize
			output = [int]$OutputTokens
		}
		options = [ordered]@{
			temperature = [double]$Temperature
			topP = [double]$TopP
		}
	}
	$models = [ordered]@{}
	$models[$ProviderModelId] = $modelConfig
	$providers = [ordered]@{}
	$providers[$Provider] = [ordered]@{
		npm = "@ai-sdk/openai-compatible"
		name = $Name
		options = [ordered]@{
			baseURL = $ApiRoot
			apiKey = "local"
			timeout = [int]$TimeoutMs
			chunkTimeout = [int]$ChunkTimeoutMs
		}
		models = $models
	}
	$buildPermission = New-OpenCodePermission -Edit "ask" -Bash "ask" -Task "ask"
	$planPermission = New-OpenCodePermission -Edit "deny" -Bash "ask" -Task "ask"
	$explorePermission = New-OpenCodePermission -Edit "deny" -Bash "ask" -Task "deny"
	$agents = [ordered]@{
		build = [ordered]@{
			mode = "primary"
			model = $FullModelId
			temperature = 0.2
			topP = [double]$TopP
			permission = $buildPermission
		}
		plan = [ordered]@{
			mode = "primary"
			model = $FullModelId
			temperature = 0.1
			topP = [double]$TopP
			permission = $planPermission
		}
		explore = [ordered]@{
			mode = "subagent"
			model = $FullModelId
			temperature = 0.1
			topP = [double]$TopP
			permission = $explorePermission
		}
	}
	$config = [ordered]@{
		'$schema' = "https://opencode.ai/config.json"
		model = $FullModelId
		small_model = $FullModelId
		default_agent = $PrimaryAgent
		provider = $providers
		agent = $agents
		permission = $buildPermission
	}
	if ($DisableBuiltInProviders) {
		$config.disabled_providers = @(
			"openai",
			"anthropic",
			"gemini"
		)
	}
	return ($config | ConvertTo-Json -Depth 12)
}

$resolvedEndpoint = Normalize-OfxGgmlPathText $Endpoint
$serverRoot = Get-OfxGgmlServerRootUrl $resolvedEndpoint
$apiRoot = if ($resolvedEndpoint.EndsWith("/v1", [System.StringComparison]::OrdinalIgnoreCase)) { $resolvedEndpoint.TrimEnd("/") } else { ($resolvedEndpoint.TrimEnd("/") + "/v1") }
$resolvedProvider = Normalize-OfxGgmlPathText $ProviderId
$resolvedProviderName = Normalize-OfxGgmlPathText $ProviderName
$resolvedDefaultAgent = Normalize-OfxGgmlPathText $DefaultAgent
$disableBuiltInProviders = !$KeepBuiltInProviders
$requestedModel = Normalize-OfxGgmlPathText $Model
$modelParts = Get-OpenCodeModelParts -Provider $resolvedProvider -ModelValue $requestedModel
$servedModels = Get-OfxGgmlServedModelEvidence -ApiRoot $apiRoot -ExpectedModel $modelParts.ProviderModelId -TimeoutSeconds $TimeoutSeconds
if ($UseServedModel -and $servedModels.Reachable -and @($servedModels.Models).Count -eq 1) {
	$modelParts = Get-OpenCodeModelParts -Provider $resolvedProvider -ModelValue ([string]@($servedModels.Models)[0])
	$servedModels.ExpectedModelServed = $true
}
$health = Test-OfxGgmlUrl -Url ($serverRoot.TrimEnd("/") + "/health") -TimeoutSeconds $TimeoutSeconds
$chatProbe = Test-OfxGgmlUrl -Url ($apiRoot.TrimEnd("/") + "/chat/completions") -TimeoutSeconds $TimeoutSeconds
$resolvedConfig = Resolve-OpenCodeConfigPath $ConfigPath
$configText = if (![string]::IsNullOrWhiteSpace($resolvedConfig) -and (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) {
	Get-Content -LiteralPath $resolvedConfig -Raw
} else {
	""
}
$resolvedOpenCode = Resolve-OpenCodeExe $OpenCodeExe
$openCodeHelp = Test-OpenCodeHelp $resolvedOpenCode
$configSnippet = New-OpenCodeConfigSnippet `
	-Provider $resolvedProvider `
	-Name $resolvedProviderName `
	-ApiRoot $apiRoot `
	-ProviderModelId $modelParts.ProviderModelId `
	-FullModelId $modelParts.FullModelId `
	-PrimaryAgent $resolvedDefaultAgent `
	-DisableBuiltInProviders $disableBuiltInProviders

$configState = [ordered]@{
	Path = $resolvedConfig
	Exists = (![string]::IsNullOrWhiteSpace($resolvedConfig) -and (Test-Path -LiteralPath $resolvedConfig -PathType Leaf))
	HasProvider = ($configText -match "`"$([regex]::Escape($resolvedProvider))`"\s*:")
	HasOpenAiCompatiblePackage = ($configText -match "@ai-sdk/openai-compatible")
	HasBaseUrl = ($configText -match [regex]::Escape($apiRoot))
	HasModel = ($configText -match [regex]::Escape($modelParts.FullModelId))
	HasDefaultAgent = ($configText -match "`"default_agent`"\s*:\s*`"$([regex]::Escape($resolvedDefaultAgent))`"")
}

$blockers = New-Object System.Collections.Generic.List[string]
if (!$health.Ready) {
	$blockers.Add("llama-server health endpoint is not ready")
}
if ($servedModels.Reachable -and !$servedModels.ExpectedModelServed) {
	$suggestion = if (@($servedModels.Models).Count -eq 1) {
		"; retry with -UseServedModel or -Model $(@($servedModels.Models)[0])"
	} else {
		""
	}
	$blockers.Add("llama-server does not advertise requested model alias: $($modelParts.ProviderModelId)$suggestion")
}
if ($configState.Exists -and (!$configState.HasProvider -or !$configState.HasOpenAiCompatiblePackage -or !$configState.HasBaseUrl -or !$configState.HasModel)) {
	$blockers.Add("OpenCode config exists but is missing the local llama.cpp provider/model shape")
}

$result = [ordered]@{
	Name = "ofxGgmlLlama local OpenCode plan"
	Root = $addonRoot.Path
	Endpoint = $resolvedEndpoint
	ServerRoot = $serverRoot
	ApiRoot = $apiRoot
	ProviderId = $resolvedProvider
	DefaultAgent = $resolvedDefaultAgent
	Model = $modelParts.ProviderModelId
	FullModel = $modelParts.FullModelId
	DisableBuiltInProviders = [bool]$disableBuiltInProviders
	UseServedModel = [bool]$UseServedModel
	SuggestedModel = if ($servedModels.Reachable -and @($servedModels.Models).Count -eq 1) { [string]@($servedModels.Models)[0] } else { "" }
	OpenCodeExe = $resolvedOpenCode
	OpenCode = $openCodeHelp
	Config = [pscustomobject]$configState
	Health = $health
	Chat = $chatProbe
	ServedModels = $servedModels
	ConfigSnippet = $configSnippet
	Blockers = @($blockers)
	Ready = ($blockers.Count -eq 0)
}

if ($Json) {
	$output = [ordered]@{}
	foreach ($key in $result.Keys) {
		if ($SummaryOnly -and $key -in @("Chat")) {
			continue
		}
		$output[$key] = $result[$key]
	}
	[pscustomobject]$output | ConvertTo-Json -Depth 12
} else {
	Write-Host "ofxGgmlLlama local OpenCode plan"
	Write-Host "  root:      $($result.Root)"
	Write-Host "  endpoint:  $($result.Endpoint)"
	Write-Host "  provider:  $($result.ProviderId)"
	Write-Host "  model:     $($result.FullModel)"
	Write-Host "  opencode:  $(if ($result.OpenCodeExe) { $result.OpenCodeExe } else { '(not found)' })"
	Write-Host "  config:    $(if ($result.Config.Path) { $result.Config.Path } else { '(not resolved)' })"
	Write-Host "  server:    $(if ($result.Health.Ready) { 'ready' } elseif ($result.Health.Reachable) { 'reachable' } else { 'down' })"
	if ($result.ServedModels.Reachable) {
		Write-Host "  served:    $(@($result.ServedModels.Models) -join ', ')"
	}
	Write-Host ""
	Write-Host "OpenCode config snippet:"
	Write-Host $result.ConfigSnippet
	Write-Host ""
	if ($result.Ready) {
		Write-Host "Ready for local OpenCode."
	} else {
		Write-Host "Blockers:"
		foreach ($blocker in $result.Blockers) {
			Write-Host "  - $blocker"
		}
		if (!$result.Config.Exists) {
			Write-Host "  - OpenCode config does not exist yet; create it from the snippet above."
		}
		if (!$result.OpenCode.Found) {
			Write-Host "  - OpenCode executable was not found; install OpenCode before launching it."
		}
	}
}

if ($Strict -and !$result.Ready) {
	exit 1
}
$global:LASTEXITCODE = 0
