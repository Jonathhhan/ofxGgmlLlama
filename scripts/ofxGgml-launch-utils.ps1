$ErrorActionPreference = "Stop"

function Write-OfxGgmlStep {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Test-OfxGgmlWindowsHost {
	return !($IsLinux -or $IsMacOS)
}

function Normalize-OfxGgmlWindowsPathEnvironment {
	if (!(Test-OfxGgmlWindowsHost)) {
		return
	}

	$variables = [Environment]::GetEnvironmentVariables("Process")
	$pathNames = New-Object System.Collections.Generic.List[string]
	foreach ($key in $variables.Keys) {
		$name = [string]$key
		if ($name.Equals("Path", [System.StringComparison]::OrdinalIgnoreCase)) {
			$pathNames.Add($name)
		}
	}
	if ($pathNames.Count -le 1) {
		return
	}

	$preferredName = if ($pathNames.Contains("Path")) { "Path" } else { $pathNames[0] }
	$pathValue = [string]$variables[$preferredName]
	if ([string]::IsNullOrWhiteSpace($pathValue)) {
		foreach ($name in $pathNames) {
			$value = [string]$variables[$name]
			if (![string]::IsNullOrWhiteSpace($value)) {
				$pathValue = $value
				break
			}
		}
	}
	foreach ($name in $pathNames) {
		if (!$name.Equals("Path", [System.StringComparison]::Ordinal)) {
			[Environment]::SetEnvironmentVariable($name, $null, "Process")
		}
	}
	[Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")
}

function Normalize-OfxGgmlPathText {
	param([string]$PathText)
	if ([string]::IsNullOrWhiteSpace($PathText)) {
		return ""
	}
	return $PathText.Trim().Trim('"')
}

function Resolve-OfxGgmlFirstFile {
	param([string[]]$Candidates)
	foreach ($candidate in $Candidates) {
		if (![string]::IsNullOrWhiteSpace($candidate) -and
			(Test-Path -LiteralPath $candidate -PathType Leaf)) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}
	return ""
}

function Get-OfxGgmlUniqueDirectories {
	param([string[]]$Directories)
	$seen = @{}
	foreach ($directory in $Directories) {
		if ([string]::IsNullOrWhiteSpace($directory)) {
			continue
		}
		$fullPath = [System.IO.Path]::GetFullPath($directory)
		$key = $fullPath.ToLowerInvariant()
		if (!$seen.ContainsKey($key)) {
			$seen[$key] = $true
			$fullPath
		}
	}
}

function Get-OfxGgmlModelFiles {
	param([string[]]$Directories)
	foreach ($directory in (Get-OfxGgmlUniqueDirectories $Directories)) {
		if (!(Test-Path -LiteralPath $directory -PathType Container)) {
			continue
		}
		Get-ChildItem -LiteralPath $directory -Filter "*.gguf" -File -ErrorAction SilentlyContinue |
			Sort-Object Name
	}
}

function Find-OfxGgmlFirstModel {
	param([string[]]$Directories)
	$model = Get-OfxGgmlModelFiles $Directories | Select-Object -First 1
	if ($model) {
		return $model.FullName
	}
	return ""
}

function Get-OfxGgmlLocalModelAlias {
	param([string]$ModelPath)

	if ([string]::IsNullOrWhiteSpace($ModelPath)) {
		return ""
	}
	$name = [System.IO.Path]::GetFileNameWithoutExtension($ModelPath)
	if ([string]::IsNullOrWhiteSpace($name)) {
		return ""
	}
	$slug = ($name -replace '[^A-Za-z0-9._-]+', '-').Trim("-")
	if ([string]::IsNullOrWhiteSpace($slug)) {
		return ""
	}
	return "local/$slug"
}

function Get-OfxGgmlModelSearchDirectories {
	param(
		[string]$AddonRoot,
		[string]$ExampleRoot = "",
		[string[]]$ExtraExampleNames = @()
	)

	$directories = New-Object System.Collections.Generic.List[string]
	if (![string]::IsNullOrWhiteSpace($ExampleRoot)) {
		$directories.Add((Join-Path $ExampleRoot "bin\data"))
		$directories.Add((Join-Path $ExampleRoot "bin\data\models"))
		$directories.Add((Join-Path $ExampleRoot "models"))
	}
	foreach ($exampleName in $ExtraExampleNames) {
		$extraRoot = Join-Path $AddonRoot $exampleName
		$directories.Add((Join-Path $extraRoot "bin\data"))
		$directories.Add((Join-Path $extraRoot "bin\data\models"))
		$directories.Add((Join-Path $extraRoot "models"))
	}
	$directories.Add((Join-Path $AddonRoot "models"))
	$directories.Add((Join-Path (Split-Path -Parent $AddonRoot) "models"))
	return @($directories)
}

function Find-OfxGgmlLlamaCli {
	param(
		[string]$AddonRoot,
		[string]$ExampleRoot
	)

	$llamaNames = if ($IsWindows -or $env:OS -eq "Windows_NT") {
		@("llama-cli.exe", "main.exe", "llama.exe")
	} else {
		@("llama-cli", "main", "llama")
	}
	$searchRoots = @(
		$AddonRoot,
		$ExampleRoot,
		(Join-Path $ExampleRoot "bin"),
		(Join-Path $ExampleRoot "bin\data")
	)
	$llamaDirs = @(
		"",
		"bin",
		"data",
		"data\bin",
		"tools",
		"libs\llama\bin",
		"libs\llama.cpp\build\bin",
		"libs\llama.cpp\build\bin\Release",
		"libs\llama.cpp\build\bin\Debug"
	)
	$candidates = foreach ($root in $searchRoots) {
		foreach ($dir in $llamaDirs) {
			foreach ($name in $llamaNames) {
				Join-Path (Join-Path $root $dir) $name
			}
		}
	}
	return Resolve-OfxGgmlFirstFile $candidates
}

function Test-OfxGgmlLocalServerUrl {
	param([string]$Url)
	try {
		$serverRoot = Get-OfxGgmlServerRootUrl $Url
		$uri = [Uri]$serverRoot
		if ($uri.Host -notin @("127.0.0.1", "localhost", "::1")) {
			return $true
		}
		$healthUrl = $serverRoot.TrimEnd("/") + "/health"
		$response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
		return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
	} catch {
		return $false
	}
}

function Get-OfxGgmlServerRootUrl {
	param([string]$Url)
	$normalized = (Normalize-OfxGgmlPathText $Url).TrimEnd("/")
	if ($normalized.EndsWith("/v1", [System.StringComparison]::OrdinalIgnoreCase)) {
		return $normalized.Substring(0, $normalized.Length - 3)
	}
	return $normalized
}

function Get-OfxGgmlServerEndpoint {
	param([string]$ServerUrl)
	$uri = [Uri](Get-OfxGgmlServerRootUrl $ServerUrl)
	$port = if ($uri.IsDefaultPort) {
		if ($uri.Scheme -ieq "https") { 443 } else { 80 }
	} else {
		$uri.Port
	}
	$hostName = if ([string]::IsNullOrWhiteSpace($uri.Host)) { "127.0.0.1" } else { $uri.Host }
	return [pscustomobject]@{
		HostName = $hostName
		Port = $port
	}
}

function Test-OfxGgmlUrl {
	param(
		[string]$Url,
		[int]$TimeoutSeconds = 2
	)

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

function Get-OfxGgmlServedModelEvidence {
	param(
		[string]$ApiRoot,
		[string]$ExpectedModel,
		[int]$TimeoutSeconds = 2
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

function Format-OfxGgmlPowerShellArgument {
	param([AllowNull()][string]$Value)
	if ($null -eq $Value) {
		return "''"
	}
	if ($Value -match "[\s`"']") {
		return "'" + ($Value -replace "'", "''") + "'"
	}
	return $Value
}

function Format-OfxGgmlCommandArgument {
	param([AllowNull()][string]$Value)
	if ($null -eq $Value) {
		return '""'
	}
	if ($Value -match '[\s"]') {
		return '"' + ($Value.Replace('"', '\"')) + '"'
	}
	return $Value
}

function Join-OfxGgmlCommandArguments {
	param([string[]]$Arguments)
	return (($Arguments | ForEach-Object { Format-OfxGgmlCommandArgument $_ }) -join " ")
}

function Get-OfxGgmlCodexLocalProviderArguments {
	param(
		[string]$ApiRoot = "http://127.0.0.1:8001/v1",
		[string]$ProviderId = "llama_cpp",
		[string]$ProviderName = "llama.cpp local",
		[string]$WireApi = "responses",
		[int]$StreamIdleTimeoutMs = 10000000,
		[int]$ModelContextWindow = 262144,
		[int]$ModelAutoCompactTokenLimit = 220000,
		[int]$ToolOutputTokenLimit = 12000,
		[string]$WebSearch = $(if ($env:OFXGGML_CODEX_WEB_SEARCH) { $env:OFXGGML_CODEX_WEB_SEARCH } else { "live" }),
		[string]$ReasoningEffort = "medium",
		[string]$ReasoningSummary = "none",
		[string]$ModelVerbosity = "low",
		[bool]$HideAgentReasoning = $true,
		[int]$AgentMaxConcurrentThreads = 0,
		[int]$AgentMaxDepth = 0,
		[switch]$SkipToolGuards,
		[switch]$SkipDesktopMcpDisable,
		[switch]$SkipProviderOverrides
	)

	$arguments = @()
	if (!$SkipToolGuards) {
		$arguments += @(
			"--disable", "apps",
			"--disable", "image_generation",
			"--disable", "browser_use",
			"--disable", "computer_use",
			"--disable", "tool_search",
			"--disable", "tool_search_always_defer_mcp_tools",
			"-c", "web_search=`"$WebSearch`""
		)
		if (!$SkipDesktopMcpDisable) {
			$arguments += @("-c", "mcp_servers.node_repl.enabled=false")
		}
	}
	if (!$SkipProviderOverrides) {
		$arguments += @(
			"-c", "model_provider=$ProviderId",
			"-c", "model_providers.$ProviderId.name=`"$ProviderName`"",
			"-c", "model_providers.$ProviderId.base_url=`"$ApiRoot`"",
			"-c", "model_providers.$ProviderId.wire_api=`"$WireApi`"",
			"-c", "model_providers.$ProviderId.stream_idle_timeout_ms=$StreamIdleTimeoutMs",
			"-c", "model_context_window=$ModelContextWindow",
			"-c", "model_auto_compact_token_limit=$ModelAutoCompactTokenLimit",
			"-c", "tool_output_token_limit=$ToolOutputTokenLimit",
			"-c", "model_reasoning_effort=$ReasoningEffort",
			"-c", "model_reasoning_summary=$ReasoningSummary",
			"-c", "model_verbosity=$ModelVerbosity",
			"-c", "hide_agent_reasoning=$($HideAgentReasoning.ToString().ToLowerInvariant())"
		)
	}
	if ($AgentMaxConcurrentThreads -gt 0) {
		$arguments += @("-c", "agents.max_threads=$AgentMaxConcurrentThreads")
	}
	if ($AgentMaxDepth -gt 0) {
		$arguments += @("-c", "agents.max_depth=$AgentMaxDepth")
	}
	return @($arguments)
}

function Start-OfxGgmlBundledLlamaServerIfNeeded {
	param(
		[string]$ScriptRoot,
		[string]$AddonRoot,
		[string]$ServerUrl,
		[string]$Model,
		[string]$LogDir,
		[string]$MissingModelWarning,
		[string]$StartMessage,
		[int]$StartupTimeoutSeconds = 120,
		[string]$Alias = "",
		[string]$GpuLayers = "",
		[Nullable[int]]$ContextSize = $null,
		[Nullable[int]]$Parallel = $null,
		[Nullable[int]]$BatchSize = $null,
		[Nullable[int]]$UBatchSize = $null,
		[Nullable[int]]$Threads = $null,
		[Nullable[int]]$ThreadsBatch = $null,
		[Nullable[int]]$ThreadsHttp = $null,
		[Nullable[int]]$CacheReuse = $null,
		[string]$KvCacheKeyType = "",
		[string]$KvCacheValueType = "",
		[string]$SpecType = "",
		[string]$DraftModel = "",
		[string]$DraftGpuLayers = "",
		[Nullable[int]]$DraftMaxTokens = $null,
		[Nullable[int]]$DraftMinTokens = $null,
		[string]$DraftPSplit = "",
		[string]$DraftPMin = "",
		[string]$Temperature = "",
		[string]$TopP = "",
		[string]$MinP = "",
		[string]$ChatTemplateKwargs = "",
		[string]$Reasoning = "",
		[string]$ReasoningBudget = "",
		[switch]$Jinja,
		[switch]$FlashAttention,
		[switch]$NoCudaGraphs,
		[switch]$SkipChatParsing,
		[switch]$ForceNew,
		[switch]$NoAutoServer,
		[switch]$Embeddings
	)

	if ($NoAutoServer -or (!$ForceNew -and (Test-OfxGgmlLocalServerUrl $ServerUrl))) {
		return
	}
	if ([string]::IsNullOrWhiteSpace($Model)) {
		Write-Warning $MissingModelWarning
		return
	}

	$endpoint = Get-OfxGgmlServerEndpoint $ServerUrl
	Write-OfxGgmlStep $StartMessage
	$args = @(
		"-ModelPath", $Model,
		"-HostName", $endpoint.HostName,
		"-Port", $endpoint.Port,
		"-Detached",
		"-StartupTimeoutSeconds", $StartupTimeoutSeconds,
		"-LogDir", $LogDir
	)
	if (![string]::IsNullOrWhiteSpace($Alias)) {
		$args += "-Alias"
		$args += $Alias
	}
	if (![string]::IsNullOrWhiteSpace($GpuLayers)) {
		$args += "-GpuLayers"
		$args += $GpuLayers
	}
	if ($null -ne $ContextSize) {
		$args += "-ContextSize"
		$args += $ContextSize
	}
	if ($null -ne $Parallel) {
		$args += "-Parallel"
		$args += $Parallel
	}
	if ($null -ne $BatchSize) {
		$args += "-BatchSize"
		$args += $BatchSize
	}
	if ($null -ne $UBatchSize) {
		$args += "-UBatchSize"
		$args += $UBatchSize
	}
	if ($null -ne $Threads) {
		$args += "-Threads"
		$args += $Threads
	}
	if ($null -ne $ThreadsBatch) {
		$args += "-ThreadsBatch"
		$args += $ThreadsBatch
	}
	if ($null -ne $ThreadsHttp) {
		$args += "-ThreadsHttp"
		$args += $ThreadsHttp
	}
	if ($null -ne $CacheReuse) {
		$args += "-CacheReuse"
		$args += $CacheReuse
	}
	if (![string]::IsNullOrWhiteSpace($KvCacheKeyType)) {
		$args += "-KvCacheKeyType"
		$args += $KvCacheKeyType
	}
	if (![string]::IsNullOrWhiteSpace($KvCacheValueType)) {
		$args += "-KvCacheValueType"
		$args += $KvCacheValueType
	}
	if (![string]::IsNullOrWhiteSpace($SpecType)) {
		$args += "-SpecType"
		$args += $SpecType
	}
	if (![string]::IsNullOrWhiteSpace($DraftModel)) {
		$args += "-DraftModel"
		$args += $DraftModel
	}
	if (![string]::IsNullOrWhiteSpace($DraftGpuLayers)) {
		$args += "-DraftGpuLayers"
		$args += $DraftGpuLayers
	}
	if ($null -ne $DraftMaxTokens) {
		$args += "-DraftMaxTokens"
		$args += $DraftMaxTokens
	}
	if ($null -ne $DraftMinTokens) {
		$args += "-DraftMinTokens"
		$args += $DraftMinTokens
	}
	if (![string]::IsNullOrWhiteSpace($DraftPSplit)) {
		$args += "-DraftPSplit"
		$args += $DraftPSplit
	}
	if (![string]::IsNullOrWhiteSpace($DraftPMin)) {
		$args += "-DraftPMin"
		$args += $DraftPMin
	}
	if (![string]::IsNullOrWhiteSpace($Temperature)) {
		$args += "-Temperature"
		$args += $Temperature
	}
	if (![string]::IsNullOrWhiteSpace($TopP)) {
		$args += "-TopP"
		$args += $TopP
	}
	if (![string]::IsNullOrWhiteSpace($MinP)) {
		$args += "-MinP"
		$args += $MinP
	}
	if (![string]::IsNullOrWhiteSpace($ChatTemplateKwargs)) {
		$args += "-ChatTemplateKwargs"
		$args += $ChatTemplateKwargs
	}
	if (![string]::IsNullOrWhiteSpace($Reasoning)) {
		$args += "-Reasoning"
		$args += $Reasoning
	}
	if (![string]::IsNullOrWhiteSpace($ReasoningBudget)) {
		$args += "-ReasoningBudget"
		$args += $ReasoningBudget
	}
	if ($Jinja) {
		$args += "-Jinja"
	}
	if ($FlashAttention) {
		$args += "-FlashAttention"
	}
	if ($SkipChatParsing) {
		$args += "-SkipChatParsing"
	}
	if ($NoCudaGraphs) {
		$args += "-NoCudaGraphs"
	}
	if ($ForceNew) {
		$args += "-ForceNew"
	}
	if ($Embeddings) {
		$args += "-Embeddings"
	}
	& (Join-Path $ScriptRoot "start-llama-server.ps1") @args
}
