param(
    [string]$InstallDir = "",
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

function Resolve-OllamaInstallDir {
    param([string]$Explicit)
    if (![string]::IsNullOrWhiteSpace($Explicit)) {
        return $Explicit
    }
    # Default install locations
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama"),
        (Join-Path $env:ProgramFiles "Ollama"),
        (Join-Path $env:ProgramFiles(x86) "Ollama")
    )
    foreach ($dir in $candidates) {
        if (Test-Path $dir) { return $dir }
    }
    return (Join-Path $env:LOCALAPPDATA "Programs\Ollama")
}

function Test-OllamaInstalled {
    param([string]$InstallDir)
    $exePath = Join-Path $InstallDir "ollama.exe"
    if (Test-Path $exePath) { return $exePath }
    # Also check PATH
    $cmd = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return ""
}

function Get-OllamaVersion {
    param([string]$ExePath)
    try {
        $output = & $ExePath --version 2>&1
        return ($output -split '\s+')[-1]
    } catch {
        return "unknown"
    }
}

function Test-OllamaServiceRunning {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        return ($response.StatusCode -eq 200)
    } catch {
        return $false
    }
}

# Determine install dir
$installDir = Resolve-OllamaInstallDir $InstallDir
$existingExe = Test-OllamaInstalled $installDir

if ($existingExe) {
    $version = Get-OllamaVersion $existingExe
    $serviceRunning = Test-OllamaServiceRunning
    Write-Step "Ollama already installed: $existingExe (v$version)"
    Write-Step "Service running: $serviceRunning"
    
    if ($Json) {
        $result = [ordered]@{
            Installed = $true
            Path = $existingExe
            Version = $version
            ServiceRunning = $serviceRunning
        }
        if ($SummaryOnly) {
            ($result | ConvertTo-Json -Compress)
        } else {
            $result | ConvertTo-Json
        }
        exit 0
    }
    exit 0
}

# Download and install
Write-Step "Ollama not found. Installing to $installDir"
$downloadUrl = "https://github.com/ollama/ollama/releases/latest/download/ollama-windows-amd64.zip"
$zipFile = Join-Path $env:TEMP "ollama-install.zip"

Write-Step "Downloading Ollama..."
try {
    $maxRetries = 3
    $downloaded = $false
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
            $downloaded = $true
            break
        } catch {
            Write-Host "  Download attempt $i/$maxRetries failed: $($_.Exception.Message)"
            if ($i -lt $maxRetries) { Start-Sleep -Seconds 5 }
        }
    }
    if (!$downloaded) {
        throw "Failed to download Ollama after $maxRetries attempts"
    }
} catch {
    $errorMsg = $_.Exception.Message
    if ($Json) {
        $result = [ordered]@{ Installed = $false, Error = $errorMsg }
        ($result | ConvertTo-Json -Compress)
    }
    exit 1
}

# Extract
Write-Step "Extracting..."
if (!(Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}
Expand-Archive -Path $zipFile -DestinationPath $installDir -Force
Remove-Item $zipFile -ErrorAction SilentlyContinue

# Verify
$exePath = Join-Path $installDir "ollama.exe"
if (!(Test-Path $exePath)) {
    throw "Extraction failed - ollama.exe not found at $exePath"
}

# Start service
Write-Step "Starting Ollama service..."
try {
    & $exePath serve 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    $running = Test-OllamaServiceRunning
    Write-Step "Ollama service started: $running"
} catch {
    Write-Warning "Could not auto-start Ollama service. Run manually: $exePath serve"
}

# Add to PATH if not already
$exePathResolved = (Resolve-Path $exePath).Path
$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentUserPath -notlike "*$installDir*") {
    Write-Step "Adding Ollama to user PATH"
    [Environment]::SetEnvironmentVariable("Path", "$currentUserPath;$installDir", "User")
    $env:Path = "$env:Path;$installDir"
}

$version = Get-OllamaVersion $exePath
Write-Step "Ollama installed: $exePath (v$version)"

if ($Json) {
    $result = [ordered]@{
        Installed = $true
        Path = $exePathResolved
        Version = $version
        ServiceRunning = (Test-OllamaServiceRunning)
    }
    if ($SummaryOnly) {
        ($result | ConvertTo-Json -Compress)
    } else {
        $result | ConvertTo-Json
    }
}
