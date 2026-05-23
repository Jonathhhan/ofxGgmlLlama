param(
	[string]$Configuration = "Release",
	[string]$Platform = "x64"
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Invoke-DryRun {
	param(
		[string]$Label,
		[string]$Script,
		[hashtable]$Parameters
	)
	Write-Step $Label
	$previousDryRunOnly = $env:OFXGGML_LAUNCH_DRY_RUN_ONLY
	$previousTextBackend = $env:OFXGGML_TEXT_BACKEND
	$previousTextServerUrl = $env:OFXGGML_TEXT_SERVER_URL
	$previousTextServerModel = $env:OFXGGML_TEXT_SERVER_MODEL
	$previousTextModel = $env:OFXGGML_TEXT_MODEL
	$previousLlamaCli = $env:OFXGGML_LLAMA_CLI
	$previousLlamaEmbedding = $env:OFXGGML_LLAMA_EMBEDDING
	$previousEmbeddingModel = $env:OFXGGML_EMBEDDING_MODEL
	$previousEmbeddingServerUrl = $env:OFXGGML_EMBEDDING_SERVER_URL
	$previousEmbeddingServerModel = $env:OFXGGML_EMBEDDING_SERVER_MODEL
	$previousCodexBaseUrl = $env:OFXGGML_CODEX_BASE_URL
	$previousCodexModel = $env:OFXGGML_CODEX_MODEL
	$previousCodexAgentThreads = $env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS
	$previousCodexAgentDepth = $env:OFXGGML_CODEX_AGENT_MAX_DEPTH
	$previousCodexAgentMinWait = $env:OFXGGML_CODEX_AGENT_MIN_WAIT_MS
	$previousCodexAgentMaxWait = $env:OFXGGML_CODEX_AGENT_MAX_WAIT_MS
	$previousCodexAgentDefaultWait = $env:OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS
	$codexEnvNames = @(
		"OFXGGML_CODEX_BASE_URL",
		"OFXGGML_CODEX_MODEL",
		"OFXGGML_CODEX_PRESET",
		"OFXGGML_CODEX_GPU_LAYERS",
		"OFXGGML_CODEX_CONTEXT_SIZE",
		"OFXGGML_CODEX_PARALLEL",
		"OFXGGML_CODEX_BATCH_SIZE",
		"OFXGGML_CODEX_UBATCH_SIZE",
		"OFXGGML_CODEX_THREADS",
		"OFXGGML_CODEX_THREADS_BATCH",
		"OFXGGML_CODEX_THREADS_HTTP",
		"OFXGGML_CODEX_CACHE_REUSE",
		"OFXGGML_CODEX_KV_CACHE_KEY_TYPE",
		"OFXGGML_CODEX_KV_CACHE_VALUE_TYPE",
		"OFXGGML_CODEX_SPEC_TYPE",
		"OFXGGML_CODEX_FLASH_ATTN",
		"OFXGGML_CODEX_MODEL_CONTEXT_WINDOW",
		"OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT",
		"OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT",
		"OFXGGML_CODEX_AGENT_MAX_AGENTS",
		"OFXGGML_CODEX_AGENT_MAX_THREADS",
		"OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS",
		"OFXGGML_CODEX_AGENT_MAX_DEPTH",
		"OFXGGML_CODEX_AGENT_MIN_WAIT_MS",
		"OFXGGML_CODEX_AGENT_MAX_WAIT_MS",
		"OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS",
		"OFXGGML_CODEX_STARTUP_TIMEOUT",
		"OFXGGML_CODEX_TEMP",
		"OFXGGML_CODEX_TOP_P",
		"OFXGGML_CODEX_MIN_P",
		"OFXGGML_CODEX_CHAT_TEMPLATE_KWARGS",
		"OFXGGML_CODEX_REASONING",
		"OFXGGML_CODEX_REASONING_BUDGET",
		"OFXGGML_CODEX_NO_CUDA_GRAPHS",
		"OFXGGML_CODEX_SKIP_CHAT_PARSING")
	$previousCodexEnv = @{}
	foreach ($name in $codexEnvNames) {
		$previousCodexEnv[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
	}
	$env:OFXGGML_LAUNCH_DRY_RUN_ONLY = "1"
	try {
		$output = & $Script @Parameters *>&1 | ForEach-Object { $_.ToString() }
		if (!$?) {
			throw "$Label failed."
		}
	} finally {
		if ($null -eq $previousDryRunOnly) {
			Remove-Item Env:\OFXGGML_LAUNCH_DRY_RUN_ONLY -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_LAUNCH_DRY_RUN_ONLY = $previousDryRunOnly
		}
		if ($null -eq $previousTextBackend) {
			Remove-Item Env:\OFXGGML_TEXT_BACKEND -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_TEXT_BACKEND = $previousTextBackend
		}
		if ($null -eq $previousTextServerUrl) {
			Remove-Item Env:\OFXGGML_TEXT_SERVER_URL -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_TEXT_SERVER_URL = $previousTextServerUrl
		}
		if ($null -eq $previousTextServerModel) {
			Remove-Item Env:\OFXGGML_TEXT_SERVER_MODEL -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_TEXT_SERVER_MODEL = $previousTextServerModel
		}
		if ($null -eq $previousTextModel) {
			Remove-Item Env:\OFXGGML_TEXT_MODEL -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_TEXT_MODEL = $previousTextModel
		}
		if ($null -eq $previousLlamaCli) {
			Remove-Item Env:\OFXGGML_LLAMA_CLI -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_LLAMA_CLI = $previousLlamaCli
		}
		if ($null -eq $previousLlamaEmbedding) {
			Remove-Item Env:\OFXGGML_LLAMA_EMBEDDING -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_LLAMA_EMBEDDING = $previousLlamaEmbedding
		}
		if ($null -eq $previousEmbeddingModel) {
			Remove-Item Env:\OFXGGML_EMBEDDING_MODEL -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_EMBEDDING_MODEL = $previousEmbeddingModel
		}
		if ($null -eq $previousEmbeddingServerUrl) {
			Remove-Item Env:\OFXGGML_EMBEDDING_SERVER_URL -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_EMBEDDING_SERVER_URL = $previousEmbeddingServerUrl
		}
		if ($null -eq $previousEmbeddingServerModel) {
			Remove-Item Env:\OFXGGML_EMBEDDING_SERVER_MODEL -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_EMBEDDING_SERVER_MODEL = $previousEmbeddingServerModel
		}
		if ($null -eq $previousCodexBaseUrl) {
			Remove-Item Env:\OFXGGML_CODEX_BASE_URL -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_CODEX_BASE_URL = $previousCodexBaseUrl
		}
		if ($null -eq $previousCodexModel) {
			Remove-Item Env:\OFXGGML_CODEX_MODEL -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_CODEX_MODEL = $previousCodexModel
		}
		if ($null -eq $previousCodexAgentThreads) {
			Remove-Item Env:\OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS = $previousCodexAgentThreads
		}
		if ($null -eq $previousCodexAgentDepth) {
			Remove-Item Env:\OFXGGML_CODEX_AGENT_MAX_DEPTH -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_CODEX_AGENT_MAX_DEPTH = $previousCodexAgentDepth
		}
		if ($null -eq $previousCodexAgentMinWait) {
			Remove-Item Env:\OFXGGML_CODEX_AGENT_MIN_WAIT_MS -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_CODEX_AGENT_MIN_WAIT_MS = $previousCodexAgentMinWait
		}
		if ($null -eq $previousCodexAgentMaxWait) {
			Remove-Item Env:\OFXGGML_CODEX_AGENT_MAX_WAIT_MS -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_CODEX_AGENT_MAX_WAIT_MS = $previousCodexAgentMaxWait
		}
		if ($null -eq $previousCodexAgentDefaultWait) {
			Remove-Item Env:\OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS -ErrorAction SilentlyContinue
		} else {
			$env:OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS = $previousCodexAgentDefaultWait
		}
		foreach ($name in $codexEnvNames) {
			if ($null -eq $previousCodexEnv[$name]) {
				Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
			} else {
				[Environment]::SetEnvironmentVariable($name, [string]$previousCodexEnv[$name], "Process")
			}
		}
	}
	return @($output)
}

function Assert-Contains {
	param(
		[string[]]$Output,
		[string]$Needle,
		[string]$Label
	)
	$text = $Output -join "`n"
	if ($text -notlike "*$Needle*") {
		throw "$Label did not contain expected text: $Needle`n$text"
	}
}

function Assert-NotContains {
	param(
		[string[]]$Output,
		[string]$Needle,
		[string]$Label
	)
	$text = $Output -join "`n"
	if ($text -like "*$Needle*") {
		throw "$Label contained unexpected text: $Needle`n$text"
	}
}

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$scratchDir = Join-Path $addonRoot "build\launch-dry-run-smoke"
New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null

$modelPath = Join-Path $scratchDir "dry-run-model.gguf"
$serverExe = Join-Path $scratchDir "llama-server.exe"
$llamaCliExe = Join-Path $scratchDir "llama-cli.exe"
$llamaEmbeddingExe = Join-Path $scratchDir "llama-embedding.exe"
if (!(Test-Path -LiteralPath $modelPath -PathType Leaf)) {
	New-Item -ItemType File -Path $modelPath | Out-Null
}
if (!(Test-Path -LiteralPath $serverExe -PathType Leaf)) {
	New-Item -ItemType File -Path $serverExe | Out-Null
}
if (!(Test-Path -LiteralPath $llamaCliExe -PathType Leaf)) {
	New-Item -ItemType File -Path $llamaCliExe | Out-Null
}
if (!(Test-Path -LiteralPath $llamaEmbeddingExe -PathType Leaf)) {
	New-Item -ItemType File -Path $llamaEmbeddingExe | Out-Null
}

$textOutput = Invoke-DryRun `
	-Label "Text example dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "text"
		DryRun = $true
		NoAutoServer = $true
		ServerUrl = "http://127.0.0.1:9080"
		ServerModel = "dry-text-model"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $textOutput "Using llama-server: http://127.0.0.1:9080" "Text dry-run"
Assert-Contains $textOutput "Using server model: dry-text-model" "Text dry-run"
Assert-Contains $textOutput "Using text model: $modelPath" "Text dry-run"
Assert-Contains $textOutput "Executable:" "Text dry-run"
Assert-Contains $textOutput "Auto server: off" "Text dry-run"
Assert-NotContains $textOutput "Starting ofxGgmlTextExample" "Text dry-run"

$textCliOutput = Invoke-DryRun `
	-Label "Text example CLI dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "text"
		DryRun = $true
		Backend = "cli"
		LlamaCli = $llamaCliExe
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $textCliOutput "Using llama.cpp CLI: $llamaCliExe" "Text CLI dry-run"
Assert-Contains $textCliOutput "Using text model: $modelPath" "Text CLI dry-run"
Assert-Contains $textCliOutput "Executable:" "Text CLI dry-run"
Assert-Contains $textCliOutput "Auto server: off" "Text CLI dry-run"
Assert-NotContains $textCliOutput "Using llama-server:" "Text CLI dry-run"
Assert-NotContains $textCliOutput "Starting ofxGgmlTextExample" "Text CLI dry-run"

$chatOutput = Invoke-DryRun `
	-Label "Chat example dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "chat"
		DryRun = $true
		NoAutoServer = $true
		ServerUrl = "http://127.0.0.1:9080"
		ServerModel = "dry-chat-model"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $chatOutput "Using llama-server: http://127.0.0.1:9080" "Chat dry-run"
Assert-Contains $chatOutput "Using server model: dry-chat-model" "Chat dry-run"
Assert-Contains $chatOutput "Using text model: $modelPath" "Chat dry-run"
Assert-Contains $chatOutput "Executable:" "Chat dry-run"
Assert-Contains $chatOutput "Auto server: off" "Chat dry-run"
Assert-NotContains $chatOutput "Starting ofxGgmlChatExample" "Chat dry-run"

$chatCliOutput = Invoke-DryRun `
	-Label "Chat example CLI dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "chat"
		DryRun = $true
		Backend = "cli"
		LlamaCli = $llamaCliExe
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $chatCliOutput "Using llama.cpp CLI: $llamaCliExe" "Chat CLI dry-run"
Assert-Contains $chatCliOutput "Using text model: $modelPath" "Chat CLI dry-run"
Assert-Contains $chatCliOutput "Executable:" "Chat CLI dry-run"
Assert-Contains $chatCliOutput "Auto server: off" "Chat CLI dry-run"
Assert-NotContains $chatCliOutput "Using llama-server:" "Chat CLI dry-run"
Assert-NotContains $chatCliOutput "Starting ofxGgmlChatExample" "Chat CLI dry-run"

$embeddingOutput = Invoke-DryRun `
	-Label "Embedding example dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "embedding"
		DryRun = $true
		NoAutoServer = $true
		ServerUrl = "http://127.0.0.1:9081"
		ServerModel = "dry-embedding-model"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $embeddingOutput "Using embedding server: http://127.0.0.1:9081" "Embedding dry-run"
Assert-Contains $embeddingOutput "Using server model: dry-embedding-model" "Embedding dry-run"
Assert-Contains $embeddingOutput "Using embedding model: $modelPath" "Embedding dry-run"
Assert-Contains $embeddingOutput "Executable:" "Embedding dry-run"
Assert-Contains $embeddingOutput "Auto server: off" "Embedding dry-run"
Assert-NotContains $embeddingOutput "Starting ofxGgmlEmbeddingExample" "Embedding dry-run"

$codexOutput = Invoke-DryRun `
	-Label "Codex local example dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "codex"
		DryRun = $true
		ServerUrl = "http://127.0.0.1:9001/v1"
		ServerModel = "dry-codex-model"
		Model = $modelPath
		GpuLayers = 77
		ContextSize = 32768
		Temperature = "1.1"
		TopP = "0.91"
		MinP = "0.03"
		SpecType = "ngram-cache"
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $codexOutput "Using Codex local endpoint: http://127.0.0.1:9001/v1" "Codex local dry-run"
Assert-Contains $codexOutput "Using Codex model alias: dry-codex-model" "Codex local dry-run"
Assert-Contains $codexOutput "Using text model: $modelPath" "Codex local dry-run"
Assert-Contains $codexOutput "Using Codex preset: Quality coding" "Codex local dry-run"
Assert-Contains $codexOutput "Using Codex server options: ngl=77 ctx=32768 parallel=1 batch=3072 ubatch=768 threads=auto batchThreads=auto httpThreads=auto cacheReuse=256 ctk=default ctv=default spec=ngram-cache flashAttn=on temp=1.1 top_p=0.91 min_p=0.03 reasoning=off thinkBudget=0 cudaGraph=on skipChatParsing=off" "Codex local dry-run"
Assert-Contains $codexOutput "Using Codex config defaults: model_context_window=65536 auto_compact=50000 tool_output=8000" "Codex local dry-run"
Assert-Contains $codexOutput "Using Codex agent settings: max_threads=auto max_depth=auto wait_ms=2500/30000/180000" "Codex local dry-run"
Assert-Contains $codexOutput "Executable:" "Codex local dry-run"
Assert-Contains $codexOutput "Auto server: off" "Codex local dry-run"
Assert-NotContains $codexOutput "Starting ofxGgmlLlamaCodexLocalExample" "Codex local dry-run"

$codexDerivedAliasOutput = Invoke-DryRun `
	-Label "Codex local derived alias dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "codex"
		DryRun = $true
		ServerUrl = "http://127.0.0.1:9001/v1"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
$expectedDerivedAlias = "local/" + [System.IO.Path]::GetFileNameWithoutExtension($modelPath)
Assert-Contains $codexDerivedAliasOutput "Using Codex model alias: $expectedDerivedAlias" "Codex local derived alias dry-run"
Assert-Contains $codexDerivedAliasOutput "ngl=all" "Codex local derived alias dry-run"
Assert-NotContains $codexDerivedAliasOutput "unsloth/GLM-4.7-Flash" "Codex local derived alias dry-run"

$env:OFXGGML_CODEX_MODEL = "local/GLM-4.7-Flash-UD-Q4_K_XL"
$codexStaleEnvAliasOutput = Invoke-DryRun `
	-Label "Codex local stale env alias dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "codex"
		DryRun = $true
		ServerUrl = "http://127.0.0.1:9001/v1"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $codexStaleEnvAliasOutput "Using Codex model alias: $expectedDerivedAlias" "Codex local stale env alias dry-run"
Assert-NotContains $codexStaleEnvAliasOutput "Using Codex model alias: local/GLM-4.7-Flash-UD-Q4_K_XL" "Codex local stale env alias dry-run"
Remove-Item Env:\OFXGGML_CODEX_MODEL -ErrorAction SilentlyContinue
$codexFastPresetOutput = Invoke-DryRun `
	-Label "Codex local fast preset dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "codex"
		DryRun = $true
		CodexPreset = "fast"
		ServerUrl = "http://127.0.0.1:9001/v1"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $codexFastPresetOutput "Using Codex preset: Fast coding" "Codex local fast preset dry-run"
Assert-Contains $codexFastPresetOutput "ctx=32768 parallel=1 batch=4096 ubatch=1024" "Codex local fast preset dry-run"
Assert-Contains $codexFastPresetOutput "cacheReuse=256" "Codex local fast preset dry-run"
Assert-Contains $codexFastPresetOutput "model_context_window=32768 auto_compact=24000 tool_output=5000" "Codex local fast preset dry-run"

$codexFullContextPresetOutput = Invoke-DryRun `
	-Label "Codex local full-context preset dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "codex"
		DryRun = $true
		CodexPreset = "fullctx"
		ServerUrl = "http://127.0.0.1:9001/v1"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $codexFullContextPresetOutput "Using Codex preset: Full context Q8" "Codex local full-context preset dry-run"
Assert-Contains $codexFullContextPresetOutput "ctx=0 parallel=1 batch=2048 ubatch=512" "Codex local full-context preset dry-run"
Assert-Contains $codexFullContextPresetOutput "cacheReuse=512 ctk=q8_0 ctv=q8_0" "Codex local full-context preset dry-run"
Assert-Contains $codexFullContextPresetOutput "model_context_window=131072 auto_compact=112000 tool_output=12000" "Codex local full-context preset dry-run"

$codexFullContextQ5PresetOutput = Invoke-DryRun `
	-Label "Codex local full-context q5 preset dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "codex"
		DryRun = $true
		CodexPreset = "fullctx-q5"
		ServerUrl = "http://127.0.0.1:9001/v1"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $codexFullContextQ5PresetOutput "Using Codex preset: Full context Q5" "Codex local full-context q5 preset dry-run"
Assert-Contains $codexFullContextQ5PresetOutput "ctx=0 parallel=1 batch=2048 ubatch=512" "Codex local full-context q5 preset dry-run"
Assert-Contains $codexFullContextQ5PresetOutput "cacheReuse=512 ctk=q5_0 ctv=q5_0" "Codex local full-context q5 preset dry-run"

$codexFullContextQ4PresetOutput = Invoke-DryRun `
	-Label "Codex local full-context q4 preset dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "codex"
		DryRun = $true
		CodexPreset = "fullctx-q4"
		ServerUrl = "http://127.0.0.1:9001/v1"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $codexFullContextQ4PresetOutput "Using Codex preset: Full context Q4" "Codex local full-context q4 preset dry-run"
Assert-Contains $codexFullContextQ4PresetOutput "ctx=0 parallel=1 batch=1536 ubatch=384" "Codex local full-context q4 preset dry-run"
Assert-Contains $codexFullContextQ4PresetOutput "cacheReuse=512 ctk=q4_0 ctv=q4_0" "Codex local full-context q4 preset dry-run"

$codexLongPresetOutput = Invoke-DryRun `
	-Label "Codex local long-context preset dry-run" `
	-Script (Join-Path $scriptRoot "run-example.ps1") `
	-Parameters @{
		Example = "codex"
		DryRun = $true
		CodexPreset = "long"
		ServerUrl = "http://127.0.0.1:9001/v1"
		Model = $modelPath
		Configuration = $Configuration
		Platform = $Platform
	}
Assert-Contains $codexLongPresetOutput "Using Codex preset: Long context" "Codex local long-context preset dry-run"
Assert-Contains $codexLongPresetOutput "ctx=131072 parallel=1 batch=4096 ubatch=1024" "Codex local long-context preset dry-run"
Assert-Contains $codexLongPresetOutput "model_context_window=131072 auto_compact=100000 tool_output=8000" "Codex local long-context preset dry-run"

$embeddingRunnerOutput = Invoke-DryRun `
	-Label "embedding runner dry-run" `
	-Script (Join-Path $scriptRoot "dev\run-embedding.ps1") `
	-Parameters @{
		DryRun = $true
		EmbeddingExe = $llamaEmbeddingExe
		ModelPath = $modelPath
		Prompt = "dry embedding prompt"
		Format = "json+"
		GpuLayers = "12"
		ContextSize = 2048
		Pooling = "mean"
	}
Assert-Contains $embeddingRunnerOutput "Running llama-embedding" "Embedding runner dry-run"
Assert-Contains $embeddingRunnerOutput "exe:       $llamaEmbeddingExe" "Embedding runner dry-run"
Assert-Contains $embeddingRunnerOutput "model:     $modelPath" "Embedding runner dry-run"
Assert-Contains $embeddingRunnerOutput "prompt:    dry embedding prompt" "Embedding runner dry-run"
Assert-Contains $embeddingRunnerOutput "format:    json+" "Embedding runner dry-run"
Assert-Contains $embeddingRunnerOutput "--embd-output-format json+" "Embedding runner dry-run"
Assert-Contains $embeddingRunnerOutput "-ngl 12" "Embedding runner dry-run"

$serverOutput = Invoke-DryRun `
	-Label "llama-server dry-run" `
	-Script (Join-Path $scriptRoot "start-llama-server.ps1") `
	-Parameters @{
		DryRun = $true
		ServerExe = $serverExe
		ModelPath = $modelPath
		HostName = "127.0.0.1"
		Port = 9082
		Alias = "dry-server-alias"
		GpuLayers = 77
		ContextSize = 32768
		Temperature = "1.1"
		TopP = "0.91"
		MinP = "0.03"
		SpecType = "ngram-cache"
		NoCudaGraphs = $true
	}
Assert-Contains $serverOutput "exe:       $serverExe" "Server dry-run"
Assert-Contains $serverOutput "model:     $modelPath" "Server dry-run"
Assert-Contains $serverOutput "url:       http://127.0.0.1:9082" "Server dry-run"
Assert-Contains $serverOutput "alias:     dry-server-alias" "Server dry-run"
Assert-Contains $serverOutput "ngl:       77" "Server dry-run"
Assert-Contains $serverOutput "ctx:       32768" "Server dry-run"
Assert-Contains $serverOutput "temp:      1.1" "Server dry-run"
Assert-Contains $serverOutput "top_p:     0.91" "Server dry-run"
Assert-Contains $serverOutput "min_p:     0.03" "Server dry-run"
Assert-Contains $serverOutput "cudaGraph: off" "Server dry-run"
Assert-Contains $serverOutput "specType:  ngram-cache" "Server dry-run"
Assert-Contains $serverOutput "--kv-unified" "Server dry-run"
Assert-Contains $serverOutput "--spec-type ngram-cache" "Server dry-run"
Assert-Contains $serverOutput "--alias dry-server-alias" "Server dry-run"
Assert-Contains $serverOutput "--no-cuda-graphs" "Server dry-run"

$stopServerOutput = Invoke-DryRun `
	-Label "stop llama-server dry-run" `
	-Script (Join-Path $scriptRoot "stop-llama-server.ps1") `
	-Parameters @{
		DryRun = $true
		IncludeExamples = $true
	}
Assert-Contains $stopServerOutput "llama-server stop plan" "Stop server dry-run"
Assert-Contains $stopServerOutput "mode:            dry-run" "Stop server dry-run"

$statusServerOutput = Invoke-DryRun `
	-Label "status llama-server smoke" `
	-Script (Join-Path $scriptRoot "status-llama-server.ps1") `
	-Parameters @{
		TextServerUrl = "http://127.0.0.1:9080"
		EmbeddingServerUrl = "http://127.0.0.1:9081"
	}
Assert-Contains $statusServerOutput "llama-server status" "Status server smoke"
Assert-Contains $statusServerOutput "text      http://127.0.0.1:9080" "Status server smoke"
Assert-Contains $statusServerOutput "embedding http://127.0.0.1:9081" "Status server smoke"
Assert-Contains $statusServerOutput "codex     http://127.0.0.1:8001" "Status server smoke"

$embeddingServerOutput = Invoke-DryRun `
	-Label "embedding llama-server dry-run" `
	-Script (Join-Path $scriptRoot "start-llama-server.ps1") `
	-Parameters @{
		DryRun = $true
		Embeddings = $true
		ServerExe = $serverExe
		ModelPath = $modelPath
	}
Assert-Contains $embeddingServerOutput "url:       http://127.0.0.1:8081" "Embedding server dry-run"
Assert-Contains $embeddingServerOutput "embeddings: on" "Embedding server dry-run"
Assert-Contains $embeddingServerOutput "pooling:   mean" "Embedding server dry-run"
Assert-Contains $embeddingServerOutput "--embeddings" "Embedding server dry-run"
Assert-Contains $embeddingServerOutput "--pooling mean" "Embedding server dry-run"

$previousEmbeddingModel = $env:OFXGGML_EMBEDDING_MODEL
$env:OFXGGML_EMBEDDING_MODEL = $modelPath
try {
	$embeddingServerEnvOutput = Invoke-DryRun `
		-Label "embedding llama-server env model dry-run" `
		-Script (Join-Path $scriptRoot "start-llama-server.ps1") `
		-Parameters @{
			DryRun = $true
			Embeddings = $true
			ServerExe = $serverExe
		}
} finally {
	if ($null -eq $previousEmbeddingModel) {
		Remove-Item Env:\OFXGGML_EMBEDDING_MODEL -ErrorAction SilentlyContinue
	} else {
		$env:OFXGGML_EMBEDDING_MODEL = $previousEmbeddingModel
	}
}
Assert-Contains $embeddingServerEnvOutput "model:     $modelPath" "Embedding server env model dry-run"
Assert-Contains $embeddingServerEnvOutput "url:       http://127.0.0.1:8081" "Embedding server env model dry-run"

Write-Step "Launch dry-run smoke coverage passed"
