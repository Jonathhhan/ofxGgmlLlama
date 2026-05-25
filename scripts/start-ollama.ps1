param(
    [string]$Model = "qwen2.5-coder:7b",
    [string]$HostName = "127.0.0.1",
    [int]$Port = 11434,
    [switch]$Pull,
    [switch]$Detached,
    [switch]$Json,
    [switch]$SummaryOnly
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")
Normalize-OfxGgmlWindowsPathEnvironment

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Find-OllamaExe {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
        (Join-Path $env:ProgramFiles "Ollama\ollama.exe")
    )
    $cmd = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($cmd) { $candidates.Insert(0, $cmd.Source) }
    return Resolve-OfxGgmlFirstFile $candidates
}

function Test-OllamaRunning {
    try {
        $resp = Invoke-WebRequest -Uri "http://$HostName`:$Port" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        return ($resp.StatusCode -eq 200)
    } catch { return $false }
}

function Test-OllamaModel {
    param([string]$Exe, [string]$ModelName)
    try {
        $out = & $Exe list 2>&1 | Out-String
        return ($out -match [regex]::Escape($ModelName))
    } catch { return $false }
}

$exe = Find-OllamaExe
if (!$exe) {
    $msg = "Ollama not found. Run scripts\install-ollama.bat first."
    if ($Json) {
        ([ordered]@{ Error = $msg } | ConvertTo-Json -Compress)
    } else {
        Write-Error $msg
    }
    exit 1
}

Write-Step "Ollama: $exe"

# Check if service is running
$running = Test-OllamaRunning
if (!$running) {
    Write-Step "Starting Ollama service..."
    if ($Detached) {
        Start-Process -FilePath $exe -ArgumentList "serve" -WindowStyle Hidden
        # Wait for service to be ready
        $timeout = 30
        $started = $false
        for ($i = 0; $i -lt $timeout; $i++) {
            Start-Sleep -Seconds 1
            if (Test-OllamaRunning) {
                $started = $true
                break
            }
        }
        if (!$started) {
            $msg = "Ollama service did not start within ${timeout}s"
            if ($Json) { ([ordered]@{ Error = $msg } | ConvertTo-Json -Compress) } else { Write-Error $msg }
            exit 1
        }
    } else {
        & $exe serve
        exit $LASTEXITCODE
    }
    Write-Step "Ollama service running"
}

# Check/pull model
$modelHasModel = Test-OllamaModel -Exe $exe -ModelName $Model
if ($Pull -or !$modelHasModel) {
    Write-Step "Pulling model: $Model"
    $pullOut = & $exe pull $Model 2>&1 | Out-String
    Write-Host $pullOut
} else {
    Write-Step "Model $Model already available"
}

# The OpenAI-compatible endpoint for ofxGgml clients
$openaiUrl = "http://$HostName`:$Port/v1"
Write-Step "OpenAI-compatible API: $openaiUrl"
Write-Step "Set OFXGGML_TEXT_SERVER_URL=$openaiUrl for ofxGgmlLlama clients"
Write-Step "Set OFXGGML_CODEX_BASE_URL=$openaiUrl for local codex"

if ($Json) {
    $result = [ordered]@{
        OllamaPath = $exe
        Model = $Model
        ServiceRunning = $true
        OpenAIEndpoint = $openaiUrl
        EnvVars = @{
            OFXGGML_TEXT_SERVER_URL = $openaiUrl
            OFXGGML_CODEX_BASE_URL = $openaiUrl
        }
    }
    if ($SummaryOnly) {
        ($result | ConvertTo-Json -Compress)
    } else {
        $result | ConvertTo-Json
    }
}
