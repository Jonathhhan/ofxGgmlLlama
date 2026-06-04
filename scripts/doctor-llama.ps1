param(
	[string]$TextServerUrl = $(if ($env:OFXGGML_TEXT_SERVER_URL) { $env:OFXGGML_TEXT_SERVER_URL } else { "http://127.0.0.1:8080" }),
	[string]$EmbeddingServerUrl = $(if ($env:OFXGGML_EMBEDDING_SERVER_URL) { $env:OFXGGML_EMBEDDING_SERVER_URL } else { "http://127.0.0.1:8081" }),
	[switch]$Json,
	[switch]$Strict
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$addonsRoot = Split-Path -Parent $addonRoot
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")
$script:Warnings = 0

function Test-CommandAvailable {
	param([string]$Name)
	return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function New-Check {
	param(
		[string]$State,
		[string]$Name,
		[string]$Detail = ""
	)
	if ($State -eq "WARN") {
		$script:Warnings++
	}
	return [pscustomobject]@{
		State = $State
		Name = $Name
		Detail = $Detail
	}
}

function Test-AnyPath {
	param([string[]]$Paths)
	foreach ($path in $Paths) {
		if (Test-Path -LiteralPath $path -PathType Leaf) {
			return $path
		}
	}
	return ""
}

function Get-GgufModels {
	$directories = Get-OfxGgmlUniqueDirectories @(
		(Join-Path $addonRoot "ofxGgmlTextExample\bin\data\models"),
		(Join-Path $addonRoot "ofxGgmlTextExample\models"),
		(Join-Path $addonRoot "ofxGgmlChatExample\bin\data\models"),
		(Join-Path $addonRoot "ofxGgmlChatExample\models"),
		(Join-Path $addonRoot "ofxGgmlEmbeddingExample\bin\data\models"),
		(Join-Path $addonRoot "ofxGgmlEmbeddingExample\models"),
		(Join-Path $addonRoot "models"),
		(Join-Path $addonsRoot "models")
	)
	return @(Get-OfxGgmlModelFiles $directories | Select-Object -ExpandProperty FullName)
}

function Get-ServerStatus {
	$statusScript = Join-Path $scriptRoot "status-llama-server.ps1"
	if (!(Test-Path -LiteralPath $statusScript -PathType Leaf)) {
		return $null
	}
	$statusJson = & $statusScript -TextServerUrl $TextServerUrl -EmbeddingServerUrl $EmbeddingServerUrl -Json *>&1
	if (!$?) {
		return $null
	}
	return ($statusJson -join "`n") | ConvertFrom-Json
}

function Test-EndpointProbe {
	param([string]$BaseUrl, [string]$ProbePath, [string]$Label, [hashtable]$Body = $null)
	$serverRoot = $BaseUrl.TrimEnd("/")
	$uri = "$serverRoot$ProbePath"
	$result = [ordered]@{
		Label = $Label
		Uri = $uri
		Ok = $false
		StatusCode = 0
		Message = ""
	}
	try {
		if ($null -ne $Body) {
			$jsonBody = $Body | ConvertTo-Json -Compress
			$response = Invoke-WebRequest -Uri $uri -Method Post -UseBasicParsing -TimeoutSec 5 `
				-ContentType "application/json" -Body $jsonBody -ErrorAction Stop
		} else {
			$response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
		}
		$result.StatusCode = [int]$response.StatusCode
		$result.Ok = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300)
		$result.Message = ($response.Content | Out-String).Trim()
		if ($result.Message.Length -gt 200) {
			$result.Message = $result.Message.Substring(0, 200) + "..."
		}
	} catch {
		if ($_.Exception.Response) {
			$result.StatusCode = [int]$_.Exception.Response.StatusCode
			$result.Message = $_.Exception.Message
		} else {
			$result.Message = $_.Exception.Message
		}
	}
	return [pscustomobject]$result
}

function Test-PortConflict {
	param([string]$HostName, [int]$Port)
	$tcp = New-Object System.Net.Sockets.TcpClient
	try {
		$tcp.Connect($Host, $Port)
		return $true
	} catch {
		return $false
	} finally {
		try { $tcp.Close() } catch {}
	}
}

function Get-ServerReadiness {
	param([string]$Url, [string]$Label)
	$serverRoot = $Url.TrimEnd("/")
	$hostPart = $serverRoot -replace '^http://', ''
	$port = [int]($hostPart -split ':')[1]
	$hostName = ($hostPart -split ':')[0]
	
	$portOpen = Test-PortConflict -HostName $hostName -Port $port
	$probes = @()
	
	if ($portOpen) {
		$probes += Test-EndpointProbe -BaseUrl $serverRoot -ProbePath "/health" -Label "$Label health"
		$probes += Test-EndpointProbe -BaseUrl $serverRoot -ProbePath "/v1/models" -Label "$Label models"
		$probes += Test-EndpointProbe -BaseUrl $serverRoot -ProbePath "/v1/chat/completions" -Label "$Label chat" `
			-Body @{ model = "test"; messages = @(@{ role = "user"; content = "hi" }) }
	}
	
	$healthOk = @($probes | Where-Object { $_.Label -eq "$Label health" -and $_.Ok }).Count -gt 0
	$modelsOk = @($probes | Where-Object { $_.Label -eq "$Label models" -and $_.Ok }).Count -gt 0
	
	$state = "WARN"
	$detail = "port $port closed"
	if ($portOpen) {
		if ($healthOk -and $modelsOk) {
			$state = "OK"
			$detail = "health + /v1/models responsive"
		} elseif ($healthOk) {
			$state = "WARN"
			$detail = "health OK but /v1/models failed"
		} else {
			$state = "WARN"
			$detail = "port open but health probe failed"
		}
	}
	
	return [pscustomobject]@{
		State = $state
		Label = $Label
		Url = $serverRoot
		Probes = $probes
		Detail = $detail
	}
}

$checks = @()
$checks += New-Check "OK" "addon root" $addonRoot.Path

foreach ($tool in @("git", "cmake")) {
	if (Test-CommandAvailable $tool) {
		$checks += New-Check "OK" $tool ((Get-Command $tool).Source)
	} else {
		$checks += New-Check "WARN" $tool "not found in PATH"
	}
}

$corePath = Join-Path $addonsRoot "ofxGgmlCore"
if (Test-Path -LiteralPath $corePath -PathType Container) {
	$checks += New-Check "OK" "ofxGgmlCore sibling" $corePath
} else {
	$checks += New-Check "WARN" "ofxGgmlCore sibling" "clone beside ofxGgmlLlama"
}

$ofxImGuiPath = Join-Path $addonsRoot "ofxImGui"
if (Test-Path -LiteralPath $ofxImGuiPath -PathType Container) {
	$checks += New-Check "OK" "ofxImGui" $ofxImGuiPath
} else {
	$checks += New-Check "WARN" "ofxImGui" "install beside ofxGgmlLlama before building GUI examples"
}

foreach ($example in @("ofxGgmlTextExample", "ofxGgmlChatExample", "ofxGgmlEmbeddingExample")) {
	$exampleRoot = Join-Path $addonRoot $example
	if (Test-Path -LiteralPath (Join-Path $exampleRoot "addons.make") -PathType Leaf) {
		$checks += New-Check "OK" $example "example skeleton present"
	} else {
		$checks += New-Check "WARN" $example "example skeleton missing or incomplete"
	}
}

$serverName = if ($IsLinux -or $IsMacOS) { "llama-server" } else { "llama-server.exe" }
$serverPath = Test-AnyPath @(
	(Join-Path $addonRoot "libs\llama\bin\$serverName"),
	(Join-Path $addonRoot "libs\llama.cpp\build\bin\Release\$serverName"),
	(Join-Path $addonRoot "libs\llama.cpp\build\bin\$serverName"),
	(Join-Path $addonRoot "libs\llama.cpp\build\$serverName")
)
if (![string]::IsNullOrWhiteSpace($serverPath)) {
	$checks += New-Check "OK" "llama-server" $serverPath
} else {
	$checks += New-Check "WARN" "llama-server" "run scripts\build-llama-server.bat"
}

$models = @(Get-GgufModels)
if ($models.Count -gt 0) {
	$checks += New-Check "OK" "GGUF models" "$($models.Count) found"
} else {
	$checks += New-Check "WARN" "GGUF models" "put models under addons\models, ofxGgmlLlama\models, or pass -Model"
}

$serverReadiness = @(
	Get-ServerReadiness -Url $TextServerUrl -Label "text"
	Get-ServerReadiness -Url $EmbeddingServerUrl -Label "embedding"
)
foreach ($readiness in $serverReadiness) {
	$checks += New-Check $readiness.State "$($readiness.Label) server" "$($readiness.Detail) at $($readiness.Url)"
}

$artifactTest = Join-Path $scriptRoot "dev\test-artifact-hygiene.ps1"
if (Test-Path -LiteralPath $artifactTest -PathType Leaf) {
	& $artifactTest *>$null
	if ($LASTEXITCODE -eq 0) {
		$checks += New-Check "OK" "artifact hygiene" "generated artifacts are ignored"
	} else {
		$checks += New-Check "WARN" "artifact hygiene" "run scripts\dev\test-artifact-hygiene.ps1"
	}
}

if ($Json) {
	[pscustomobject]@{
		Root = $addonRoot.Path
		Warnings = $script:Warnings
		Checks = $checks
		Models = $models
		ServerReadiness = $serverReadiness
	} | ConvertTo-Json -Depth 6
} else {
	Write-Host "ofxGgmlLlama doctor"
	Write-Host "Root  $addonRoot"
	Write-Host ""
	foreach ($check in $checks) {
		$line = "{0,-5} {1}" -f $check.State, $check.Name
		if (![string]::IsNullOrWhiteSpace($check.Detail)) {
			$line += " - $($check.Detail)"
		}
		Write-Host $line
	}
	Write-Host ""
	if ($script:Warnings -eq 0) {
		Write-Host "Doctor passed."
	} else {
		Write-Host "Doctor found $script:Warnings warning(s)."
	}
}

if ($Strict -and $script:Warnings -gt 0) {
	exit 1
}
