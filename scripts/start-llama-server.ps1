param(
	[string]$ModelPath = $(if ($env:OFXGGML_TEXT_MODEL) { $env:OFXGGML_TEXT_MODEL } else { "" }),
	[string]$ServerExe = $(if ($env:OFXGGML_LLAMA_SERVER) { $env:OFXGGML_LLAMA_SERVER } else { "" }),
	[string]$HostName = "127.0.0.1",
	[int]$Port = 8080,
	[string]$Alias = "",
	[string]$GpuLayers = "28",
	[int]$ContextSize = 4096,
	[int]$Parallel = 1,
	[int]$BatchSize = 0,
	[int]$UBatchSize = 0,
	[int]$Threads = 0,
	[int]$ThreadsBatch = 0,
	[int]$ThreadsHttp = 0,
	[int]$CacheReuse = 0,
	[string]$Temperature = "",
	[string]$TopP = "",
	[string]$MinP = "",
	[string]$ChatTemplateKwargs = "",
	[string]$Reasoning = "",
	[string]$ReasoningBudget = "",
	[string]$EmbeddingPooling = "mean",
	[switch]$Jinja,
	[switch]$FlashAttention,
	[switch]$NoCudaGraphs,
	[switch]$SkipChatParsing,
	[switch]$Embeddings,
	[switch]$Detached,
	[switch]$ForceNew,
	[switch]$NoHealthCheck,
	[int]$StartupTimeoutSeconds = 30,
	[string]$LogDir = "",
	[switch]$DryRun
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")
Normalize-OfxGgmlWindowsPathEnvironment

if ($env:OFXGGML_LAUNCH_DRY_RUN_ONLY -eq "1") {
	$DryRun = $true
	$Detached = $false
	$NoHealthCheck = $true
}

function Get-ServerUrl {
	param([string]$HostValue, [int]$PortValue)
	return "http://$HostValue`:$PortValue"
}

function Get-HealthUrl {
	param([string]$ServerUrl)
	return "$ServerUrl/health"
}

function Test-LlamaServer {
	param([string]$ServerUrl)
	$result = [ordered]@{
		Reachable = $false
		Ready = $false
		StatusCode = 0
		Message = ""
	}
	try {
		$response = Invoke-WebRequest `
			-Uri (Get-HealthUrl $ServerUrl) `
			-UseBasicParsing `
			-TimeoutSec 2 `
			-ErrorAction Stop
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

function Wait-LlamaServer {
	param([string]$ServerUrl, [int]$TimeoutSeconds)
	$deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
	do {
		$health = Test-LlamaServer $ServerUrl
		if ($health.Ready) {
			return $health
		}
		Start-Sleep -Milliseconds 500
	} while ((Get-Date) -lt $deadline)
	return Test-LlamaServer $ServerUrl
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

function Test-LlamaServerArgument {
	param(
		[string]$ServerExePath,
		[string]$Argument
	)
	$previousErrorActionPreference = $ErrorActionPreference
	try {
		$ErrorActionPreference = "Continue"
		$output = & $ServerExePath --help *>&1 | ForEach-Object { $_.ToString() }
		return (($output -join "`n") -like "*$Argument*")
	} catch {
		return $false
	} finally {
		$ErrorActionPreference = $previousErrorActionPreference
	}
}

function Get-ProcessPath {
	param([System.Diagnostics.Process]$Process)
	try {
		return [string]$Process.Path
	} catch {
		return ""
	}
}

function Stop-MatchingLlamaServer {
	param([string]$ServerExePath)
	$targetPath = (Resolve-Path -LiteralPath $ServerExePath).Path
	$targets = @(Get-Process -Name "llama-server" -ErrorAction SilentlyContinue |
		Where-Object {
			$processPath = Get-ProcessPath $_
			![string]::IsNullOrWhiteSpace($processPath) -and
				$processPath.Equals($targetPath, [System.StringComparison]::OrdinalIgnoreCase)
		} |
		Sort-Object Id)
	if ($targets.Count -eq 0) {
		return 0
	}
	foreach ($process in $targets) {
		Stop-Process -Id $process.Id -Force -ErrorAction Stop
	}
	return $targets.Count
}

if ([string]::IsNullOrWhiteSpace($ServerExe)) {
	$serverName = if ($IsLinux -or $IsMacOS) { "llama-server" } else { "llama-server.exe" }
	$ServerExe = Resolve-OfxGgmlFirstFile @(
		(Join-Path $addonRoot "libs\llama\bin\$serverName"),
		(Join-Path $addonRoot "libs\llama.cpp\build\bin\Release\$serverName"),
		(Join-Path $addonRoot "libs\llama.cpp\build\bin\$serverName"),
		(Join-Path $addonRoot "libs\llama.cpp\build\$serverName")
	)
}
if ([string]::IsNullOrWhiteSpace($ServerExe)) {
	throw "Could not find llama-server. Build it with scripts\build-llama-server.bat or pass -ServerExe."
}

if ([string]::IsNullOrWhiteSpace($ModelPath) -and $Embeddings -and $env:OFXGGML_EMBEDDING_MODEL) {
	$ModelPath = $env:OFXGGML_EMBEDDING_MODEL
}

if ([string]::IsNullOrWhiteSpace($ModelPath)) {
	$primaryExample = if ($Embeddings) { "ofxGgmlEmbeddingExample" } else { "ofxGgmlTextExample" }
	$extraExamples = if ($Embeddings) {
		@("ofxGgmlTextExample", "ofxGgmlChatExample")
	} else {
		@("ofxGgmlChatExample")
	}
	$ModelPath = Find-OfxGgmlFirstModel (Get-OfxGgmlModelSearchDirectories `
		-AddonRoot $addonRoot `
		-ExampleRoot (Join-Path $addonRoot $primaryExample) `
		-ExtraExampleNames $extraExamples)
}
if ([string]::IsNullOrWhiteSpace($ModelPath)) {
	$modelEnv = if ($Embeddings) { "OFXGGML_EMBEDDING_MODEL" } else { "OFXGGML_TEXT_MODEL" }
	throw "Could not find a GGUF model. Pass -ModelPath or set $modelEnv."
}
if (!(Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
	throw "Model file was not found: $ModelPath"
}
$ModelPath = (Resolve-Path -LiteralPath $ModelPath).Path
$ServerExe = (Resolve-Path -LiteralPath $ServerExe).Path

if ($ForceNew -and !$DryRun) {
	$stopped = Stop-MatchingLlamaServer -ServerExePath $ServerExe
	if ($stopped -gt 0) {
		Write-Host "Stopped $stopped existing llama-server process(es) for $ServerExe"
		Start-Sleep -Milliseconds 750
	}
}

if ($Embeddings -and !$PSBoundParameters.ContainsKey("Port")) {
	$Port = 8081
}

$serverUrl = Get-ServerUrl $HostName $Port
$serverUrlEnvName = if ($Embeddings) { "OFXGGML_EMBEDDING_SERVER_URL" } else { "OFXGGML_TEXT_SERVER_URL" }
if (!$NoHealthCheck -and !$DryRun) {
	$existing = Test-LlamaServer $serverUrl
	if ($existing.Reachable -and !$ForceNew) {
		Write-Host "llama-server is already reachable."
		Write-Host "  url:       $serverUrl"
		Write-Host "  health:    HTTP $($existing.StatusCode) $(if ($existing.Ready) { '(ready)' } else { '(starting/busy)' })"
		if (![string]::IsNullOrWhiteSpace($existing.Message)) {
			Write-Host "  response:  $($existing.Message)"
		}
		Write-Host ""
		Write-Host "Reusing the existing server. Pass -ForceNew to start another process anyway."
		Write-Host "Use $serverUrlEnvName=$serverUrl"
		return
	}
}

$arguments = @(
	"-m", $ModelPath,
	"--host", $HostName,
	"--port", $Port.ToString(),
	"-ngl", $GpuLayers,
	"-c", ([Math]::Max(512, $ContextSize)).ToString()
)
if ($Parallel -gt 0) {
	$arguments += "--parallel"
	$arguments += ([Math]::Max(1, $Parallel)).ToString()
}
if ($FlashAttention) {
	$arguments += "--flash-attn"
	$arguments += "on"
}
if ($BatchSize -gt 0) {
	$arguments += "--batch-size"
	$arguments += $BatchSize.ToString()
}
if ($UBatchSize -gt 0) {
	$arguments += "--ubatch-size"
	$arguments += $UBatchSize.ToString()
}
if ($Threads -gt 0) {
	$arguments += "--threads"
	$arguments += $Threads.ToString()
}
if ($ThreadsBatch -gt 0) {
	$arguments += "--threads-batch"
	$arguments += $ThreadsBatch.ToString()
}
if ($ThreadsHttp -gt 0) {
	$arguments += "--threads-http"
	$arguments += $ThreadsHttp.ToString()
}
if ($CacheReuse -gt 0) {
	$arguments += "--cache-reuse"
	$arguments += $CacheReuse.ToString()
}
if (![string]::IsNullOrWhiteSpace($Alias)) {
	$arguments += "--alias"
	$arguments += $Alias
}
if (![string]::IsNullOrWhiteSpace($Temperature)) {
	$arguments += "--temp"
	$arguments += $Temperature
}
if (![string]::IsNullOrWhiteSpace($TopP)) {
	$arguments += "--top-p"
	$arguments += $TopP
}
if (![string]::IsNullOrWhiteSpace($MinP)) {
	$arguments += "--min-p"
	$arguments += $MinP
}
if ($Jinja) {
	$arguments += "--jinja"
}
if (![string]::IsNullOrWhiteSpace($ChatTemplateKwargs)) {
	$arguments += "--chat-template-kwargs"
	$arguments += $ChatTemplateKwargs
}
if (![string]::IsNullOrWhiteSpace($Reasoning)) {
	$arguments += "--reasoning"
	$arguments += $Reasoning
}
if (![string]::IsNullOrWhiteSpace($ReasoningBudget)) {
	$arguments += "--reasoning-budget"
	$arguments += $ReasoningBudget
}
$cudaGraphsArgumentSupported = $true
if ($NoCudaGraphs -and !$DryRun) {
	$cudaGraphsArgumentSupported = Test-LlamaServerArgument -ServerExePath $ServerExe -Argument "--no-cuda-graphs"
	if (!$cudaGraphsArgumentSupported) {
		Write-Warning "llama-server does not support --no-cuda-graphs; using server CUDA graph default."
	}
}
if ($SkipChatParsing -and !$DryRun) {
	$skipChatParsingArgumentSupported = Test-LlamaServerArgument -ServerExePath $ServerExe -Argument "--skip-chat-parsing"
	if (!$skipChatParsingArgumentSupported) {
		Write-Warning "llama-server does not support --skip-chat-parsing; continuing without it."
	}
}
if ($NoCudaGraphs -and $cudaGraphsArgumentSupported) {
	$arguments += "--no-cuda-graphs"
}
if ($SkipChatParsing -and $skipChatParsingArgumentSupported) {
	$arguments += "--skip-chat-parsing"
}
if ($Embeddings) {
	$arguments += "--embeddings"
	if (![string]::IsNullOrWhiteSpace($EmbeddingPooling)) {
		$arguments += "--pooling"
		$arguments += $EmbeddingPooling
	}
}
if (![string]::IsNullOrWhiteSpace($LogDir)) {
	New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
	$LogDir = (Resolve-Path -LiteralPath $LogDir).Path
	$arguments += "--log-file"
	$arguments += (Join-Path $LogDir "llama-server.log")
}

Write-Host "Starting llama-server"
Write-Host "  exe:       $ServerExe"
Write-Host "  model:     $ModelPath"
Write-Host "  url:       $serverUrl"
Write-Host "  backend:   llama.cpp auto"
if (![string]::IsNullOrWhiteSpace($Alias)) {
	Write-Host "  alias:     $Alias"
}
Write-Host "  ngl:       $GpuLayers"
Write-Host "  ctx:       $ContextSize"
Write-Host "  parallel:  $Parallel"
if ($BatchSize -gt 0) {
	Write-Host "  batch:     $BatchSize"
}
if ($UBatchSize -gt 0) {
	Write-Host "  ubatch:    $UBatchSize"
}
Write-Host "  threads:   $(if ($Threads -gt 0) { $Threads } else { 'auto' })"
Write-Host "  batchTh:   $(if ($ThreadsBatch -gt 0) { $ThreadsBatch } else { 'auto' })"
Write-Host "  httpTh:    $(if ($ThreadsHttp -gt 0) { $ThreadsHttp } else { 'auto' })"
Write-Host "  cacheReuse: $(if ($CacheReuse -gt 0) { $CacheReuse } else { 'default' })"
if (![string]::IsNullOrWhiteSpace($Temperature)) {
	Write-Host "  temp:      $Temperature"
}
if (![string]::IsNullOrWhiteSpace($TopP)) {
	Write-Host "  top_p:     $TopP"
}
if (![string]::IsNullOrWhiteSpace($MinP)) {
	Write-Host "  min_p:     $MinP"
}
Write-Host "  jinja:     $(if ($Jinja) { 'on' } else { 'default' })"
Write-Host "  flashAttn: $(if ($FlashAttention) { 'on' } else { 'default' })"
if (![string]::IsNullOrWhiteSpace($Reasoning)) {
	Write-Host "  reasoning: $Reasoning"
}
if (![string]::IsNullOrWhiteSpace($ReasoningBudget)) {
	Write-Host "  thinkBudget: $ReasoningBudget"
}
Write-Host "  cudaGraph: $(if (!$NoCudaGraphs) { 'on' } elseif ($cudaGraphsArgumentSupported) { 'off' } else { 'off requested; unsupported by this llama-server' })"
Write-Host "  skipChatParsing: $(if ($SkipChatParsing -and $skipChatParsingArgumentSupported) { 'on' } elseif ($SkipChatParsing) { 'requested; unsupported by this llama-server' } else { 'off' })"
Write-Host "  embeddings: $(if ($Embeddings) { 'on' } else { 'off' })"
if ($Embeddings) {
	Write-Host "  serverMode: embeddings only"
	Write-Host "  pooling:   $EmbeddingPooling"
}
Write-Host "  mode:      $(if ($Detached) { 'detached' } else { 'foreground' })"
if (![string]::IsNullOrWhiteSpace($LogDir)) {
	Write-Host "  logs:      $LogDir"
}
Write-Host ""
Write-Host ("`"$ServerExe`" " + (Join-ProcessArguments $arguments))

if ($DryRun) {
	return
}

$workingDir = Split-Path -Parent $ServerExe
if ($Detached) {
	$startInfo = New-Object System.Diagnostics.ProcessStartInfo
	$startInfo.FileName = $ServerExe
	$startInfo.Arguments = Join-ProcessArguments $arguments
	$startInfo.WorkingDirectory = $workingDir
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$process = New-Object System.Diagnostics.Process
	$process.StartInfo = $startInfo
	if (![string]::IsNullOrWhiteSpace($LogDir)) {
		Set-Content -LiteralPath (Join-Path $LogDir "llama-server.command.txt") `
			-Value ("`"$ServerExe`" " + (Join-ProcessArguments $arguments))
	}
	if (!$process.Start()) {
		throw "Failed to start llama-server."
	}
	Write-Host ""
	Write-Host "llama-server started in the background (PID $($process.Id))."
	Write-Host "Use $serverUrlEnvName=$serverUrl"
	if (![string]::IsNullOrWhiteSpace($LogDir)) {
		Write-Host "Command line saved in $LogDir"
	}
	if (!$NoHealthCheck -and $StartupTimeoutSeconds -gt 0) {
		Write-Host "Waiting up to $StartupTimeoutSeconds seconds for llama-server readiness..."
		$deadline = (Get-Date).AddSeconds([Math]::Max(1, $StartupTimeoutSeconds))
		do {
			if ($process.HasExited) {
				$stderrTail = ""
				if (![string]::IsNullOrWhiteSpace($LogDir)) {
					$logPath = Join-Path $LogDir "llama-server.log"
					if (Test-Path -LiteralPath $logPath -PathType Leaf) {
						$stderrTail = ((Get-Content -LiteralPath $logPath -Tail 8 -ErrorAction SilentlyContinue) -join " ").Trim()
					}
				}
				$detail = if (![string]::IsNullOrWhiteSpace($stderrTail)) { " $stderrTail" } else { "" }
				throw "llama-server exited before readiness with code $($process.ExitCode).$detail"
			}
			$health = Test-LlamaServer $serverUrl
			if ($health.Ready) {
				break
			}
			Start-Sleep -Milliseconds 500
		} while ((Get-Date) -lt $deadline)
		if (!$health.Ready) {
			$health = Test-LlamaServer $serverUrl
		}
		if ($health.Ready) {
			Write-Host "llama-server is ready at $serverUrl"
		} else {
			$detail = if ($health.Reachable) {
				"HTTP $($health.StatusCode) $($health.Message)"
			} else {
				$health.Message
			}
			throw "llama-server did not become ready at $serverUrl within $StartupTimeoutSeconds seconds. $detail"
		}
	}
	Write-Output "OFXGGML_LLAMA_SERVER_PID=$($process.Id)"
} else {
	Write-Host ""
	Write-Host "llama-server is running in this console. Press Ctrl+C to stop it."
	Write-Host "Use $serverUrlEnvName=$serverUrl"
	& $ServerExe @arguments
}
