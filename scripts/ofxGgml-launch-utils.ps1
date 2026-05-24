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

function Find-OfxGgmlFirstModel {
	param([string[]]$Directories)
	foreach ($directory in $Directories) {
		if (!(Test-Path -LiteralPath $directory -PathType Container)) {
			continue
		}
		$model = Get-ChildItem -LiteralPath $directory -Filter "*.gguf" -File -ErrorAction SilentlyContinue |
			Sort-Object Name |
			Select-Object -First 1
		if ($model) {
			return $model.FullName
		}
	}
	return ""
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

# ── Ollama backend helpers ──

function Find-OfxGgmlOllama {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
        (Join-Path $env:ProgramFiles "Ollama\ollama.exe")
    )
    $cmd = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($cmd) { $candidates.Insert(0, $cmd.Source) }
    return Resolve-OfxGgmlFirstFile $candidates
}

function Test-OfxGgmlOllamaRunning {
    param([string]$Host = "127.0.0.1", [int]$Port = 11434)
    return (Test-OfxGgmlLocalServerUrl "http://$Host`:$Port")
}

function Get-OfxGgmlOllamaEndpoint {
    param([string]$Host = "127.0.0.1", [int]$Port = 11434)
    return "http://$Host`:$Port/v1"
}

function Start-OfxGgmlOllamaIfNeeded {
    param(
        [string]$Model = "qwen2.5-coder:7b",
        [string]$HostName = "127.0.0.1",
        [int]$Port = 11434,
        [switch]$Pull,
        [switch]$ForceNew,
        [switch]$NoAutoServer
    )

    if ($NoAutoServer -or (!$ForceNew -and (Test-OfxGgmlOllamaRunning -Host $HostName -Port $Port))) {
        return
    }

    $ollamaExe = Find-OfxGgmlOllama
    if (!$ollamaExe) {
        Write-Warning "Ollama not found. Run scripts\install-ollama.bat first."
        return
    }

    Write-OfxGgmlStep "Starting Ollama service..."
    Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WindowStyle Hidden

    # Wait for service
    $timeout = 30
    $started = $false
    for ($i = 0; $i -lt $timeout; $i++) {
        Start-Sleep -Seconds 1
        if (Test-OfxGgmlOllamaRunning -Host $HostName -Port $Port) {
            $started = $true
            break
        }
    }
    if (!$started) {
        Write-Warning "Ollama service did not start within ${timeout}s"
        return
    }

    # Pull model if needed
    $needsPull = $Pull
    if (!$needsPull) {
        try {
            $out = & $ollamaExe list 2>&1 | Out-String
            if ($out -notmatch [regex]::Escape($Model)) {
                $needsPull = $true
            }
        } catch {}
    }

    if ($needsPull) {
        Write-OfxGgmlStep "Pulling model: $Model"
        & $ollamaExe pull $Model 2>&1 | Out-Host
    }

    $endpoint = Get-OfxGgmlOllamaEndpoint -Host $HostName -Port $Port
    Write-OfxGgmlStep "Ollama ready: $endpoint (model: $Model)"
}

# ── Backend selector: pick best available local backend ──

function Get-OfxGgmlLocalBackend {
    param(
        [string]$Preferred = "",  # "ollama", "llama-server", or "" for auto
        [string]$ServerUrl = ""
    )

    $ollamaExe = Find-OfxGgmlOllama
    $ollamaRunning = Test-OfxGgmlOllamaRunning
    $llamaRunning = if ($ServerUrl) { Test-OfxGgmlLocalServerUrl $ServerUrl } else { $false }

    switch ($Preferred) {
        "ollama" {
            if ($ollamaRunning) {
                return [ordered]@{ Type = "ollama"; Endpoint = Get-OfxGgmlOllamaEndpoint; Path = $ollamaExe }
            }
            return $null
        }
        "llama-server" {
            if ($llamaRunning -and $ServerUrl) {
                return [ordered]@{ Type = "llama-server"; Endpoint = $ServerUrl }
            }
            return $null
        }
        default {
            # Auto: prefer ollama if running, then llama-server
            if ($ollamaRunning) {
                return [ordered]@{ Type = "ollama"; Endpoint = Get-OfxGgmlOllamaEndpoint; Path = $ollamaExe }
            }
            if ($llamaRunning -and $ServerUrl) {
                return [ordered]@{ Type = "llama-server"; Endpoint = $ServerUrl }
            }
            return $null
        }
    }
}
