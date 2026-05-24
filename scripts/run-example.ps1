param(
	[Parameter(Position = 0)]
	[ValidateSet("text", "chat", "embedding", "emb", "codex")]
	[string]$Example = "text",
	[string]$Backend = $(if ($env:OFXGGML_TEXT_BACKEND) { $env:OFXGGML_TEXT_BACKEND } else { "server" }),
	[string]$ServerUrl = "",
	[string]$ServerModel = "",
	[string]$LlamaCli = $env:OFXGGML_LLAMA_CLI,
	[string]$Model = "",
	[string]$CodexPreset = "",
	[ValidateSet("local", "openai", "hybrid", "ollama", "hybrid-ollama")]
	[string]$CodexProvider = "",
	[string]$OpenAiModel = "",
	[string]$GpuLayers = "",
	[int]$ContextSize = [int]::MinValue,
	[int]$Parallel = [int]::MinValue,
	[int]$BatchSize = [int]::MinValue,
	[int]$UBatchSize = [int]::MinValue,
	[int]$Threads = [int]::MinValue,
	[int]$ThreadsBatch = [int]::MinValue,
	[int]$ThreadsHttp = [int]::MinValue,
	[int]$CacheReuse = [int]::MinValue,
	[string]$KvCacheKeyType = "",
	[string]$KvCacheValueType = "",
	[string]$SpecType = "",
	[int]$ModelContextWindow = [int]::MinValue,
	[int]$ModelAutoCompactTokenLimit = [int]::MinValue,
	[int]$ToolOutputTokenLimit = [int]::MinValue,
	[Alias("AgentMaxAgents", "MaxAgents", "AgentMaxThreads", "MaxAgentThreads")]
	[int]$AgentMaxConcurrentThreads = [int]::MinValue,
	[int]$AgentMaxDepth = [int]::MinValue,
	[int]$AgentMinWaitMs = [int]::MinValue,
	[int]$AgentMaxWaitMs = [int]::MinValue,
	[int]$AgentDefaultWaitMs = [int]::MinValue,
	[int]$StartupTimeoutSeconds = [int]::MinValue,
	[string]$Temperature = "",
	[string]$TopP = "",
	[string]$MinP = "",
	[string]$ChatTemplateKwargs = "",
	[string]$Reasoning = "",
	[string]$ReasoningBudget = "",
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
$defaultCodexModelAlias = "local/Qwen3.6-35B-A3B-UD-Q4_K_M"
$defaultCodexOllamaModel = "hermes3:latest"
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

function Get-OfxGgmlLocalModelAlias {
	param([string]$ModelPath)

	if ([string]::IsNullOrWhiteSpace($ModelPath)) {
		return ""
	}
	$name = [System.IO.Path]::GetFileNameWithoutExtension($ModelPath)
	if ([string]::IsNullOrWhiteSpace($name)) {
		return ""
	}
	$slug = ($name -replace '[^A-Za-z0-9._-]+', '-').Trim("-")
	if ([string]::IsNullOrWhiteSpace($slug)) {
		return ""
	}
	return "local/$slug"
}

function Get-OfxGgmlCodexPresetDefaults {
	param([string]$Name)

	$preset = if ([string]::IsNullOrWhiteSpace($Name)) { "quality" } else { $Name.Trim().ToLowerInvariant() }
	switch ($preset) {
		"memory" {
			return @{
				Name = "memory"
				Label = "Memory saver"
				ContextSize = 16384
				Parallel = 1
				BatchSize = 1024
				UBatchSize = 256
				Threads = 0
				ThreadsBatch = 0
				ThreadsHttp = 0
				CacheReuse = 128
				KvCacheKeyType = ""
				KvCacheValueType = ""
				ModelContextWindow = 16384
				ModelAutoCompactTokenLimit = 12000
				ToolOutputTokenLimit = 3000
				AgentMaxConcurrentThreads = 0
				AgentMaxDepth = 0
				AgentMinWaitMs = 2500
				AgentMaxWaitMs = 90000
				AgentDefaultWaitMs = 30000
				StartupTimeoutSeconds = 300
				Temperature = "0.8"
				TopP = "0.9"
				MinP = "0.02"
			}
		}
		"fast" {
			return @{
				Name = "fast"
				Label = "Fast coding"
				ContextSize = 32768
				Parallel = 1
				BatchSize = 4096
				UBatchSize = 1024
				Threads = 0
				ThreadsBatch = 0
				ThreadsHttp = 0
				CacheReuse = 256
				KvCacheKeyType = ""
				KvCacheValueType = ""
				ModelContextWindow = 32768
				ModelAutoCompactTokenLimit = 24000
				ToolOutputTokenLimit = 5000
				AgentMaxConcurrentThreads = 0
				AgentMaxDepth = 0
				AgentMinWaitMs = 2500
				AgentMaxWaitMs = 120000
				AgentDefaultWaitMs = 30000
				StartupTimeoutSeconds = 300
				Temperature = "0.6"
				TopP = "0.9"
				MinP = "0.02"
			}
		}
		"balanced" {
			return @{
				Name = "balanced"
				Label = "Balanced local"
				ContextSize = 40960
				Parallel = 1
				BatchSize = 2048
				UBatchSize = 512
				Threads = 0
				ThreadsBatch = 0
				ThreadsHttp = 0
				CacheReuse = 256
				KvCacheKeyType = ""
				KvCacheValueType = ""
				ModelContextWindow = 40960
				ModelAutoCompactTokenLimit = 30000
				ToolOutputTokenLimit = 5000
				AgentMaxConcurrentThreads = 0
				AgentMaxDepth = 0
				AgentMinWaitMs = 2500
				AgentMaxWaitMs = 120000
				AgentDefaultWaitMs = 30000
				StartupTimeoutSeconds = 300
				Temperature = "1.0"
				TopP = "0.95"
				MinP = "0.01"
			}
		}
		"quality" {
			return @{
				Name = "quality"
				Label = "Quality coding"
				ContextSize = 262144
				Parallel = 1
				BatchSize = 3072
				UBatchSize = 768
				Threads = 0
				ThreadsBatch = 0
				ThreadsHttp = 0
				CacheReuse = 256
				KvCacheKeyType = ""
				KvCacheValueType = ""
				ModelContextWindow = 262144
				ModelAutoCompactTokenLimit = 220000
				ToolOutputTokenLimit = 12000
				AgentMaxConcurrentThreads = 0
				AgentMaxDepth = 0
				AgentMinWaitMs = 2500
				AgentMaxWaitMs = 180000
				AgentDefaultWaitMs = 30000
				StartupTimeoutSeconds = 600
				Temperature = "0.7"
				TopP = "0.9"
				MinP = "0.02"
			}
		}
		"fullctx" {
			return @{
				Name = "fullctx"
				Label = "Full context Q8"
				ContextSize = 0
				Parallel = 1
				BatchSize = 2048
				UBatchSize = 512
				Threads = 0
				ThreadsBatch = 0
				ThreadsHttp = 0
				CacheReuse = 512
				KvCacheKeyType = "q8_0"
				KvCacheValueType = "q8_0"
				ModelContextWindow = 262144
				ModelAutoCompactTokenLimit = 220000
				ToolOutputTokenLimit = 12000
				AgentMaxConcurrentThreads = 0
				AgentMaxDepth = 0
				AgentMinWaitMs = 5000
				AgentMaxWaitMs = 240000
				AgentDefaultWaitMs = 30000
				StartupTimeoutSeconds = 600
				Temperature = "0.7"
				TopP = "0.9"
				MinP = "0.02"
			}
		}
		"fullctx-q5" {
			return @{
				Name = "fullctx-q5"
				Label = "Full context Q5"
				ContextSize = 0
				Parallel = 1
				BatchSize = 2048
				UBatchSize = 512
				Threads = 0
				ThreadsBatch = 0
				ThreadsHttp = 0
				CacheReuse = 512
				KvCacheKeyType = "q5_0"
				KvCacheValueType = "q5_0"
				ModelContextWindow = 262144
				ModelAutoCompactTokenLimit = 220000
				ToolOutputTokenLimit = 12000
				AgentMaxConcurrentThreads = 0
				AgentMaxDepth = 0
				AgentMinWaitMs = 5000
				AgentMaxWaitMs = 240000
				AgentDefaultWaitMs = 30000
				StartupTimeoutSeconds = 600
				Temperature = "0.7"
				TopP = "0.9"
				MinP = "0.02"
			}
		}
		"fullctx-q4" {
			return @{
				Name = "fullctx-q4"
				Label = "Full context Q4"
				ContextSize = 0
				Parallel = 1
				BatchSize = 1536
				UBatchSize = 384
				Threads = 0
				ThreadsBatch = 0
				ThreadsHttp = 0
				CacheReuse = 512
				KvCacheKeyType = "q4_0"
				KvCacheValueType = "q4_0"
				ModelContextWindow = 262144
				ModelAutoCompactTokenLimit = 220000
				ToolOutputTokenLimit = 12000
				AgentMaxConcurrentThreads = 0
				AgentMaxDepth = 0
				AgentMinWaitMs = 5000
				AgentMaxWaitMs = 240000
				AgentDefaultWaitMs = 30000
				StartupTimeoutSeconds = 600
				Temperature = "0.7"
				TopP = "0.9"
				MinP = "0.02"
			}
		}
		"long" {
			return @{
				Name = "long"
				Label = "Long context"
				ContextSize = 262144
				Parallel = 1
				BatchSize = 4096
				UBatchSize = 1024
				Threads = 0
				ThreadsBatch = 0
				ThreadsHttp = 0
				CacheReuse = 512
				KvCacheKeyType = ""
				KvCacheValueType = ""
				ModelContextWindow = 262144
				ModelAutoCompactTokenLimit = 220000
				ToolOutputTokenLimit = 12000
				AgentMaxConcurrentThreads = 0
				AgentMaxDepth = 0
				AgentMinWaitMs = 5000
				AgentMaxWaitMs = 300000
				AgentDefaultWaitMs = 30000
				StartupTimeoutSeconds = 600
				Temperature = "0.8"
				TopP = "0.92"
				MinP = "0.02"
			}
		}
		"concurrent" {
			return @{
				Name = "concurrent"
				Label = "Concurrent agents"
				ContextSize = 65536
				Parallel = 2
				BatchSize = 2048
				UBatchSize = 512
				Threads = 0
				ThreadsBatch = 0
				ThreadsHttp = 0
				CacheReuse = 256
				KvCacheKeyType = ""
				KvCacheValueType = ""
				ModelContextWindow = 32768
				ModelAutoCompactTokenLimit = 24000
				ToolOutputTokenLimit = 5000
				AgentMaxConcurrentThreads = 2
				AgentMaxDepth = 0
				AgentMinWaitMs = 2500
				AgentMaxWaitMs = 180000
				AgentDefaultWaitMs = 30000
				StartupTimeoutSeconds = 600
				Temperature = "0.9"
				TopP = "0.95"
				MinP = "0.01"
			}
		}
		default {
			throw "Unknown Codex preset '$Name'. Use memory, fast, balanced, quality, fullctx, fullctx-q5, fullctx-q4, long, or concurrent."
		}
	}
}

if ($isCodex) {
	$hasExplicitCodexModelPath = ![string]::IsNullOrWhiteSpace($Model) -or
		![string]::IsNullOrWhiteSpace($env:OFXGGML_TEXT_MODEL)
	$resolvedCodexProvider = if (![string]::IsNullOrWhiteSpace($CodexProvider)) {
		$CodexProvider
	} elseif ($env:OFXGGML_CODEX_PROVIDER) {
		$env:OFXGGML_CODEX_PROVIDER
	} else {
		"local"
	}
	$useOllamaCodexProvider = $resolvedCodexProvider -eq "ollama" -or
		$resolvedCodexProvider -eq "hybrid-ollama"
	$useLlamaCppCodexProvider = $resolvedCodexProvider -eq "local" -or
		$resolvedCodexProvider -eq "hybrid"
	$useLocalCodexProvider = $useOllamaCodexProvider -or $useLlamaCppCodexProvider
	$useOpenAiCodexLaunch = $resolvedCodexProvider -eq "openai" -or
		$resolvedCodexProvider -eq "hybrid" -or
		$resolvedCodexProvider -eq "hybrid-ollama"
	if ([string]::IsNullOrWhiteSpace($OpenAiModel)) {
		$OpenAiModel = if ($env:OFXGGML_CODEX_OPENAI_MODEL) {
			$env:OFXGGML_CODEX_OPENAI_MODEL
		} elseif ($useOpenAiCodexLaunch -and $env:OFXGGML_CODEX_MODEL -and !$useLocalCodexProvider) {
			$env:OFXGGML_CODEX_MODEL
		} else {
			"gpt-5"
		}
	}
	$presetName = if (![string]::IsNullOrWhiteSpace($CodexPreset)) {
		$CodexPreset
	} elseif ($env:OFXGGML_CODEX_PRESET) {
		$env:OFXGGML_CODEX_PRESET
	} else {
		"quality"
	}
	$codexPresetDefaults = Get-OfxGgmlCodexPresetDefaults $presetName
	if ([string]::IsNullOrWhiteSpace($ServerUrl)) {
		$ServerUrl = if ($env:OFXGGML_CODEX_BASE_URL) {
			$env:OFXGGML_CODEX_BASE_URL
		} elseif ($useOllamaCodexProvider) {
			"http://127.0.0.1:11434/v1"
		} else {
			"http://127.0.0.1:8001/v1"
		}
	}
	if ([string]::IsNullOrWhiteSpace($GpuLayers)) {
		$GpuLayers = if ($env:OFXGGML_CODEX_GPU_LAYERS) { $env:OFXGGML_CODEX_GPU_LAYERS } else { "all" }
	}
	if ($ContextSize -eq [int]::MinValue) {
		$ContextSize = if ($env:OFXGGML_CODEX_CONTEXT_SIZE) { [int]$env:OFXGGML_CODEX_CONTEXT_SIZE } else { $codexPresetDefaults.ContextSize }
	}
	if ($Parallel -eq [int]::MinValue) {
		$Parallel = if ($env:OFXGGML_CODEX_PARALLEL) { [int]$env:OFXGGML_CODEX_PARALLEL } else { $codexPresetDefaults.Parallel }
	}
	if ($BatchSize -eq [int]::MinValue) {
		$BatchSize = if ($env:OFXGGML_CODEX_BATCH_SIZE) { [int]$env:OFXGGML_CODEX_BATCH_SIZE } else { $codexPresetDefaults.BatchSize }
	}
	if ($UBatchSize -eq [int]::MinValue) {
		$UBatchSize = if ($env:OFXGGML_CODEX_UBATCH_SIZE) { [int]$env:OFXGGML_CODEX_UBATCH_SIZE } else { $codexPresetDefaults.UBatchSize }
	}
	if ($Threads -eq [int]::MinValue) {
		$Threads = if ($env:OFXGGML_CODEX_THREADS) { [int]$env:OFXGGML_CODEX_THREADS } else { $codexPresetDefaults.Threads }
	}
	if ($ThreadsBatch -eq [int]::MinValue) {
		$ThreadsBatch = if ($env:OFXGGML_CODEX_THREADS_BATCH) { [int]$env:OFXGGML_CODEX_THREADS_BATCH } else { $codexPresetDefaults.ThreadsBatch }
	}
	if ($ThreadsHttp -eq [int]::MinValue) {
		$ThreadsHttp = if ($env:OFXGGML_CODEX_THREADS_HTTP) { [int]$env:OFXGGML_CODEX_THREADS_HTTP } else { $codexPresetDefaults.ThreadsHttp }
	}
	if ($CacheReuse -eq [int]::MinValue) {
		$CacheReuse = if ($env:OFXGGML_CODEX_CACHE_REUSE) { [int]$env:OFXGGML_CODEX_CACHE_REUSE } else { $codexPresetDefaults.CacheReuse }
	}
	if ([string]::IsNullOrWhiteSpace($KvCacheKeyType)) {
		$KvCacheKeyType = if ($env:OFXGGML_CODEX_KV_CACHE_KEY_TYPE) { $env:OFXGGML_CODEX_KV_CACHE_KEY_TYPE } else { $codexPresetDefaults.KvCacheKeyType }
	}
	if ([string]::IsNullOrWhiteSpace($KvCacheValueType)) {
		$KvCacheValueType = if ($env:OFXGGML_CODEX_KV_CACHE_VALUE_TYPE) { $env:OFXGGML_CODEX_KV_CACHE_VALUE_TYPE } else { $codexPresetDefaults.KvCacheValueType }
	}
	if ([string]::IsNullOrWhiteSpace($SpecType)) {
		$SpecType = if ($env:OFXGGML_CODEX_SPEC_TYPE) { $env:OFXGGML_CODEX_SPEC_TYPE } else { "" }
	}
	if ($ModelContextWindow -eq [int]::MinValue) {
		$ModelContextWindow = if ($env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW) { [int]$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW } else { $codexPresetDefaults.ModelContextWindow }
	}
	if ($ModelAutoCompactTokenLimit -eq [int]::MinValue) {
		$ModelAutoCompactTokenLimit = if ($env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT } else { $codexPresetDefaults.ModelAutoCompactTokenLimit }
	}
	if ($ToolOutputTokenLimit -eq [int]::MinValue) {
		$ToolOutputTokenLimit = if ($env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT) { [int]$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT } else { $codexPresetDefaults.ToolOutputTokenLimit }
	}
	if ($AgentMaxConcurrentThreads -eq [int]::MinValue) {
		$AgentMaxConcurrentThreads = if ($env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS) {
			[int]$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS
		} elseif ($env:OFXGGML_CODEX_AGENT_MAX_THREADS) {
			[int]$env:OFXGGML_CODEX_AGENT_MAX_THREADS
		} elseif ($env:OFXGGML_CODEX_AGENT_MAX_AGENTS) {
			[int]$env:OFXGGML_CODEX_AGENT_MAX_AGENTS
		} else {
			$codexPresetDefaults.AgentMaxConcurrentThreads
		}
	}
	if ($AgentMaxDepth -eq [int]::MinValue) {
		$AgentMaxDepth = if ($env:OFXGGML_CODEX_AGENT_MAX_DEPTH) { [int]$env:OFXGGML_CODEX_AGENT_MAX_DEPTH } else { $codexPresetDefaults.AgentMaxDepth }
	}
	if ($AgentMinWaitMs -eq [int]::MinValue) {
		$AgentMinWaitMs = if ($env:OFXGGML_CODEX_AGENT_MIN_WAIT_MS) { [int]$env:OFXGGML_CODEX_AGENT_MIN_WAIT_MS } else { $codexPresetDefaults.AgentMinWaitMs }
	}
	if ($AgentMaxWaitMs -eq [int]::MinValue) {
		$AgentMaxWaitMs = if ($env:OFXGGML_CODEX_AGENT_MAX_WAIT_MS) { [int]$env:OFXGGML_CODEX_AGENT_MAX_WAIT_MS } else { $codexPresetDefaults.AgentMaxWaitMs }
	}
	if ($AgentDefaultWaitMs -eq [int]::MinValue) {
		$AgentDefaultWaitMs = if ($env:OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS) { [int]$env:OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS } else { $codexPresetDefaults.AgentDefaultWaitMs }
	}
	if ($StartupTimeoutSeconds -eq [int]::MinValue) {
		$StartupTimeoutSeconds = if ($env:OFXGGML_CODEX_STARTUP_TIMEOUT) { [int]$env:OFXGGML_CODEX_STARTUP_TIMEOUT } else { $codexPresetDefaults.StartupTimeoutSeconds }
	}
	if ([string]::IsNullOrWhiteSpace($Temperature)) {
		$Temperature = if ($env:OFXGGML_CODEX_TEMP) { $env:OFXGGML_CODEX_TEMP } else { $codexPresetDefaults.Temperature }
	}
	if ([string]::IsNullOrWhiteSpace($TopP)) {
		$TopP = if ($env:OFXGGML_CODEX_TOP_P) { $env:OFXGGML_CODEX_TOP_P } else { $codexPresetDefaults.TopP }
	}
	if ([string]::IsNullOrWhiteSpace($MinP)) {
		$MinP = if ($env:OFXGGML_CODEX_MIN_P) { $env:OFXGGML_CODEX_MIN_P } else { $codexPresetDefaults.MinP }
	}
	if ([string]::IsNullOrWhiteSpace($ChatTemplateKwargs)) {
		$ChatTemplateKwargs = if ($env:OFXGGML_CODEX_CHAT_TEMPLATE_KWARGS) { $env:OFXGGML_CODEX_CHAT_TEMPLATE_KWARGS } else { '{"enable_thinking": false}' }
	}
	if ([string]::IsNullOrWhiteSpace($Reasoning)) {
		$Reasoning = if ($env:OFXGGML_CODEX_REASONING) { $env:OFXGGML_CODEX_REASONING } else { "off" }
	}
	if ([string]::IsNullOrWhiteSpace($ReasoningBudget)) {
		$ReasoningBudget = if ($env:OFXGGML_CODEX_REASONING_BUDGET) { $env:OFXGGML_CODEX_REASONING_BUDGET } else { "0" }
	}
	$codexNoCudaGraphs = $NoCudaGraphs -or (![string]::IsNullOrWhiteSpace($env:OFXGGML_CODEX_NO_CUDA_GRAPHS) -and $env:OFXGGML_CODEX_NO_CUDA_GRAPHS -ne "0")
	$codexSkipChatParsing = if ($env:OFXGGML_CODEX_SKIP_CHAT_PARSING) {
		$env:OFXGGML_CODEX_SKIP_CHAT_PARSING -ne "0"
	} else {
		$false
	}
	if ($useLlamaCppCodexProvider -and [string]::IsNullOrWhiteSpace($Model)) {
		$Model = if ($env:OFXGGML_TEXT_MODEL) { $env:OFXGGML_TEXT_MODEL } else { "" }
	}
	if ($useLlamaCppCodexProvider -and [string]::IsNullOrWhiteSpace($Model)) {
		$Model = Find-OfxGgmlFirstModel (Get-OfxGgmlModelSearchDirectories `
			-AddonRoot $addonRoot `
			-ExampleRoot $exampleRoot `
			-ExtraExampleNames @("ofxGgmlTextExample", "ofxGgmlChatExample"))
	}
	if ([string]::IsNullOrWhiteSpace($ServerModel)) {
		if ($useLlamaCppCodexProvider -and $hasExplicitCodexModelPath) {
			$ServerModel = Get-OfxGgmlLocalModelAlias -ModelPath $Model
		}
		if ([string]::IsNullOrWhiteSpace($ServerModel) -and
			$useLocalCodexProvider -and
			$env:OFXGGML_CODEX_MODEL) {
			$ServerModel = $env:OFXGGML_CODEX_MODEL
		}
		if ([string]::IsNullOrWhiteSpace($ServerModel) -and $useOllamaCodexProvider) {
			$ServerModel = $defaultCodexOllamaModel
		}
		if ([string]::IsNullOrWhiteSpace($ServerModel) -and $useLlamaCppCodexProvider) {
			$ServerModel = $defaultCodexModelAlias
		}
	}
	$env:OFXGGML_CODEX_PROVIDER = $resolvedCodexProvider
	$env:OFXGGML_CODEX_BASE_URL = $ServerUrl
	$env:OFXGGML_CODEX_MODEL = $ServerModel
	$env:OFXGGML_CODEX_OPENAI_MODEL = $OpenAiModel
	$env:OFXGGML_CODEX_PRESET = $codexPresetDefaults.Name
	$env:OFXGGML_CODEX_GPU_LAYERS = $GpuLayers
	$env:OFXGGML_CODEX_CONTEXT_SIZE = $ContextSize.ToString()
	$env:OFXGGML_CODEX_PARALLEL = $Parallel.ToString()
	$env:OFXGGML_CODEX_BATCH_SIZE = $BatchSize.ToString()
	$env:OFXGGML_CODEX_UBATCH_SIZE = $UBatchSize.ToString()
	$env:OFXGGML_CODEX_THREADS = $Threads.ToString()
	$env:OFXGGML_CODEX_THREADS_BATCH = $ThreadsBatch.ToString()
	$env:OFXGGML_CODEX_THREADS_HTTP = $ThreadsHttp.ToString()
	$env:OFXGGML_CODEX_CACHE_REUSE = $CacheReuse.ToString()
	$env:OFXGGML_CODEX_KV_CACHE_KEY_TYPE = $KvCacheKeyType
	$env:OFXGGML_CODEX_KV_CACHE_VALUE_TYPE = $KvCacheValueType
	$env:OFXGGML_CODEX_SPEC_TYPE = $SpecType
	$env:OFXGGML_CODEX_FLASH_ATTN = "1"
	$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW = $ModelContextWindow.ToString()
	$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT = $ModelAutoCompactTokenLimit.ToString()
	$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT = $ToolOutputTokenLimit.ToString()
	$env:OFXGGML_CODEX_AGENT_MAX_AGENTS = $AgentMaxConcurrentThreads.ToString()
	$env:OFXGGML_CODEX_AGENT_MAX_THREADS = $AgentMaxConcurrentThreads.ToString()
	$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS = $AgentMaxConcurrentThreads.ToString()
	$env:OFXGGML_CODEX_AGENT_MAX_DEPTH = $AgentMaxDepth.ToString()
	$env:OFXGGML_CODEX_AGENT_MIN_WAIT_MS = $AgentMinWaitMs.ToString()
	$env:OFXGGML_CODEX_AGENT_MAX_WAIT_MS = $AgentMaxWaitMs.ToString()
	$env:OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS = $AgentDefaultWaitMs.ToString()
	$env:OFXGGML_CODEX_TEMP = $Temperature
	$env:OFXGGML_CODEX_TOP_P = $TopP
	$env:OFXGGML_CODEX_MIN_P = $MinP
	$env:OFXGGML_CODEX_CHAT_TEMPLATE_KWARGS = $ChatTemplateKwargs
	$env:OFXGGML_CODEX_REASONING = $Reasoning
	$env:OFXGGML_CODEX_REASONING_BUDGET = $ReasoningBudget
	$env:OFXGGML_CODEX_NO_CUDA_GRAPHS = if ($codexNoCudaGraphs) { "1" } else { "0" }
	$env:OFXGGML_CODEX_SKIP_CHAT_PARSING = if ($codexSkipChatParsing) { "1" } else { "0" }
	if ($useLlamaCppCodexProvider -and ![string]::IsNullOrWhiteSpace($Model)) {
		$env:OFXGGML_TEXT_MODEL = $Model
		Write-OfxGgmlStep "Using text model: $Model"
	} elseif ($useLlamaCppCodexProvider) {
		Write-Warning "No GGUF model found. The example can still connect to an already-running server."
	}
	Write-OfxGgmlStep "Using Codex provider: $resolvedCodexProvider"
	if ($useLocalCodexProvider) {
		Write-OfxGgmlStep "Using Codex local endpoint: $ServerUrl"
	}
	if (![string]::IsNullOrWhiteSpace($ServerModel)) {
		Write-OfxGgmlStep "Using Codex model alias: $ServerModel"
	}
	if ($useOpenAiCodexLaunch -and ![string]::IsNullOrWhiteSpace($OpenAiModel)) {
		Write-OfxGgmlStep "Using Codex OpenAI model: $OpenAiModel"
	}
	Write-OfxGgmlStep "Using Codex preset: $($codexPresetDefaults.Label)"
	Write-OfxGgmlStep "Using Codex server options: ngl=$GpuLayers ctx=$ContextSize parallel=$Parallel batch=$BatchSize ubatch=$UBatchSize threads=$(if ($Threads -gt 0) { $Threads } else { 'auto' }) batchThreads=$(if ($ThreadsBatch -gt 0) { $ThreadsBatch } else { 'auto' }) httpThreads=$(if ($ThreadsHttp -gt 0) { $ThreadsHttp } else { 'auto' }) cacheReuse=$CacheReuse ctk=$(if (![string]::IsNullOrWhiteSpace($KvCacheKeyType)) { $KvCacheKeyType } else { 'default' }) ctv=$(if (![string]::IsNullOrWhiteSpace($KvCacheValueType)) { $KvCacheValueType } else { 'default' }) spec=$(if (![string]::IsNullOrWhiteSpace($SpecType)) { $SpecType } else { 'default' }) flashAttn=on temp=$Temperature top_p=$TopP min_p=$MinP reasoning=$Reasoning thinkBudget=$ReasoningBudget cudaGraph=$(if ($codexNoCudaGraphs) { 'off' } else { 'on' }) skipChatParsing=$(if ($codexSkipChatParsing) { 'on' } else { 'off' })"
	Write-OfxGgmlStep "Using Codex config defaults: model_context_window=$ModelContextWindow auto_compact=$ModelAutoCompactTokenLimit tool_output=$ToolOutputTokenLimit"
	Write-OfxGgmlStep "Using Codex agent settings: max_threads=$(if ($AgentMaxConcurrentThreads -gt 0) { $AgentMaxConcurrentThreads } else { 'auto' }) max_depth=$(if ($AgentMaxDepth -gt 0) { $AgentMaxDepth } else { 'auto' }) wait_ms=$AgentMinWaitMs/$AgentDefaultWaitMs/$AgentMaxWaitMs"
	if ($DryRun) {
		Write-OfxGgmlStep "Executable: $exampleExe"
		Write-OfxGgmlStep "Auto server: $(if ($NoAutoServer) { 'off' } else { 'on' })"
		return
	}
	if ($useLlamaCppCodexProvider) {
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
			-Parallel $Parallel `
			-BatchSize $BatchSize `
			-UBatchSize $UBatchSize `
			-Threads $Threads `
			-ThreadsBatch $ThreadsBatch `
			-ThreadsHttp $ThreadsHttp `
			-CacheReuse $CacheReuse `
			-KvCacheKeyType $KvCacheKeyType `
			-KvCacheValueType $KvCacheValueType `
			-SpecType $SpecType `
			-Temperature $Temperature `
			-TopP $TopP `
			-MinP $MinP `
			-ChatTemplateKwargs $ChatTemplateKwargs `
			-Reasoning $Reasoning `
			-ReasoningBudget $ReasoningBudget `
			-Jinja `
			-FlashAttention `
			-NoCudaGraphs:$codexNoCudaGraphs `
			-SkipChatParsing:$codexSkipChatParsing `
			-ForceNew:$ForceNewServer `
			-NoAutoServer:$NoAutoServer
	}
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
