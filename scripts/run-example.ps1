param(
	[Parameter(Position = 0)]
	[ValidateSet("text", "chat", "embedding", "emb")]
	[string]$Example = "text",
	[string]$Backend = $(if ($env:OFXGGML_TEXT_BACKEND) { $env:OFXGGML_TEXT_BACKEND } else { "server" }),
	[string]$ServerUrl = "",
	[string]$ServerModel = "",
	[string]$LlamaCli = $env:OFXGGML_LLAMA_CLI,
	[string]$Model = "",
	[switch]$Build,
	[switch]$NoAutoServer,
	[switch]$DryRun,
	[string]$Configuration = "Release",
	[string]$Platform = "x64"
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
}
$isEmbedding = $canonicalExample -eq "embedding"
$exampleName = switch ($canonicalExample) {
	"text" { "ofxGgmlTextExample" }
	"chat" { "ofxGgmlChatExample" }
	"embedding" { "ofxGgmlEmbeddingExample" }
}
$exampleRoot = Join-Path $addonRoot $exampleName
$exampleExe = Join-Path $exampleRoot "bin\$exampleName.exe"

if ($Build) {
	& (Join-Path $scriptRoot "build-example.ps1") `
		-Example $canonicalExample `
		-Configuration $Configuration `
		-Platform $Platform
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

if ($isEmbedding) {
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
