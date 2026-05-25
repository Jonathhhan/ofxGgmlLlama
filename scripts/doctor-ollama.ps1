param(
    [switch]$Json,
    [switch]$SummaryOnly,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")
Normalize-OfxGgmlWindowsPathEnvironment

$script:Warnings = 0
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$State, [string]$Name, [string]$Detail = "")
    if ($State -eq "WARN") { $script:Warnings++ }
    $checks.Add([ordered]@{ State = $State; Name = $Name; Detail = $Detail })
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
    param([string]$Host = "127.0.0.1", [int]$Port = 11434)
    try {
        $resp = Invoke-WebRequest -Uri "http://$Host`:$Port" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        return ($resp.StatusCode -eq 200)
    } catch { return $false }
}

function Test-OllamaAPI {
    param([string]$Host = "127.0.0.1", [int]$Port = 11434)
    try {
        $resp = Invoke-WebRequest -Uri "http://$Host`:$Port/api/tags" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            $data = $resp.Content | ConvertFrom-Json
            return $data
        }
    } catch {}
    return $null
}

function Get-GPUCaps {
    if (Test-CommandAvailable "nvidia-smi") {
        try {
            $gpu = nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>$null
            return $gpu.Trim()
        } catch {}
    }
    return "unknown"
}

function Test-CommandAvailable {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# Check 1: Ollama installed
$exe = Find-OllamaExe
if ($exe) {
    try {
        $ver = (& $exe --version 2>&1) -split '\s+' | Select-Object -Last 1
        Add-Check "OK" "ollama_installed" "v$ver at $exe"
    } catch {
        Add-Check "OK" "ollama_installed" "at $exe"
    }
} else {
    Add-Check "WARN" "ollama_installed" "not found - run install-ollama.bat"
}

# Check 2: Service running
$svcRunning = Test-OllamaRunning
if ($svcRunning) {
    Add-Check "OK" "ollama_service" "running on :11434"
} else {
    Add-Check "WARN" "ollama_service" "not running - run start-ollama.bat"
}

# Check 3: Available models
$apiData = Test-OllamaAPI
if ($apiData) {
    $modelCount = if ($apiData.models) { $apiData.models.Count } else { 0 }
    Add-Check "OK" "ollama_models" "$modelCount models loaded"
    if ($apiData.models) {
        foreach ($m in $apiData.models) {
            $name = $m.name
            $sizeMB = [math]::Round($m.size / 1MB)
            Add-Check "OK" "model_$name" "${sizeMB} MB"
        }
    }
} else {
    Add-Check "WARN" "ollama_models" "no models or API not reachable"
}

# Check 4: GPU
$gpu = Get-GPUCaps
if ($gpu -ne "unknown") {
    Add-Check "OK" "cuda_gpu" $gpu
} else {
    Add-Check "WARN" "cuda_gpu" "no GPU detected"
}

# Check 5: OpenAI-compatible endpoint
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:11434/v1/models" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    if ($resp.StatusCode -eq 200) {
        Add-Check "OK" "openai_compat" "endpoint ready at http://127.0.0.1:11434/v1"
    } else {
        Add-Check "WARN" "openai_compat" "endpoint returned $($resp.StatusCode)"
    }
} catch {
    Add-Check "WARN" "openai_compat" "endpoint not reachable"
}

# Summary
$okCount = ($checks | Where-Object { $_.State -eq "OK" }).Count
$warnCount = ($checks | Where-Object { $_.State -eq "WARN" }).Count

if ($Json) {
    $result = [ordered]@{
        Checks = $checks
        OkCount = $okCount
        WarnCount = $warnCount
        Status = if ($warnCount -eq 0) { "ready" } elseif ($Strict) { "needs_attention" } else { "partial" }
    }
    if ($SummaryOnly) {
        ($result | ConvertTo-Json -Compress)
    } else {
        $result | ConvertTo-Json -Depth 4
    }
} else {
    Write-Host ""
    foreach ($c in $checks) {
        $icon = if ($c.State -eq "OK") { "✓" } else { "⚠" }
        Write-Host "  $icon $($c.Name): $($c.Detail)"
    }
    Write-Host ""
    Write-Host "  Summary: $okCount OK, $warnCount warnings"
    Write-Host "  Status: $(if ($warnCount -eq 0) { 'ready' } elseif ($Strict) { 'needs_attention' } else { 'partial' })"
}

if ($Strict -and $warnCount -gt 0) { exit 1 }
