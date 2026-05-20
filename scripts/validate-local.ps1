param()

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Assert-Path {
	param(
		[string]$Path,
		[string]$Label,
		[switch]$Directory
	)

	if ($Directory) {
		if (!(Test-Path -LiteralPath $Path -PathType Container)) {
			throw "$Label was not found: $Path"
		}
	} elseif (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
		throw "$Label was not found: $Path"
	}
}

function Assert-FileContains {
	param(
		[string]$Path,
		[string]$Pattern,
		[string]$Label
	)
	$content = Get-Content -LiteralPath $Path -Raw
	if ($content -notmatch $Pattern) {
		throw "$Label did not contain expected pattern: $Pattern"
	}
}

function Assert-FileNotContains {
	param(
		[string]$Path,
		[string]$Pattern,
		[string]$Label
	)
	$content = Get-Content -LiteralPath $Path -Raw
	if ($content -match $Pattern) {
		throw "$Label contained unexpected pattern: $Pattern"
	}
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Split-Path -Parent $scriptRoot
$addonsRoot = Split-Path -Parent $addonRoot

Write-Step "Checking addon skeleton"
Assert-Path (Join-Path $addonRoot "addon_config.mk") "addon config"
Assert-Path (Join-Path $addonRoot "README.md") "README"
Assert-Path (Join-Path $addonRoot "LICENSE") "license"
Assert-Path (Join-Path $addonRoot "docs\LLAMA_WORKFLOWS.md") "llama workflow docs"
Assert-Path (Join-Path $addonRoot "docs\OPENCODE_LOCAL_SERVER.md") "OpenCode local server docs"
Assert-FileContains (Join-Path $addonRoot "README.md") "docs/LLAMA_WORKFLOWS.md" "README"
Assert-FileContains (Join-Path $addonRoot "README.md") "docs/OPENCODE_LOCAL_SERVER.md" "README"
Assert-FileContains (Join-Path $addonRoot "docs\LLAMA_WORKFLOWS.md") "Planning handoff" "llama workflow docs"
Assert-FileContains (Join-Path $addonRoot "docs\LLAMA_WORKFLOWS.md") "Validation ladder" "llama workflow docs"
Assert-FileContains (Join-Path $addonRoot "docs\LLAMA_WORKFLOWS.md") "CLI fallback" "llama workflow docs"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlLlama.h") "public header"
Assert-Path (Join-Path $addonRoot "src\ofxGgmlLlamaVersion.h") "version header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlamaVersion.h") "OFXGGML_LLAMA_VERSION_STRING" "version header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlama.h") "ofxGgmlLlamaVersion.h" "public header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlama.h") "ofxGgmlLlamaCliTextBackend.h" "public header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlama.h") "ofxGgmlLlamaServerTextBackend.h" "public header"
Assert-FileContains (Join-Path $addonRoot "src\ofxGgmlLlama.h") "ofxGgmlLlamaServerEmbeddingBackend.h" "public header"
Assert-FileContains (Join-Path $addonRoot "addon_config.mk") "ADDON_DEPENDENCIES\s*\+=\s*ofxGgmlCore" "addon config"
Assert-FileContains (Join-Path $addonRoot "addon_config.mk") "\.\./ofxGgmlCore/src" "addon config"
Assert-Path (Join-Path $addonRoot "tests\CMakeLists.txt") "test CMakeLists"
Assert-Path (Join-Path $addonRoot "tests\test_main.cpp") "test source"

Write-Step "Checking dependency layout"
Assert-Path (Join-Path $addonsRoot "ofxGgmlCore") "sibling ofxGgmlCore addon" -Directory

Write-Step "Checking example layout"
foreach ($example in @("ofxGgmlTextExample", "ofxGgmlChatExample", "ofxGgmlEmbeddingExample", "ofxGgmlLlamaCodexLocalExample")) {
	$exampleRoot = Join-Path $addonRoot $example
	Assert-Path $exampleRoot "$example root" -Directory
	Assert-Path (Join-Path $exampleRoot "addons.make") "$example addons.make"
	Assert-Path (Join-Path $exampleRoot "src\main.cpp") "$example main.cpp"
	Assert-Path (Join-Path $exampleRoot "src\ofApp.h") "$example ofApp.h"
	Assert-Path (Join-Path $exampleRoot "src\ofApp.cpp") "$example ofApp.cpp"
}
Assert-Path (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") "Codex local example README"
Assert-Path (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") "Codex local example config"
Assert-Path (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\opencode.example.json") "OpenCode local example config"
Assert-Path (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\explorer.toml") "Codex local explorer agent config"
Assert-Path (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\worker.toml") "Codex local worker agent config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") "llama-server" "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") "OpenCode" "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") "wire_api" "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\opencode.example.json") '"model": "llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL"' "OpenCode local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\opencode.example.json") '"default_agent": "build"' "OpenCode local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\opencode.example.json") '"npm": "@ai-sdk/openai-compatible"' "OpenCode local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\opencode.example.json") '"baseURL": "http://127.0.0.1:8001/v1"' "OpenCode local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\opencode.example.json") '"agent":' "OpenCode local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\opencode.example.json") '"websearch": "deny"' "OpenCode local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\opencode.example.json") '"disabled_providers":' "OpenCode local example config"
Assert-FileContains (Join-Path $addonRoot "docs\OPENCODE_LOCAL_SERVER.md") "plan-local-opencode" "OpenCode local server docs"
Assert-FileContains (Join-Path $addonRoot "docs\OPENCODE_LOCAL_SERVER.md") "@ai-sdk/openai-compatible" "OpenCode local server docs"
Assert-FileContains (Join-Path $addonRoot "docs\LOCAL_AGENT_ROUTING.md") "OpenCode Direct Route" "local agent routing docs"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") 'wire_api = "responses"' "Codex local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") 'web_search = "disabled"' "Codex local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") 'model_context_window = 65536' "Codex local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") 'tool_output_token_limit = 8000' "Codex local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") 'max_threads = 1' "Codex local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") '\[agents\]' "Codex local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") 'max_depth = 1' "Codex local example config"
Assert-FileNotContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") '\[agents\.explorer\]' "Codex local example config"
Assert-FileNotContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-config.example.toml") 'config_file = ' "Codex local example config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\explorer.toml") 'developer_instructions' "Codex local explorer agent config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\worker.toml") 'developer_instructions' "Codex local worker agent config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\explorer.toml") 'name = "explorer"' "Codex local explorer agent config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\worker.toml") 'name = "worker"' "Codex local worker agent config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\explorer.toml") 'model = "local/example-model"' "Codex local explorer agent config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\worker.toml") 'model = "local/example-model"' "Codex local worker agent config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\explorer.toml") 'sandbox_mode = "read-only"' "Codex local explorer agent config"
Assert-FileNotContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\explorer.toml") '\[agents\]' "Codex local explorer agent config"
Assert-FileNotContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\codex-agents\worker.toml") '\[agents\]' "Codex local worker agent config"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") '-MaxAgents' "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") 'CodexPreset quality' "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") 'Quality coding' "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") 'fullctx-q5' "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") 'ctk=q4_0' "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") 'context_length' "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") 'GPU layers all' "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") 'preflight line' "Codex local example README"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'Full context Q8' "Codex local example presets"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'q5_0' "Codex local example presets"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'q4_0' "Codex local example presets"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'contextLength' "Codex local example metadata defaults"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'compactLimitForContext' "Codex local example metadata defaults"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'Concurrent agents' "Codex local example presets"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'Agent max threads' "Codex local example UI"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'collectPreflightIssues' "Codex local example UI"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'GPU layers all' "Codex local example UI"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'model layers' "Codex local example GPU layer display"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") 'gpuLayersAll' "Codex local example server settings"
Assert-FileContains (Join-Path $addonRoot "src\codex\ofxGgmlLlamaCodexLocal.cpp") 'std::string\("all"\)' "Codex local server launcher"
Assert-FileContains (Join-Path $addonRoot "src\codex\ofxGgmlLlamaCodexLocal.cpp") '-ctk' "Codex local server launcher"
Assert-FileContains (Join-Path $addonRoot "src\codex\ofxGgmlLlamaCodexLocal.cpp") '-ctv' "Codex local server launcher"
Assert-FileContains (Join-Path $addonRoot "src\codex\ofxGgmlLlamaCodexLocal.cpp") 'executableHelpOutput' "Codex local server launcher help cache"
Assert-FileContains (Join-Path $addonRoot "docs\CODEX_COPILOT_LOCAL_SERVER.md") '-MaxAgents' "Codex local server docs"
Assert-FileContains (Join-Path $addonRoot "docs\CODEX_COPILOT_LOCAL_SERVER.md") '-GpuLayers all' "Codex local server docs"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.h") "ofxImGui::Gui" "Codex local example UI"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") "ImGui::Begin" "Codex local example UI"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") "model_provider=llama_cpp" "Codex local launch command"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") "web_search=" "Codex local launch command"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") "--disable apps" "Codex local launch command"
Assert-FileNotContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\src\ofApp.cpp") "--oss" "Codex local launch command"
Assert-FileContains (Join-Path $addonRoot "ofxGgmlLlamaCodexLocalExample\README.md") 'Do not add `--oss`' "Codex local example README"

foreach ($scriptName in @(
	"build-example.ps1",
	"build-llama-server.ps1",
	"doctor-llama.ps1",
	"start-llama-server.ps1",
	"stop-llama-server.ps1",
	"status-llama-server.ps1",
	"run-llama-runtime-smoke.ps1",
	"run-llama-runtime-smoke.bat",
	"run-llama-runtime-smoke.sh",
	"test-llama-runtime-smoke.ps1",
	"list-models.ps1",
	"plan-local-codex.ps1",
	"plan-local-codex.bat",
	"plan-local-codex.sh",
	"plan-local-opencode.ps1",
	"plan-local-opencode.bat",
	"plan-local-opencode.sh",
	"test-local-codex.ps1",
	"test-local-codex.bat",
	"test-local-codex.sh",
	"run-example.ps1",
	"test-doctor-llama.ps1",
	"dev\release-candidate.ps1",
	"dev\test-addon.ps1",
	"dev\test-launch-utils.ps1",
	"dev\test-release-checklist.ps1",
	"dev\test-launch-dry-run.ps1",
	"dev\test-artifact-hygiene.ps1")) {
	Assert-Path (Join-Path $scriptRoot $scriptName) "$scriptName"
}

Write-Step "Checking generated artifact hygiene"
& (Join-Path $scriptRoot "dev\test-artifact-hygiene.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Artifact hygiene failed with exit code $LASTEXITCODE"
}

Write-Step "Checking launch utility helpers"
& (Join-Path $scriptRoot "dev\test-launch-utils.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Launch utility helper tests failed with exit code $LASTEXITCODE"
}

Write-Step "Checking release checklist commands"
& (Join-Path $scriptRoot "dev\test-release-checklist.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Release checklist command tests failed with exit code $LASTEXITCODE"
}

Write-Step "Checking generated project repair"
& (Join-Path $scriptRoot "dev\test-example-project-repair.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Generated project repair tests failed with exit code $LASTEXITCODE"
}

Write-Step "Checking launch dry-runs"
& (Join-Path $scriptRoot "dev\test-launch-dry-run.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Launch dry-runs failed with exit code $LASTEXITCODE"
}

Write-Step "Checking local Codex plan"
$codexPlan = & (Join-Path $scriptRoot "plan-local-codex.ps1") -Endpoint "http://127.0.0.1:9001/v1" -Model "dry-codex-model" -Profile "ofxggml_local" -Json -SummaryOnly | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
	throw "Local Codex plan failed with exit code $LASTEXITCODE"
}
if ($codexPlan.LaunchCommand -notlike "*model_provider=llama_cpp*") {
	throw "Local Codex plan did not use llama_cpp provider override"
}
if (!$codexPlan.PSObject.Properties["ServedModels"] -or !$codexPlan.PSObject.Properties["LocalLlamaServer"]) {
	throw "Local Codex plan did not expose served model and local server process evidence"
}
if ($codexPlan.LaunchCommand -notlike "*web_search=*" -or $codexPlan.LaunchCommand -notlike "*--disable apps*") {
	throw "Local Codex plan did not include llama-server tool compatibility overrides"
}
if ($codexPlan.LaunchCommand -notlike "*agents.max_threads=1*" -or $codexPlan.LaunchCommand -notlike "*agents.max_depth=1*") {
	throw "Local Codex plan did not include local agent settings"
}
if ($codexPlan.UsesOssFlag) {
	throw "Local Codex plan unexpectedly used --oss"
}

Write-Step "Checking local OpenCode plan"
$openCodePlan = & (Join-Path $scriptRoot "plan-local-opencode.ps1") -Endpoint "http://127.0.0.1:9001/v1" -Model "dry-opencode-model" -ProviderId "llama_cpp" -Json -SummaryOnly | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
	throw "Local OpenCode plan failed with exit code $LASTEXITCODE"
}
if ($openCodePlan.FullModel -ne "llama_cpp/dry-opencode-model") {
	throw "Local OpenCode plan did not build provider/model id"
}
if ($openCodePlan.ConfigSnippet -notlike '*@ai-sdk/openai-compatible*') {
	throw "Local OpenCode plan did not use the OpenAI-compatible package"
}
if ($openCodePlan.ConfigSnippet -notlike '*http://127.0.0.1:9001/v1*') {
	throw "Local OpenCode plan did not include the local baseURL"
}
if ($openCodePlan.ConfigSnippet -notlike '*"agent":*' -or $openCodePlan.ConfigSnippet -notlike '*"explore":*') {
	throw "Local OpenCode plan did not include local agent settings"
}
if ($openCodePlan.ConfigSnippet -notlike '*"default_agent":*' -or $openCodePlan.ConfigSnippet -notlike '*"websearch":*') {
	throw "Local OpenCode plan did not include optimized local defaults"
}
if ($openCodePlan.ConfigSnippet -notlike '*"disabled_providers":*') {
	throw "Local OpenCode plan did not disable built-in cloud providers by default"
}

Write-Step "Checking local Codex exec smoke contract"
$codexSmoke = & (Join-Path $scriptRoot "test-local-codex.ps1") -Endpoint "http://127.0.0.1:9001/v1" -Model "dry-codex-model" -Profile "ofxggml_local" -DryRun -Json -SummaryOnly | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
	throw "Local Codex smoke dry-run failed with exit code $LASTEXITCODE"
}
if ($codexSmoke.Command -notlike "*codex*exec*" -or $codexSmoke.Command -notlike "*LOCAL_CODEX_OK*") {
	throw "Local Codex smoke did not build the expected codex exec marker command"
}
if ($codexSmoke.Command -notlike "*model_provider=llama_cpp*" -or $codexSmoke.Command -notlike "*web_search=*" -or $codexSmoke.Command -notlike "*--disable apps*") {
	throw "Local Codex smoke did not include llama-server tool compatibility overrides"
}
if ($codexSmoke.Command -notlike "*agents.max_threads=1*" -or $codexSmoke.Command -notlike "*agents.max_depth=1*") {
	throw "Local Codex smoke did not include local agent settings"
}
if (!$codexSmoke.PSObject.Properties["ServedModels"] -or !$codexSmoke.PSObject.Properties["LocalLlamaServer"]) {
	throw "Local Codex smoke did not include preflight model/server evidence"
}

Write-Step "Checking Codex local example build"
$codexExampleProcess = Get-Process -Name "ofxGgmlLlamaCodexLocalExample" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($codexExampleProcess) {
	Write-Warning "Skipping Codex local example build because ofxGgmlLlamaCodexLocalExample.exe is running (pid $($codexExampleProcess.Id)). Close it to compile-check this example locally."
} else {
	& (Join-Path $scriptRoot "build-example.ps1") -Example "codex" -Configuration "Release" -Platform "x64"
	if ($LASTEXITCODE -ne 0) {
		throw "Codex local example build failed with exit code $LASTEXITCODE"
	}
}

Write-Step "Checking Llama doctor"
& (Join-Path $scriptRoot "test-doctor-llama.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Llama doctor smoke test failed with exit code $LASTEXITCODE"
}

Write-Step "Checking Llama runtime smoke contract"
& (Join-Path $scriptRoot "test-llama-runtime-smoke.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Llama runtime smoke contract failed with exit code $LASTEXITCODE"
}

Write-Step "Running headless tests"
& (Join-Path $scriptRoot "dev\test-addon.ps1")
if ($LASTEXITCODE -ne 0) {
	throw "Headless tests failed with exit code $LASTEXITCODE"
}

Write-Step "ofxGgmlLlama local validation passed"
