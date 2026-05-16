param(
	[Parameter(Position = 0)]
	[ValidateSet("text", "chat", "embedding", "emb", "codex")]
	[string]$Example = "text",
	[string]$Backend = $(if ($env:OFXGGML_TEXT_BACKEND) { $env:OFXGGML_TEXT_BACKEND } else { "server" }),
	[string]$ServerUrl = "",
	[string]$ServerModel = "",
	[string]$LlamaCli = $env:OFXGGML_LLAMA_CLI,
	[string]$Model = "",
	[int]$GpuLayers = [int]::MinValue,
	[int]$ContextSize = [int]::MinValue,
	[int]$StartupTimeoutSeconds = [int]::MinValue,
	[string]$Temperature = "",
	[string]$TopP = "",
	[string]$MinP = "",
	[switch]$NoCudaGraphs,
	[switch]$ForceNewServer,
	[switch]$Build,
	[switch]$NoAutoServer,
	[switch]$DryRun,
	[string]$Configuration = "Release",
	[string]$Platform = "x64",
	[int]$Jobs = 1
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Split-Path -Parent $scriptRoot
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")

if ($env:OFXGGML_LAUNCH_DRY_RUN_ONLY -eq "1") {
	$Build = $false
	$DryRun = $true
	$NoAutoServer = $true
}

$canonicalExample = switch ($Example) {
	"text" { "text" }
	"chat" { "chat" }
	"embedding" { "embedding" }
	"emb" { "embedding" }
	"codex" { "codex" }
}
$isEmbedding = $canonicalExample -eq "embedding"
$isCodex = $canonicalExample -eq "codex"
$exampleName = switch ($canonicalExample) {
	"text" { "ofxGgmlTextExample" }
	"chat" { "ofxGgmlChatExample" }
	"embedding" { "ofxGgmlEmbeddingExample" }
	"codex" { "ofxGgmlLlamaCodexLocalExample" }
}
$exampleRoot = Join-Path $addonRoot $exampleName
$exampleExe = Join-Path $exampleRoot "bin\$exampleName.exe"

if ($Build) {
	& (Join-Path $scriptRoot "build-example.ps1") `
		-Example $canonicalExample `
		-Configuration $Configuration `
		-Platform $Platform `
		-Jobs $Jobs
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}

if (!(Test-Path -LiteralPath $exampleExe -PathType Leaf)) {
	if ($DryRun) {
		Write-Warning "$exampleName executable was not found: $exampleExe"
	} else {
		throw "$exampleName executable was not found: $exampleExe. Run scripts\run-example.bat $canonicalExample -Build first."
	}
}

$Model = Normalize-OfxGgmlPathText $Model
$ServerUrl = Normalize-OfxGgmlPathText $ServerUrl
$ServerModel = Normalize-OfxGgmlPathText $ServerModel
$Temperature = Normalize-OfxGgmlPathText $Temperature
$TopP = Normalize-OfxGgmlPathText $TopP
$MinP = Normalize-OfxGgmlPathText $MinP

if ($isCodex) {
	if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
		$ServerUrl = if ($env:OFXGGML_CODEX_BASE_URL) { $env:OFXGGML_CODEX_BASE_URL } else { "http://127.0.0.1:8001/v1" }
	}
	if ([string]::IsNullOrWhiteSpace($ServerModel)) {
		$ServerModel = if ($env:OFXGGML_CODEX_MODEL) { $env:OFXGGML_CODEX_MODEL } else { "unsloth/GLM-4.7-Flash" }
	}
	if ($GpuLayers -eq [int]::MinValue) {
		$GpuLayers = if ($env:OFXGGML_CODEX_GPU_LAYERS) { [int]$env:OFXGGML_CODEX_GPU_LAYERS } else { 999 }
	}
	if ($ContextSize -eq [int]::MinValue) {
		$ContextSize = if ($env:OFXGGML_CODEX_CONTEXT_SIZE) { [int]$env:OFXGGML_CODEX_CONTEXT_SIZE } else { 131072 }
	}
	if ($StartupTimeoutSeconds -eq [int]::MinValue) {
		$StartupTimeoutSeconds = if ($env:OFXGGML_CODEX_STARTUP_TIMEOUT) { [int]$env:OFXGGML_CODEX_STARTUP_TIMEOUT } else { 300 }
	}
	if ([string]::IsNullOrWhiteSpace($Temperature)) {
		$Temperature = if ($env:OFXGGML_CODEX_TEMP) { $env:OFXGGML_CODEX_TEMP } else { "1.0" }
	}
	if ([string]::IsNullOrWhiteSpace($TopP)) {
		$TopP = if ($env:OFXGGML_CODEX_TOP_P) { $env:OFXGGML_CODEX_TOP_P } else { "0.95" }
	}
	if ([string]::IsNullOrWhiteSpace($MinP)) {
		$MinP = if ($env:OFXGGML_CODEX_MIN_P) { $env:OFXGGML_CODEX_MIN_P } else { "0.01" }
	}
	$codexNoCudaGraphs = $NoCudaGraphs -or $env:OFXGGML_CODEX_NO_CUDA_GRAPHS -ne "0"
	if ([string]::IsNullOrWhiteSpace($Model)) {
		$Model = if ($env:OFXGGML_TEXT_MODEL) { $env:OFXGGML_TEXT_MODEL } else { "" }
	}
	if ([string]::IsNullOrWhiteSpace($Model)) {
		$Model = Find-OfxGgmlFirstModel (Get-OfxGgmlModelSearchDirectories `
			-AddonRoot $addonRoot `
			-ExampleRoot $exampleRoot `
			-ExtraExampleNames @("ofxGgmlTextExample", "ofxGgmlChatExample"))
	}
	$env:OFXGGML_CODEX_BASE_URL = $ServerUrl
	$env:OFXGGML_CODEX_MODEL = $ServerModel
	$env:OFXGGML_CODEX_GPU_LAYERS = $GpuLayers.ToString()
	$env:OFXGGML_CODEX_CONTEXT_SIZE = $ContextSize.ToString()
	$env:OFXGGML_CODEX_TEMP = $Temperature
	$env:OFXGGML_CODEX_TOP_P = $TopP
	$env:OFXGGML_CODEX_MIN_P = $MinP
	$env:OFXGGML_CODEX_NO_CUDA_GRAPHS = if ($codexNoCudaGraphs) { "1" } else { "0" }
	if (![string]::IsNullOrWhiteSpace($Model)) {
		$env:OFXGGML_TEXT_MODEL = $Model
		Write-OfxGgmlStep "Using text model: $Model"
	} else {
		Write-Warning "No GGUF model found. The example can still connect to an already-running server."
	}
	Write-OfxGgmlStep "Using Codex local endpoint: $ServerUrl"
	Write-OfxGgmlStep "Using Codex model alias: $ServerModel"
	Write-OfxGgmlStep "Using Codex server options: ngl=$GpuLayers ctx=$ContextSize temp=$Temperature top_p=$TopP min_p=$MinP cudaGraph=$(if ($codexNoCudaGraphs) { 'off' } else { 'on' })"
	if ($DryRun) {
		Write-OfxGgmlStep "Executable: $exampleExe"
		Write-OfxGgmlStep "Auto server: $(if ($NoAutoServer) { 'off' } else { 'on' })"
		return
	}
	Start-OfxGgmlBundledLlamaServerIfNeeded `
		-ScriptRoot $scriptRoot `
		-AddonRoot $addonRoot `
		-ServerUrl (Get-OfxGgmlServerRootUrl $ServerUrl) `
		-Model $Model `
		-LogDir (Join-Path $addonRoot "build\llama-codex-server") `
		-MissingModelWarning "No GGUF model found. Put one under addons\models or pass -Model C:\path\to\model.gguf." `
		-StartMessage "Codex llama-server is not responding; starting bundled server" `
		-StartupTimeoutSeconds $StartupTimeoutSeconds `
		-Alias $ServerModel `
		-GpuLayers $GpuLayers `
		-ContextSize $ContextSize `
		-Temperature $Temperature `
		-TopP $TopP `
		-MinP $MinP `
		-NoCudaGraphs:$codexNoCudaGraphs `
		-ForceNew:$ForceNewServer `
		-NoAutoServer:$NoAutoServer
} elseif ($isEmbedding) {
	if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
		$ServerUrl = if ($env:OFXGGML_EMBEDDING_SERVER_URL) { $env:OFXGGML_EMBEDDING_SERVER_URL } else { "http://127.0.0.1:8081" }
	}
	if ([string]::IsNullOrWhiteSpace($ServerModel)) {
		$ServerModel = $env:OFXGGML_EMBEDDING_SERVER_MODEL
	}
	if ([string]::IsNullOrWhiteSpace($Model)) {
		$Model = if ($env:OFXGGML_EMBEDDING_MODEL) { $env:OFXGGML_EMBEDDING_MODEL } elseif ($env:OFXGGML_TEXT_MODEL) { $env:OFXGGML_TEXT_MODEL } else { "" }
	}
	if ([string]::IsNullOrWhiteSpace($Model)) {
		$Model = Find-OfxGgmlFirstModel (Get-OfxGgmlModelSearchDirectories `
			-AddonRoot $addonRoot `
			-ExampleRoot $exampleRoot `
			-ExtraExampleNames @("ofxGgmlTextExample", "ofxGgmlChatExample"))
	}

	$env:OFXGGML_EMBEDDING_SERVER_URL = $ServerUrl
	if (![string]::IsNullOrWhiteSpace($ServerModel)) {
		$env:OFXGGML_EMBEDDING_SERVER_MODEL = $ServerModel
	}
	if (![string]::IsNullOrWhiteSpace($Model)) {
		$env:OFXGGML_EMBEDDING_MODEL = $Model
		Write-OfxGgmlStep "Using embedding model: $Model"
	} else {
		Write-Warning "No GGUF model found. The example can still connect to an already-running server."
	}

	Write-OfxGgmlStep "Using embedding server: $ServerUrl"
	if (![string]::IsNullOrWhiteSpace($ServerModel)) {
		Write-OfxGgmlStep "Using server model: $ServerModel"
	}
	if ($DryRun) {
		Write-OfxGgmlStep "Executable: $exampleExe"
		Write-OfxGgmlStep "Auto server: $(if ($NoAutoServer) { 'off' } else { 'on' })"
		return
	}

	Start-OfxGgmlBundledLlamaServerIfNeeded `
		-ScriptRoot $scriptRoot `
		-AddonRoot $addonRoot `
		-ServerUrl $ServerUrl `
		-Model $Model `
		-LogDir (Join-Path $addonRoot "build\llama-embedding-server") `
		-MissingModelWarning "No GGUF model found. Put an embedding GGUF under addons\models or pass -Model C:\path\to\embedding-model.gguf." `
		-StartMessage "embedding llama-server is not responding; starting bundled server" `
		-StartupTimeoutSeconds 180 `
		-NoAutoServer:$NoAutoServer `
		-Embeddings
} else {
	$LlamaCli = Normalize-OfxGgmlPathText $LlamaCli
	$Backend = Normalize-OfxGgmlPathText $Backend
	if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
		$ServerUrl = if ($env:OFXGGML_TEXT_SERVER_URL) { $env:OFXGGML_TEXT_SERVER_URL } else { "http://127.0.0.1:8080" }
	}
	if ([string]::IsNullOrWhiteSpace($ServerModel)) {
		$ServerModel = $env:OFXGGML_TEXT_SERVER_MODEL
	}
	if ([string]::IsNullOrWhiteSpace($Model)) {
		$Model = $env:OFXGGML_TEXT_MODEL
	}
	if ([string]::IsNullOrWhiteSpace($Backend)) {
		$Backend = "server"
	}
	if ($Backend -ieq "cli" -and [string]::IsNullOrWhiteSpace($LlamaCli)) {
		$LlamaCli = Find-OfxGgmlLlamaCli -AddonRoot $addonRoot -ExampleRoot $exampleRoot
	}
	if ([string]::IsNullOrWhiteSpace($Model)) {
		$Model = Find-OfxGgmlFirstModel (Get-OfxGgmlModelSearchDirectories `
			-AddonRoot $addonRoot `
			-ExampleRoot $exampleRoot)
	}

	if ($Backend -ieq "server") {
		$env:OFXGGML_TEXT_BACKEND = "server"
		$env:OFXGGML_TEXT_SERVER_URL = $ServerUrl
		if (![string]::IsNullOrWhiteSpace($ServerModel)) {
			$env:OFXGGML_TEXT_SERVER_MODEL = $ServerModel
		}
		Write-OfxGgmlStep "Using llama-server: $ServerUrl"
		if (![string]::IsNullOrWhiteSpace($ServerModel)) {
			Write-OfxGgmlStep "Using server model: $ServerModel"
		}
		if (!$DryRun) {
			Start-OfxGgmlBundledLlamaServerIfNeeded `
				-ScriptRoot $scriptRoot `
				-AddonRoot $addonRoot `
				-ServerUrl $ServerUrl `
				-Model $Model `
				-LogDir (Join-Path $addonRoot "build\llama-server") `
				-MissingModelWarning "No GGUF model found. Put one under addons\models or pass -Model C:\path\to\model.gguf." `
				-StartMessage "llama-server is not responding; starting bundled server" `
				-StartupTimeoutSeconds 120 `
				-NoAutoServer:$NoAutoServer
		}
	} elseif (![string]::IsNullOrWhiteSpace($LlamaCli)) {
		$env:OFXGGML_TEXT_BACKEND = "cli"
		$env:OFXGGML_LLAMA_CLI = $LlamaCli
		Write-OfxGgmlStep "Using llama.cpp CLI: $LlamaCli"
	} else {
		Write-Warning "No llama.cpp CLI found. The example will show setup instructions."
	}

	if (![string]::IsNullOrWhiteSpace($Model)) {
		$env:OFXGGML_TEXT_MODEL = $Model
		Write-OfxGgmlStep "Using text model: $Model"
	} elseif ($Backend -ieq "cli") {
		Write-Warning "No GGUF model found. The example will show setup instructions."
	}

	if ($DryRun) {
		Write-OfxGgmlStep "Executable: $exampleExe"
		Write-OfxGgmlStep "Auto server: $(if ($NoAutoServer) { 'off' } else { 'on' })"
		return
	}
}

Write-OfxGgmlStep "Starting $exampleName"
& $exampleExe
exit $LASTEXITCODE
