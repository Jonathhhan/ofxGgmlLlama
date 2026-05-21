param(
	[string]$TextServerUrl = $(if ($env:OFXGGML_TEXT_SERVER_URL) { $env:OFXGGML_TEXT_SERVER_URL } else { "http://127.0.0.1:8080" }),
	[string]$EmbeddingServerUrl = $(if ($env:OFXGGML_EMBEDDING_SERVER_URL) { $env:OFXGGML_EMBEDDING_SERVER_URL } else { "http://127.0.0.1:8081" }),
	[string]$CodexServerUrl = $(if ($env:OFXGGML_CODEX_BASE_URL) { $env:OFXGGML_CODEX_BASE_URL } else { "http://127.0.0.1:8001" }),
	[int]$TimeoutSeconds = 1,
	[switch]$All,
	[switch]$Json,
	[switch]$Strict
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")

function Get-ProcessPath {
	param([System.Diagnostics.Process]$Process)
	try {
		return [string]$Process.Path
	} catch {
		return ""
	}
}

function Get-LlamaProcesses {
	$addonPath = $addonRoot.Path
	return @(Get-Process -Name "llama-server" -ErrorAction SilentlyContinue |
		Where-Object {
			if ($All) {
				return $true
			}
			$processPath = Get-ProcessPath $_
			![string]::IsNullOrWhiteSpace($processPath) -and
				$processPath.StartsWith($addonPath, [System.StringComparison]::OrdinalIgnoreCase)
		} |
		Sort-Object Id |
		ForEach-Object {
			[pscustomobject]@{
				ProcessName = $_.ProcessName
				Id = $_.Id
				Path = Get-ProcessPath $_
			}
		})
}

function Test-ServerHealth {
	param([string]$Url, [string]$Label)
	$serverRoot = if ([string]::IsNullOrWhiteSpace($Url)) { "" } else { $Url.TrimEnd("/") }
	if (![string]::IsNullOrWhiteSpace($serverRoot) -and
		$serverRoot.EndsWith("/v1", [System.StringComparison]::OrdinalIgnoreCase)) {
		$serverRoot = $serverRoot.Substring(0, $serverRoot.Length - 3)
	}
	$result = [ordered]@{
		Label = $Label
		Url = $serverRoot
		Reachable = $false
		Ready = $false
		StatusCode = 0
		Message = ""
	}
	if ([string]::IsNullOrWhiteSpace($Url)) {
		$result.Message = "URL is not set"
		return [pscustomobject]$result
	}
	try {
		$response = Invoke-WebRequest -Uri ($serverRoot + "/health") -UseBasicParsing -TimeoutSec ([Math]::Max(1, $TimeoutSeconds)) -ErrorAction Stop
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

$processes = @(Get-LlamaProcesses)
$servers = @(
	(Test-ServerHealth -Url $TextServerUrl -Label "text"),
	(Test-ServerHealth -Url $EmbeddingServerUrl -Label "embedding"),
	(Test-ServerHealth -Url $CodexServerUrl -Label "codex")
)

if ($Json) {
	[pscustomobject]@{
		Root = $addonRoot.Path
		Scope = if ($All) { "all" } else { "addon" }
		Processes = $processes
		Servers = $servers
	} | ConvertTo-Json -Depth 4
} else {
	Write-Host "llama-server status"
	Write-Host "  root:  $addonRoot"
	Write-Host "  scope: $(if ($All) { 'all matching processes' } else { 'this addon only' })"
	Write-Host "  timeout: $([Math]::Max(1, $TimeoutSeconds))s"
	Write-Host ""
	Write-Host "Processes:"
	if ($processes.Count -eq 0) {
		Write-Host "  (none)"
	} else {
		foreach ($process in $processes) {
			Write-Host ("  {0}({1}) {2}" -f $process.ProcessName, $process.Id, $process.Path)
		}
	}
	Write-Host ""
	Write-Host "Endpoints:"
	foreach ($server in $servers) {
		$status = if ($server.Ready) {
			"ready"
		} elseif ($server.Reachable) {
			"reachable"
		} else {
			"down"
		}
		$code = if ($server.StatusCode -gt 0) { " HTTP $($server.StatusCode)" } else { "" }
		Write-Host ("  {0,-9} {1}  {2}{3}" -f $server.Label, $server.Url, $status, $code)
		if (![string]::IsNullOrWhiteSpace($server.Message) -and $server.Message.Length -lt 160) {
			Write-Host "            $($server.Message)"
		}
	}
}

if ($Strict -and @($servers | Where-Object { !$_.Ready }).Count -gt 0) {
	exit 1
}
