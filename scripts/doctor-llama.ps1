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
	$directories = @(
		(Join-Path $addonRoot "ofxGgmlTextExample\bin\data\models"),
		(Join-Path $addonRoot "ofxGgmlTextExample\models"),
		(Join-Path $addonRoot "ofxGgmlChatExample\bin\data\models"),
		(Join-Path $addonRoot "ofxGgmlChatExample\models"),
		(Join-Path $addonRoot "ofxGgmlEmbeddingExample\bin\data\models"),
		(Join-Path $addonRoot "ofxGgmlEmbeddingExample\models"),
		(Join-Path $addonRoot "models"),
		(Join-Path $addonsRoot "models")
	)
	$models = @()
	foreach ($directory in $directories) {
		if (Test-Path -LiteralPath $directory -PathType Container) {
			$models += @(
				Get-ChildItem -LiteralPath $directory -Filter "*.gguf" -File -ErrorAction SilentlyContinue |
					Sort-Object FullName |
					Select-Object -ExpandProperty FullName
			)
		}
	}
	return @($models)
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

$serverStatus = Get-ServerStatus
if ($null -ne $serverStatus) {
	$processCount = @($serverStatus.Processes).Count
	$readyCount = @($serverStatus.Servers | Where-Object { $_.Ready }).Count
	if ($processCount -gt 0 -or $readyCount -gt 0) {
		$checks += New-Check "OK" "llama-server status" "$processCount process(es), $readyCount ready endpoint(s)"
	} else {
		$checks += New-Check "WARN" "llama-server status" "no local process or ready endpoint found"
	}
} else {
	$checks += New-Check "WARN" "llama-server status" "status script failed"
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
		ServerStatus = $serverStatus
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
