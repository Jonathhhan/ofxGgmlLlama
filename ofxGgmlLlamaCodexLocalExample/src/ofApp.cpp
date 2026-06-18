#include "ofApp.h"

#include "imgui_stdlib.h"
#include "model/ofxGgmlModel.h"

#include <algorithm>
#include <exception>
#include <limits>
#include <memory>
#include <sstream>
#include <thread>

namespace {
constexpr const char * LogModule = "ofxGgmlLlamaCodexLocalExample";
constexpr const char * DefaultCodexModelAlias = "local/Qwen3.6-27B-Q4_0";
constexpr const char * WorkspaceWriteSandbox = "workspace-write";

struct CodexLocalPreset {
	const char * id;
	const char * label;
	int contextSize;
	int parallel;
	int batchSize;
	int ubatchSize;
	int threads;
	int threadsBatch;
	int threadsHttp;
	int cacheReuse;
	const char * kvCacheKeyType;
	const char * kvCacheValueType;
	int modelContextWindow;
	int modelAutoCompactTokenLimit;
	int toolOutputTokenLimit;
	int agentMaxConcurrentThreads;
	int agentMaxDepth;
	int agentMinWaitMs;
	int agentMaxWaitMs;
	int agentDefaultWaitMs;
	int startupTimeoutSeconds;
	float temperature;
	float topP;
	float minP;
};

const std::vector<CodexLocalPreset> & codexLocalPresets() {
	static const std::vector<CodexLocalPreset> presets {
		{"default", "Default local", 32768, 1, 2048, 512, 0, 0, 0, 256, "", "", 32768, 24000, 5000, 0, 0, 2500, 120000, 30000, 300, 0.2f, 0.85f, 0.03f},
		{"qwen27b-3090", "Qwen 27B RTX 3090", 65536, 1, 1024, 256, 0, 0, 0, 256, "q4_0", "q4_0", 65536, 56000, 12000, 1, 0, 2500, 180000, 30000, 600, 0.2f, 0.85f, 0.03f},
		{"unsloth-glm-24gb", "Unsloth GLM 24GB", 131072, 1, 4096, 1024, 0, 0, 0, 512, "q8_0", "q8_0", 131072, 110000, 12000, 1, 0, 5000, 240000, 30000, 600, 1.0f, 0.95f, 0.01f},
		{"hermes-codex-shared", "Hermes + Codex shared", 65536, 2, 1024, 256, 0, 0, 0, 256, "q4_0", "q4_0", 65536, 52000, 8000, 2, 0, 2500, 180000, 30000, 600, 0.2f, 0.85f, 0.03f},
		{"rtx4090", "Qwen 27B RTX 4090", 65536, 1, 2048, 512, 0, 0, 0, 256, "q4_0", "q4_0", 65536, 56000, 12000, 1, 0, 2500, 180000, 30000, 600, 0.2f, 0.85f, 0.03f},
		{"fast", "Fast coding", 32768, 1, 4096, 1024, 0, 0, 0, 256, "", "", 32768, 24000, 5000, 0, 0, 2500, 120000, 30000, 300, 0.2f, 0.85f, 0.03f},
		{"balanced", "Balanced local", 40960, 1, 2048, 512, 0, 0, 0, 256, "", "", 40960, 30000, 5000, 0, 0, 2500, 120000, 30000, 300, 0.25f, 0.85f, 0.03f},
		{"quality", "Quality coding", 262144, 1, 3072, 768, 0, 0, 0, 256, "", "", 262144, 220000, 12000, 0, 0, 2500, 180000, 30000, 600, 0.15f, 0.85f, 0.03f},
		{"fullctx", "Full context Q8", 0, 1, 2048, 512, 0, 0, 0, 512, "q8_0", "q8_0", 262144, 220000, 12000, 0, 0, 5000, 240000, 30000, 600, 0.15f, 0.85f, 0.03f},
		{"fullctx-q5", "Full context Q5", 0, 1, 2048, 512, 0, 0, 0, 512, "q5_0", "q5_0", 262144, 220000, 12000, 0, 0, 5000, 240000, 30000, 600, 0.15f, 0.85f, 0.03f},
		{"fullctx-q4", "Full context Q4", 0, 1, 1536, 384, 0, 0, 0, 512, "q4_0", "q4_0", 262144, 220000, 12000, 0, 0, 5000, 240000, 30000, 600, 0.15f, 0.85f, 0.03f},
		{"long", "Long context", 262144, 1, 4096, 1024, 0, 0, 0, 512, "", "", 262144, 220000, 12000, 0, 0, 5000, 300000, 30000, 600, 0.2f, 0.85f, 0.03f},
		{"concurrent", "Concurrent agents", 65536, 2, 2048, 512, 0, 0, 0, 256, "", "", 32768, 24000, 5000, 2, 0, 2500, 180000, 30000, 600, 0.15f, 0.85f, 0.03f}
	};
	return presets;
}

const std::vector<const char *> & codexReasoningEfforts() {
	static const std::vector<const char *> efforts {
		"minimal",
		"low",
		"medium",
		"high"
	};
	return efforts;
}

const std::vector<const char *> & codexWebSearchModes() {
	static const std::vector<const char *> modes {
		"live",
		"disabled"
	};
	return modes;
}

const std::vector<const char *> & codexProviderModes() {
	static const std::vector<const char *> modes {
		"Local llama.cpp",
		"OpenAI profile",
		"Hybrid: local agents",
		"OpenAI + local Hermes"
	};
	return modes;
}

bool isLocalCodexProviderMode(int mode) {
	return mode == 0;
}

bool usesLocalCodexProvider(int mode) {
	return mode == 0 || mode == 2;
}

bool usesOpenAiCodexLaunch(int mode) {
	return mode == 1 || mode == 2 || mode == 3;
}

bool usesLlamaCppCodexProvider(int mode) {
	return mode == 0 || mode == 2 || mode == 3;
}

bool usesLocalHermesEndpoint(int mode) {
	return mode == 0 || mode == 2 || mode == 3;
}

std::string defaultBaseUrlForProviderMode(int mode) {
	(void)mode;
	return "http://127.0.0.1:8001/v1";
}

std::string defaultModelForProviderMode(int mode) {
	(void)mode;
	return DefaultCodexModelAlias;
}

std::string providerIdForMode(int mode) {
	(void)mode;
	return "llama_cpp";
}

std::string providerNameForMode(int mode) {
	(void)mode;
	return "llama.cpp local";
}

std::string profileForMode(int mode) {
	(void)mode;
	return "ofxggml_local";
}

std::string defaultSandboxForProviderMode(int mode) {
	return isLocalCodexProviderMode(mode) ? WorkspaceWriteSandbox : "";
}

int codexProviderModeFromValue(const std::string & value) {
	auto lower = value;
	std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
		return static_cast<char>(std::tolower(c));
	});
	if (lower == "openai" || lower == "cloud" || lower == "profile") {
		return 1;
	}
	if (lower == "hybrid" || lower == "mixed" || lower == "local-agents") {
		return 2;
	}
	if (lower == "openai-hermes" || lower == "cloud-hermes" || lower == "local-hermes") {
		return 3;
	}
	return 0;
}

int reasoningEffortIndexFromValue(const std::string & value) {
	const auto & efforts = codexReasoningEfforts();
	for (std::size_t i = 0; i < efforts.size(); ++i) {
		if (value == efforts[i]) {
			return static_cast<int>(i);
		}
	}
	return 2;
}

const char * reasoningEffortFromIndex(int index) {
	const auto & efforts = codexReasoningEfforts();
	if (index < 0 || index >= static_cast<int>(efforts.size())) {
		return efforts[2];
	}
	return efforts[static_cast<std::size_t>(index)];
}

const std::vector<const char *> & specTypes() {
	static const std::vector<const char *> types {
		"",
		"none",
		"draft-simple",
		"draft-eagle3",
		"draft-mtp",
		"ngram-simple",
		"ngram-map-k",
		"ngram-map-k4v",
		"ngram-mod",
		"ngram-cache"
	};
	return types;
}

const std::vector<const char *> & kvCacheTypes() {
	static const std::vector<const char *> types {
		"",
		"f32",
		"f16",
		"bf16",
		"q8_0",
		"q4_0",
		"q4_1",
		"iq4_nl",
		"q5_0",
		"q5_1"
	};
	return types;
}

bool drawStringCombo(
	const char * label,
	std::string & value,
	const std::vector<const char *> & options) {
	const auto preview = value.empty() ? "default" : value.c_str();
	bool changed = false;
	if (ImGui::BeginCombo(label, preview)) {
		for (const auto * option : options) {
			const bool isDefault = option[0] == '\0';
			const auto optionLabel = isDefault ? "default" : option;
			const bool selected = value == option;
			if (ImGui::Selectable(optionLabel, selected)) {
				value = option;
				changed = true;
			}
			if (selected) {
				ImGui::SetItemDefaultFocus();
			}
		}
		ImGui::EndCombo();
	}
	return changed;
}

int presetIndexFromId(const std::string & value) {
	const auto & presets = codexLocalPresets();
	for (std::size_t i = 0; i < presets.size(); ++i) {
		if (value == presets[i].id || value == presets[i].label) {
			return static_cast<int>(i);
		}
	}
	return 1;
}

void appendWrapped(
	std::vector<std::string> & lines,
	const std::string & text,
	std::size_t maxChars) {
	if (text.size() <= maxChars) {
		lines.push_back(text);
		return;
	}

	std::string line;
	std::istringstream words(text);
	std::string word;
	while (words >> word) {
		if (!line.empty() && line.size() + word.size() + 1 > maxChars) {
			lines.push_back(line);
			line.clear();
		}
		if (!line.empty()) {
			line += " ";
		}
		line += word;
	}
	if (!line.empty()) {
		lines.push_back(line);
	}
}

std::string quoteCommandArgument(const std::string & value) {
	if (value.empty()) {
		return "\"\"";
	}
	if (value.find_first_of(" \t\"'") == std::string::npos) {
		return value;
	}
	std::string quoted = "\"";
	for (const auto c : value) {
		if (c == '"') {
			quoted += "\\\"";
		} else {
			quoted += c;
		}
	}
	quoted += "\"";
	return quoted;
}

void appendCommandArgument(
	std::vector<std::string> & arguments,
	const std::string & name,
	const std::string & value) {
	if (value.empty()) {
		return;
	}
	arguments.push_back(name);
	arguments.push_back(value);
}

std::string tomlString(const std::string & value) {
	std::string escaped;
	escaped.reserve(value.size() + 2);
	escaped.push_back('"');
	for (const auto c : value) {
		if (c == '\\' || c == '"') {
			escaped.push_back('\\');
		}
		escaped.push_back(c);
	}
	escaped.push_back('"');
	return escaped;
}

void appendCodexConfigOverride(
	std::vector<std::string> & arguments,
	const std::string & value) {
	arguments.push_back("-c");
	arguments.push_back(value);
}

std::string joinCodexArguments(const std::vector<std::string> & arguments) {
	std::ostringstream command;
	for (std::size_t i = 0; i < arguments.size(); ++i) {
		if (i > 0) {
			command << " ";
		}
		command << ofxGgmlLlamaCodexLocal::quoteArgument(arguments[i]);
	}
	return command.str();
}

std::string chooseFile(const std::string & title, const std::string & currentPath) {
	const auto startPath = currentPath.empty() ? ofToDataPath("", true) : currentPath;
	auto result = ofSystemLoadDialog(title, false, startPath);
	return result.bSuccess ? result.getPath() : std::string();
}

int envInt(const char * name, int fallback) {
	const auto value = ofxGgmlLlamaCodexLocal::envValue(name);
	if (value.empty()) {
		return fallback;
	}
	try {
		return std::stoi(value);
	} catch (...) {
		return fallback;
	}
}

bool hasEnvValue(const char * name) {
	return !ofxGgmlLlamaCodexLocal::envValue(name).empty();
}

int compactLimitForContext(int contextWindow) {
	if (contextWindow <= 0) {
		return 0;
	}
	const auto compactLimit = (static_cast<int64_t>(contextWindow) * 85) / 100;
	return static_cast<int>(std::min<int64_t>(
		std::max<int64_t>(2048, compactLimit),
		std::numeric_limits<int>::max()));
}

float envFloat(const char * name, float fallback) {
	const auto value = ofxGgmlLlamaCodexLocal::envValue(name);
	if (value.empty()) {
		return fallback;
	}
	try {
		return std::stof(value);
	} catch (...) {
		return fallback;
	}
}

bool envBool(const char * name, bool fallback) {
	const auto value = ofxGgmlLlamaCodexLocal::envValue(name);
	if (value.empty()) {
		return fallback;
	}
	return value != "0" && value != "false" && value != "False";
}

bool envGpuLayersAll(const char * name, bool fallback) {
	const auto value = ofxGgmlLlamaCodexLocal::envValue(name);
	if (value.empty()) {
		return fallback;
	}
	if (value == "all" || value == "ALL" || value == "All") {
		return true;
	}
	return false;
}

std::string joinAliases(const std::vector<std::string> & values) {
	std::ostringstream output;
	for (std::size_t i = 0; i < values.size(); ++i) {
		if (i > 0) {
			output << ", ";
		}
		output << values[i];
	}
	return output.str();
}

std::string joinIssues(const std::vector<std::string> & values) {
	std::ostringstream output;
	for (std::size_t i = 0; i < values.size(); ++i) {
		if (i > 0) {
			output << "; ";
		}
		output << values[i];
	}
	return output.str();
}

}

void ofApp::setup() {
	ofSetWindowTitle("ofxGgmlLlama Codex Local");
	gui.setup();

	presetIndex = presetIndexFromId(
		ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_CODEX_PRESET", "qwen27b-3090"));
	applyPreset(presetIndex);
	codexProviderMode = codexProviderModeFromValue(
		ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_CODEX_PROVIDER", "local"));

	baseUrl = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_BASE_URL",
		defaultBaseUrlForProviderMode(codexProviderMode));
	serverUrl = ofxGgmlLlamaCodexLocal::serverRootFromBaseUrl(baseUrl);
	modelPath = ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_TEXT_MODEL", "");
	modelAlias = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_MODEL",
		defaultModelForProviderMode(codexProviderMode));
	openAiModelAlias = ofxGgmlLlamaCodexLocal::envValue("OFXGGML_CODEX_OPENAI_MODEL");
	if (openAiModelAlias.empty() && !usesLocalCodexProvider(codexProviderMode)) {
		openAiModelAlias = ofxGgmlLlamaCodexLocal::envValue("OFXGGML_CODEX_MODEL");
	}
	if (openAiModelAlias.empty()) {
		openAiModelAlias = "gpt-5";
	}
	serverExe = ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_LLAMA_SERVER_EXE", "");
	codexExe = ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_CODEX_EXE", "");
	codexProfile = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_PROFILE",
		isLocalCodexProviderMode(codexProviderMode) ? profileForMode(codexProviderMode) : "");
	codexSandboxManuallyEdited = hasEnvValue("OFXGGML_CODEX_SANDBOX");
	codexSandbox = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_SANDBOX",
		defaultSandboxForProviderMode(codexProviderMode));
	configPath = ofxGgmlLlamaCodexLocal::resolveCodexConfigPath();
	gpuLayersAll = envGpuLayersAll("OFXGGML_CODEX_GPU_LAYERS", gpuLayersAll);
	gpuLayers = envInt("OFXGGML_CODEX_GPU_LAYERS", gpuLayers);
	contextSize = envInt("OFXGGML_CODEX_CONTEXT_SIZE", contextSize);
	parallel = envInt("OFXGGML_CODEX_PARALLEL", parallel);
	batchSize = envInt("OFXGGML_CODEX_BATCH_SIZE", batchSize);
	ubatchSize = envInt("OFXGGML_CODEX_UBATCH_SIZE", ubatchSize);
	threads = envInt("OFXGGML_CODEX_THREADS", threads);
	threadsBatch = envInt("OFXGGML_CODEX_THREADS_BATCH", threadsBatch);
	threadsHttp = envInt("OFXGGML_CODEX_THREADS_HTTP", threadsHttp);
	cacheReuse = envInt("OFXGGML_CODEX_CACHE_REUSE", cacheReuse);
	kvCacheKeyType = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_KV_CACHE_KEY_TYPE",
		kvCacheKeyType);
	kvCacheValueType = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_KV_CACHE_VALUE_TYPE",
		kvCacheValueType);
	specType = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_SPEC_TYPE",
		specType);
	draftModelPath = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_DRAFT_MODEL",
		draftModelPath);
	draftGpuLayers = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_DRAFT_GPU_LAYERS",
		draftGpuLayers);
	draftMaxTokens = envInt("OFXGGML_CODEX_DRAFT_MAX_TOKENS", draftMaxTokens);
	draftMinTokens = envInt("OFXGGML_CODEX_DRAFT_MIN_TOKENS", draftMinTokens);
	draftPSplit = envFloat("OFXGGML_CODEX_DRAFT_P_SPLIT", draftPSplit);
	draftPMin = envFloat("OFXGGML_CODEX_DRAFT_P_MIN", draftPMin);
	webSearch = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_WEB_SEARCH",
		webSearch);
	modelContextWindowManuallyEdited = hasEnvValue("OFXGGML_CODEX_MODEL_CONTEXT_WINDOW");
	modelContextWindow = envInt("OFXGGML_CODEX_MODEL_CONTEXT_WINDOW", modelContextWindow);
	modelAutoCompactManuallyEdited = hasEnvValue("OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT");
	modelAutoCompactTokenLimit = envInt(
		"OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT",
		modelAutoCompactTokenLimit);
	toolOutputTokenLimit = envInt("OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT", toolOutputTokenLimit);
	agentMaxConcurrentThreadsPerSession = envInt(
		"OFXGGML_CODEX_AGENT_MAX_AGENTS",
		agentMaxConcurrentThreadsPerSession);
	agentMaxConcurrentThreadsPerSession = envInt(
		"OFXGGML_CODEX_AGENT_MAX_THREADS",
		agentMaxConcurrentThreadsPerSession);
	agentMaxConcurrentThreadsPerSession = envInt(
		"OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS",
		agentMaxConcurrentThreadsPerSession);
	const bool hasAgentThreadEnv =
		hasEnvValue("OFXGGML_CODEX_AGENT_MAX_AGENTS") ||
		hasEnvValue("OFXGGML_CODEX_AGENT_MAX_THREADS") ||
		hasEnvValue("OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS");
	agentMaxDepth = envInt("OFXGGML_CODEX_AGENT_MAX_DEPTH", agentMaxDepth);
	applyInteractiveThreadBudget(
		!hasAgentThreadEnv,
		!hasEnvValue("OFXGGML_CODEX_THREADS"),
		!hasEnvValue("OFXGGML_CODEX_THREADS_BATCH"),
		!hasEnvValue("OFXGGML_CODEX_THREADS_HTTP"));
	agentMinWaitTimeoutMs = envInt("OFXGGML_CODEX_AGENT_MIN_WAIT_MS", agentMinWaitTimeoutMs);
	agentMaxWaitTimeoutMs = envInt("OFXGGML_CODEX_AGENT_MAX_WAIT_MS", agentMaxWaitTimeoutMs);
	agentDefaultWaitTimeoutMs = envInt(
		"OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS",
		agentDefaultWaitTimeoutMs);
	reasoningEffortIndex = reasoningEffortIndexFromValue(
		ofxGgmlLlamaCodexLocal::getEnvOrDefault(
			"OFXGGML_CODEX_REASONING_EFFORT",
			reasoningEffortFromIndex(reasoningEffortIndex)));
	startupTimeoutSeconds = envInt("OFXGGML_CODEX_STARTUP_TIMEOUT", startupTimeoutSeconds);
	temperature = envFloat("OFXGGML_CODEX_TEMP", temperature);
	topP = envFloat("OFXGGML_CODEX_TOP_P", topP);
	minP = envFloat("OFXGGML_CODEX_MIN_P", minP);
	noCudaGraphs = envBool("OFXGGML_CODEX_NO_CUDA_GRAPHS", noCudaGraphs);
	skipChatParsing = envBool("OFXGGML_CODEX_SKIP_CHAT_PARSING", skipChatParsing);
	autoConfig = envBool("OFXGGML_CODEX_AUTO_CONFIG", autoConfig);

	refreshRuntimeDiscovery();
	if (modelAlias.empty()) {
		modelAlias = ofxGgmlLlamaCodexLocal::modelAliasFromPath(modelPath);
	}
	refreshModelMetadata();
	status = "ready";
	wireApiProbeStatus = "wire_api defaults to responses";
	rebuildLines();
	refreshServerStatus();
}

void ofApp::draw() {
	ofBackground(18, 20, 24);

	bool startRequested = false;
	bool forceStartRequested = false;
	bool smokeRequested = false;
	bool writeConfigRequested = false;
	bool launchRequested = false;
	bool refreshRequested = false;
	bool adoptServedAliasRequested = false;
	bool copyConfigRequested = false;
	bool copyHermesConfigRequested = false;
	bool copyServerCommandRequested = false;
	bool copyLaunchCommandRequested = false;
	bool writeHermesConfigRequested = false;

	gui.begin();
	if (ImGui::Begin("OpenAI Codex + local llama-server")) {
		std::lock_guard<std::mutex> lock(stateMutex);
		bool settingsChanged = false;
		ImGui::TextWrapped("%s", status.empty() ? "ready" : status.c_str());
		const auto serverPreflightIssues = collectPreflightIssues(true, false);
		const auto launchPreflightIssues = collectPreflightIssues(false, true);
		preflightStatus = formatPreflightSummary(launchPreflightIssues);
		ImGui::TextWrapped("%s", preflightStatus.c_str());
		ImGui::Separator();

		if (ImGui::Combo(
				"Codex provider",
				&codexProviderMode,
				codexProviderModes().data(),
				static_cast<int>(codexProviderModes().size()))) {
			if (isLocalCodexProviderMode(codexProviderMode) && codexProfile.empty()) {
				codexProfile = profileForMode(codexProviderMode);
			} else if (usesOpenAiCodexLaunch(codexProviderMode) && codexProfile == "ofxggml_local") {
				codexProfile.clear();
			}
			if (baseUrl == "http://127.0.0.1:8001/v1") {
				baseUrl = defaultBaseUrlForProviderMode(codexProviderMode);
				serverUrl = ofxGgmlLlamaCodexLocal::serverRootFromBaseUrl(baseUrl);
			}
			if (modelAlias == DefaultCodexModelAlias) {
				modelAlias = defaultModelForProviderMode(codexProviderMode);
				modelAliasManuallyEdited = false;
			}
			if (!codexSandboxManuallyEdited) {
				codexSandbox = defaultSandboxForProviderMode(codexProviderMode);
			}
			rebuildLines();
		}
		const bool localProviderMode = usesLocalCodexProvider(codexProviderMode);
		const bool llamaCppProviderMode = usesLlamaCppCodexProvider(codexProviderMode);
		const bool openAiLaunchMode = usesOpenAiCodexLaunch(codexProviderMode);
		const bool localHermesEndpointMode = usesLocalHermesEndpoint(codexProviderMode);
		ImGui::BeginDisabled(!localHermesEndpointMode);
		if (ImGui::InputText("Codex base URL", &baseUrl)) {
			serverUrl = ofxGgmlLlamaCodexLocal::serverRootFromBaseUrl(baseUrl);
			rebuildLines();
		}
		if (ImGui::InputText("llama-server root", &serverUrl)) {
			baseUrl = ofxGgmlLlamaCodexLocal::baseUrlFromServerRoot(serverUrl);
			rebuildLines();
		}
		if (ImGui::InputText("Model alias", &modelAlias)) {
			modelAliasManuallyEdited = true;
			rebuildLines();
		}
		ImGui::SameLine();
		ImGui::BeginDisabled(servedModelAliases.empty() || !localHermesEndpointMode);
		adoptServedAliasRequested = ImGui::Button("Use served alias");
		ImGui::EndDisabled();
		ImGui::EndDisabled();
		ImGui::BeginDisabled(!openAiLaunchMode);
		if (ImGui::InputText("OpenAI model", &openAiModelAlias)) {
			rebuildLines();
		}
		ImGui::EndDisabled();
		ImGui::BeginDisabled(!llamaCppProviderMode);
		const auto previousModelPath = modelPath;
		if (ImGui::InputText("GGUF model", &modelPath)) {
			refreshModelAliasForPath(previousModelPath);
			refreshModelMetadata();
			rebuildLines();
		}
		ImGui::SameLine();
		if (ImGui::Button("Choose model")) {
			const auto selected = chooseFile("Choose GGUF model", modelPath);
			if (!selected.empty()) {
				modelPath = selected;
				modelAlias = ofxGgmlLlamaCodexLocal::modelAliasFromPath(modelPath);
				modelAliasManuallyEdited = false;
				refreshModelMetadata();
				rebuildLines();
			}
		}
		if (ImGui::InputText("llama-server path", &serverExe)) {
			rebuildLines();
		}
		ImGui::SameLine();
		if (ImGui::Button("Choose server")) {
			const auto selected = chooseFile("Choose llama-server executable", serverExe);
			if (!selected.empty()) {
				serverExe = selected;
				rebuildLines();
			}
		}
		ImGui::EndDisabled();
		if (ImGui::InputText("Codex executable", &codexExe)) {
			rebuildLines();
		}
		if (ImGui::InputText("Codex profile", &codexProfile)) {
			rebuildLines();
		}
		if (ImGui::InputText("Codex sandbox", &codexSandbox)) {
			codexSandboxManuallyEdited = true;
			rebuildLines();
		}
		ImGui::InputText("Codex config", &configPath);

		ImGui::Separator();
		const auto & presets = codexLocalPresets();
		std::vector<const char *> presetLabels;
		presetLabels.reserve(presets.size());
		for (const auto & preset : presets) {
			presetLabels.push_back(preset.label);
		}
		ImGui::Combo(
			"Preset",
			&presetIndex,
			presetLabels.data(),
			static_cast<int>(presetLabels.size()));
		ImGui::SameLine();
		if (ImGui::Button("Apply preset")) {
			applyPreset(presetIndex);
			rebuildLines();
		}
		if (ImGui::Checkbox("GPU layers all", &gpuLayersAll)) {
			settingsChanged = true;
		}
		if (gpuLayersAll) {
			ImGui::SameLine();
			if (modelLayerCount > 0) {
				ImGui::TextDisabled(
					"(%llu model layers)",
					static_cast<unsigned long long>(modelLayerCount));
			} else {
				ImGui::TextDisabled("(model layer count unknown)");
			}
		}
		ImGui::BeginDisabled(gpuLayersAll);
		if (ImGui::InputInt("GPU layers", &gpuLayers)) {
			settingsChanged = true;
		}
		ImGui::EndDisabled();
		if (ImGui::InputInt("Context size", &contextSize)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Parallel", &parallel)) {
			applyInteractiveThreadBudget(true, true, true, true);
			settingsChanged = true;
		}
		if (ImGui::InputInt("Batch size", &batchSize)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("UBatch size", &ubatchSize)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Threads (0 auto)", &threads)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Batch threads (0 auto)", &threadsBatch)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("HTTP threads (0 auto)", &threadsHttp)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Cache reuse tokens", &cacheReuse)) {
			settingsChanged = true;
		}
		if (drawStringCombo("KV cache K type", kvCacheKeyType, kvCacheTypes())) {
			settingsChanged = true;
		}
		if (drawStringCombo("KV cache V type", kvCacheValueType, kvCacheTypes())) {
			settingsChanged = true;
		}
		if (drawStringCombo("Spec type", specType, specTypes())) {
			settingsChanged = true;
		}
		if (ImGui::InputText("Draft model", &draftModelPath)) {
			settingsChanged = true;
		}
		ImGui::SameLine();
		if (ImGui::Button("Choose draft model")) {
			const auto selected = chooseFile("Choose speculative decoding draft GGUF", draftModelPath);
			if (!selected.empty()) {
				draftModelPath = selected;
				settingsChanged = true;
			}
		}
		if (ImGui::InputText("Draft GPU layers", &draftGpuLayers)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Draft max tokens", &draftMaxTokens)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Draft min tokens", &draftMinTokens)) {
			settingsChanged = true;
		}
		if (ImGui::InputFloat("Draft split probability", &draftPSplit, 0.01f, 0.10f, "%.3f")) {
			settingsChanged = true;
		}
		if (ImGui::InputFloat("Draft min probability", &draftPMin, 0.01f, 0.10f, "%.3f")) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Model context window", &modelContextWindow)) {
			modelContextWindowManuallyEdited = true;
			settingsChanged = true;
		}
		if (ImGui::InputInt("Auto compact tokens", &modelAutoCompactTokenLimit)) {
			modelAutoCompactManuallyEdited = true;
			settingsChanged = true;
		}
		if (ImGui::InputInt("Tool output tokens", &toolOutputTokenLimit)) {
			settingsChanged = true;
		}
		if (drawStringCombo("Web search", webSearch, codexWebSearchModes())) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Startup timeout seconds", &startupTimeoutSeconds)) {
			settingsChanged = true;
		}
		if (ImGui::SliderFloat("Temperature", &temperature, 0.0f, 2.0f, "%.2f")) {
			settingsChanged = true;
		}
		if (ImGui::SliderFloat("Top P", &topP, 0.05f, 1.0f, "%.2f")) {
			settingsChanged = true;
		}
		if (ImGui::SliderFloat("Min P", &minP, 0.0f, 0.2f, "%.3f")) {
			settingsChanged = true;
		}
		ImGui::Separator();
		ImGui::TextUnformatted("Agent settings");
		if (ImGui::InputInt("Agent max threads (0 auto)", &agentMaxConcurrentThreadsPerSession)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Agent max depth (0 auto)", &agentMaxDepth)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Agent min wait ms", &agentMinWaitTimeoutMs)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Agent max wait ms", &agentMaxWaitTimeoutMs)) {
			settingsChanged = true;
		}
		if (ImGui::InputInt("Agent default wait ms", &agentDefaultWaitTimeoutMs)) {
			settingsChanged = true;
		}
		if (ImGui::Combo(
				"Reasoning effort",
				&reasoningEffortIndex,
				codexReasoningEfforts().data(),
				static_cast<int>(codexReasoningEfforts().size()))) {
			settingsChanged = true;
		}
		if (ImGui::Checkbox("No CUDA graphs", &noCudaGraphs)) {
			settingsChanged = true;
		}
		if (ImGui::Checkbox("Skip chat parsing", &skipChatParsing)) {
			settingsChanged = true;
		}
		ImGui::BeginDisabled(!localProviderMode);
		if (ImGui::Checkbox("Auto-write Codex config", &autoConfig)) {
			settingsChanged = true;
		}
		ImGui::EndDisabled();
		if (settingsChanged) {
			rebuildLines();
		}

		ImGui::Separator();
		const bool blockServerActions = running || !llamaCppProviderMode || !serverPreflightIssues.empty();
		const bool blockSmoke = running || !localHermesEndpointMode || modelAlias.empty() || baseUrl.empty();
		const bool blockConfigWrite = running || !localProviderMode || modelAlias.empty() || configPath.empty();
		const bool blockLaunch = running || !launchPreflightIssues.empty();
		ImGui::BeginDisabled(blockServerActions);
		startRequested = ImGui::Button("Start server");
		ImGui::SameLine();
		forceStartRequested = ImGui::Button("Force new");
		ImGui::EndDisabled();
		ImGui::SameLine();
		ImGui::BeginDisabled(blockSmoke);
		smokeRequested = ImGui::Button("Smoke endpoint");
		ImGui::EndDisabled();
		ImGui::SameLine();
		ImGui::BeginDisabled(blockConfigWrite);
		writeConfigRequested = ImGui::Button("Write config");
		ImGui::EndDisabled();
		ImGui::SameLine();
		ImGui::BeginDisabled(blockLaunch);
		launchRequested = ImGui::Button("Launch Codex");
		ImGui::EndDisabled();
		ImGui::SameLine();
		refreshRequested = ImGui::Button("Refresh");
		ImGui::BeginDisabled(!localProviderMode || modelAlias.empty());
		copyConfigRequested = ImGui::Button("Copy config");
		ImGui::EndDisabled();
		ImGui::SameLine();
		ImGui::BeginDisabled(!localHermesEndpointMode || modelAlias.empty() || baseUrl.empty());
		copyHermesConfigRequested = ImGui::Button("Copy Hermes config");
		ImGui::EndDisabled();
		ImGui::SameLine();
		ImGui::BeginDisabled(!localHermesEndpointMode || modelAlias.empty() || baseUrl.empty());
		writeHermesConfigRequested = ImGui::Button("Write Hermes config");
		ImGui::EndDisabled();
		ImGui::SameLine();
		ImGui::BeginDisabled(!llamaCppProviderMode || modelPath.empty());
		copyServerCommandRequested = ImGui::Button("Copy server command");
		ImGui::EndDisabled();
		ImGui::SameLine();
		copyLaunchCommandRequested = ImGui::Button("Copy launch command");
		if (copyConfigRequested) {
			copyTextToClipboard("Codex config snippet", buildCodexConfigSnippetText());
		}
		if (copyHermesConfigRequested) {
			copyTextToClipboard("Hermes custom endpoint snippet", buildHermesConfigSnippetText());
		}
		if (copyServerCommandRequested) {
			copyTextToClipboard("manual server command", buildManualServerCommand());
		}
		if (copyLaunchCommandRequested) {
			copyTextToClipboard("Codex launch command", buildCodexLaunchCommand());
		}

		ImGui::Separator();
		ImGui::Text("server: %s", serverReady ? "ready" : "not ready");
		ImGui::Text("endpoint: %s", endpointReady ? "ready" : "not ready");
		ImGui::TextWrapped("wire_api: %s", wireApi.empty() ? "(not detected)" : wireApi.c_str());
		ImGui::TextWrapped("%s", wireApiProbeStatus.c_str());
		ImGui::TextWrapped("%s", servedModelStatus.c_str());
		ImGui::TextWrapped("%s", endpointStatus.c_str());
		if (!endpointOutput.empty()) {
			ImGui::TextWrapped("endpoint output: %s", endpointOutput.c_str());
		}
		ImGui::TextWrapped("%s", configWriteStatus.c_str());
		ImGui::TextWrapped("%s", hermesConfigWriteStatus.c_str());

		ImGui::Separator();
		for (const auto & line : lines) {
			ImGui::TextWrapped("%s", line.c_str());
		}
	}
	ImGui::End();
	gui.end();

	if (refreshRequested) {
		refreshRuntimeDiscovery();
		refreshServerStatus();
	}
	if (adoptServedAliasRequested) {
		adoptServedModelAliasIfNeeded();
	}
	if (writeConfigRequested) {
		requestWriteConfig();
	}
	if (writeHermesConfigRequested) {
		syncHermesConfig();
		refreshRuntimeDiscovery();
	}
	if (startRequested) {
		requestStartServer(false);
	}
	if (forceStartRequested) {
		requestStartServer(true);
	}
	if (smokeRequested) {
		requestEndpointSmoke();
	}
	if (launchRequested) {
		requestLaunchCodex();
	}
}

void ofApp::keyPressed(int key) {
	if (key == 'r' || key == 'R') {
		refreshRuntimeDiscovery();
		refreshServerStatus();
	}
	if (key == 's' || key == 'S') {
		requestStartServer(false);
	}
}

void ofApp::exit() {
	cancelRequested = true;
	joinWorker();
}

void ofApp::requestStartServer(bool force) {
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		if (running) {
			status = "another operation is already running";
			return;
		}
		running = true;
		cancelRequested = false;
		serverReady = false;
		status = force ? "starting a new llama-server..." : "checking llama-server...";
	}
	joinWorker();
	worker = std::thread(&ofApp::runStartServerWorker, this, force);
}

void ofApp::runStartServerWorker(bool force) {
	const auto settings = makeServerSettings();
	int requestStartupTimeout = 300;
	bool requestAutoConfig = false;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestStartupTimeout = startupTimeoutSeconds;
		requestAutoConfig = autoConfig;
	}
	if (!force) {
		const auto existing = ofxGgmlLlamaCodexLocal::probeServerHealth(settings.serverUrl, 2);
		if (existing.ready) {
			if (requestAutoConfig) {
				syncCodexConfig();
			}
			std::lock_guard<std::mutex> lock(stateMutex);
			serverReady = true;
			status = "llama-server is already ready at " + settings.serverUrl;
			running = false;
			return;
		}
	}

	if (!ofxGgmlLlamaCodexLocal::fileExists(settings.serverExe)) {
		std::lock_guard<std::mutex> lock(stateMutex);
		status = "llama-server executable not found";
		running = false;
		return;
	}
	if (!ofxGgmlLlamaCodexLocal::fileExists(settings.modelPath)) {
		std::lock_guard<std::mutex> lock(stateMutex);
		status = "GGUF model not found";
		running = false;
		return;
	}

	if (!ofxGgmlLlamaCodexLocal::startLlamaServer(settings)) {
		std::lock_guard<std::mutex> lock(stateMutex);
		status = "failed to launch llama-server";
		running = false;
		return;
	}

	const auto probe = ofxGgmlLlamaCodexLocal::waitForServerReady(
		settings.serverUrl,
		requestStartupTimeout,
		[this]() { return cancelRequested.load(); });
	if (probe.ready && requestAutoConfig) {
		syncCodexConfig();
	}
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		serverReady = probe.ready;
		status = probe.ready
			? "llama-server ready for Codex at " + baseUrl
			: "llama-server did not become ready (" + ofxGgmlLlamaCodexLocal::describeProbe(probe) + ")";
		running = false;
	}
}

void ofApp::requestEndpointSmoke() {
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		if (running) {
			endpointStatus = "another operation is already running";
			return;
		}
		running = true;
		cancelRequested = false;
		endpointReady = false;
		endpointOutput.clear();
		endpointStatus = "testing OpenAI-compatible endpoint...";
	}
	joinWorker();
	worker = std::thread(&ofApp::runEndpointSmokeWorker, this);
}

void ofApp::runEndpointSmokeWorker() {
	std::string requestBaseUrl;
	std::string requestModelAlias;
	float requestTemperature = 0.0f;
	float requestTopP = 0.0f;
	bool requestAutoConfig = false;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestBaseUrl = baseUrl;
		requestModelAlias = modelAlias;
		requestTemperature = temperature;
		requestTopP = topP;
		requestAutoConfig = autoConfig;
	}

	ofxGgmlTextGenerationSettings requestSettings;
	requestSettings.useServerBackend = true;
	requestSettings.serverUrl = requestBaseUrl;
	requestSettings.serverModel = requestModelAlias;
	requestSettings.maxTokens = 24;
	requestSettings.temperature = std::max(0.0f, requestTemperature);
	requestSettings.topP = std::max(0.1f, requestTopP);
	requestSettings.stream = false;

	ofxGgmlTextRequest request;
	request.systemPrompt = "Return a very short readiness confirmation.";
	request.prompt = "Reply with: ofxGgml Codex endpoint ready.";
	request.settings = requestSettings;

	ofxGgmlTextGenerator generator;
	generator.setBackend(std::make_shared<ofxGgmlLlamaServerTextBackend>(requestBaseUrl));
	const auto result = generator.generate(
		request,
		[this](const std::string &) {
			return !cancelRequested.load();
		});
	if (result && requestAutoConfig) {
		syncCodexConfig();
	}

	std::lock_guard<std::mutex> lock(stateMutex);
	if (cancelRequested) {
		endpointReady = false;
		endpointStatus = "endpoint smoke cancelled";
		running = false;
		return;
	}
	if (result) {
		endpointReady = true;
		serverReady = true;
		endpointOutput = ofxGgmlLlamaCodexLocal::trimCopy(result.text);
		endpointStatus = "OpenAI-compatible endpoint answered in " +
			std::to_string(static_cast<int>(result.elapsedMs)) + " ms";
		ofLogNotice(LogModule) << "endpoint smoke output\n" << endpointOutput;
	} else {
		endpointReady = false;
		endpointOutput = result.error;
		endpointStatus = "endpoint smoke failed: " + result.error;
		ofLogWarning(LogModule) << endpointStatus;
	}
	running = false;
}

void ofApp::requestWriteConfig() {
	if (syncCodexConfig()) {
		refreshServerStatus();
	}
}

void ofApp::requestLaunchCodex() {
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		if (running) {
			status = "another operation is already running";
			return;
		}
		running = true;
		cancelRequested = false;
		status = "launching Codex...";
	}
	joinWorker();
	worker = std::thread(&ofApp::runLaunchCodexWorker, this);
}

void ofApp::runLaunchCodexWorker() {
	std::string requestCodexExe;
	std::string requestAppArguments;
	int requestProviderMode = 0;
	bool requestAutoConfig = false;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestCodexExe = codexExe;
		requestProviderMode = codexProviderMode;
		requestAutoConfig = autoConfig;
		if (usesLocalCodexProvider(requestProviderMode)) {
			const auto config = makeCodexConfig();
			const auto launchModel = usesOpenAiCodexLaunch(requestProviderMode)
				? openAiModelAlias
				: (modelAlias.empty() ? defaultModelForProviderMode(requestProviderMode) : modelAlias);
			std::vector<std::string> arguments {
				"app",
				"--disable", "apps",
				"--disable", "image_generation",
				"--disable", "browser_use",
				"--disable", "computer_use",
				"--disable", "tool_search",
				"--disable", "tool_search_always_defer_mcp_tools"
			};
			appendCodexConfigOverride(arguments, "mcp_servers.node_repl.enabled=false");
			appendCodexConfigOverride(arguments, "web_search=" + tomlString(config.webSearch.empty() ? "live" : config.webSearch));
			if (isLocalCodexProviderMode(requestProviderMode)) {
				appendCodexConfigOverride(arguments, "model_provider=" + config.providerId);
				appendCodexConfigOverride(arguments, "model_providers." + config.providerId + ".name=" + tomlString(config.providerName));
				appendCodexConfigOverride(arguments, "model_providers." + config.providerId + ".base_url=" + tomlString(config.baseUrl));
				appendCodexConfigOverride(arguments, "model_providers." + config.providerId + ".wire_api=" + tomlString(config.wireApi));
				appendCodexConfigOverride(arguments, "model_providers." + config.providerId + ".stream_idle_timeout_ms=" + std::to_string(config.streamIdleTimeoutMs));
			}
			appendCodexConfigOverride(arguments, "model_context_window=" + std::to_string(config.modelContextWindow));
			appendCodexConfigOverride(arguments, "model_auto_compact_token_limit=" + std::to_string(config.modelAutoCompactTokenLimit));
			appendCodexConfigOverride(arguments, "tool_output_token_limit=" + std::to_string(config.toolOutputTokenLimit));
			appendCodexConfigOverride(arguments, "model_reasoning_effort=" + config.modelReasoningEffort);
			appendCodexConfigOverride(arguments, "model_reasoning_summary=" + config.modelReasoningSummary);
			appendCodexConfigOverride(arguments, "model_verbosity=" + config.modelVerbosity);
			appendCodexConfigOverride(arguments, std::string("hide_agent_reasoning=") + (config.hideAgentReasoning ? "true" : "false"));
			if (config.agentMaxConcurrentThreadsPerSession > 0) {
				appendCodexConfigOverride(arguments, "agents.max_threads=" + std::to_string(config.agentMaxConcurrentThreadsPerSession));
			}
			if (config.agentMaxDepth > 0) {
				appendCodexConfigOverride(arguments, "agents.max_depth=" + std::to_string(config.agentMaxDepth));
			}
			if (!launchModel.empty()) {
				appendCodexConfigOverride(arguments, "model=" + tomlString(launchModel));
			}
			if (!codexSandbox.empty()) {
				appendCodexConfigOverride(arguments, "sandbox_mode=" + tomlString(codexSandbox));
			}
			arguments.push_back(".");
			requestAppArguments = joinCodexArguments(arguments);
		}
	}

	const bool requestLocalProvider = usesLocalCodexProvider(requestProviderMode);
	if (requestLocalProvider && requestAutoConfig && !syncCodexConfig()) {
		ofLogWarning(LogModule) << "Codex auto-config failed; launch blocked";
		std::lock_guard<std::mutex> lock(stateMutex);
		running = false;
		status = "Codex launch blocked: failed to write local provider selection config";
		configWriteStatus = "local agents need the llama_cpp provider in " + configPath;
		return;
	}

	const bool launched = requestLocalProvider
		? ofxGgmlLlamaCodexLocal::launchDetachedProcess(
			requestCodexExe.empty() ? std::string("codex") : requestCodexExe,
			requestAppArguments)
		: ofxGgmlLlamaCodexLocal::launchUiProcess(requestCodexExe);
	std::lock_guard<std::mutex> lock(stateMutex);
	running = false;
	status = launched
		? "Opened Codex UI"
		: "failed to open Codex UI";
	configWriteStatus = launched
		? (requestLocalProvider
			? "Codex Desktop opened with llama.cpp-safe tool guards"
			: "Codex UI opened; provider selection settings are read from " + configPath)
		: (requestLocalProvider
			? "Codex Desktop launch failed; check executable path"
			: "Codex UI launch failed; check executable path");
}

void ofApp::refreshRuntimeDiscovery() {
	std::lock_guard<std::mutex> lock(stateMutex);
	const auto previousModelPath = modelPath;
	if (serverExe.empty() || !ofxGgmlLlamaCodexLocal::fileExists(serverExe)) {
		serverExe = ofxGgmlLlamaCodexLocal::discoverLlamaServer();
	}
	if (modelPath.empty() || !ofxGgmlLlamaCodexLocal::fileExists(modelPath)) {
		modelPath = ofxGgmlLlamaCodexLocal::discoverTextModel();
	}
	if (codexExe.empty() || !ofxGgmlLlamaCodexLocal::fileExists(codexExe)) {
		codexExe = ofxGgmlLlamaCodexLocal::discoverCodexExecutable();
	}
	refreshModelAliasForPath(previousModelPath);
	refreshModelMetadata();
	rebuildLines();
}

void ofApp::refreshModelAliasForPath(const std::string & previousModelPath) {
	const auto previousDerivedAlias = ofxGgmlLlamaCodexLocal::modelAliasFromPath(previousModelPath);
	const auto nextDerivedAlias = ofxGgmlLlamaCodexLocal::modelAliasFromPath(modelPath);
	if (nextDerivedAlias.empty()) {
		return;
	}
	if (!modelAliasManuallyEdited || modelAlias.empty() || modelAlias == previousDerivedAlias) {
		modelAlias = nextDerivedAlias;
		modelAliasManuallyEdited = false;
	}
}

void ofApp::refreshModelMetadata() {
	modelLayerCount = 0;
	modelContextLength = 0;
	if (modelPath.empty() || !ofxGgmlLlamaCodexLocal::fileExists(modelPath)) {
		return;
	}
	const auto result = ofxGgmlModel().inspect(modelPath);
	if (result.isOk()) {
		modelLayerCount = result.value().layerCount;
		modelContextLength = result.value().contextLength;
		applyModelContextMetadataDefaults();
	}
}

void ofApp::applyModelContextMetadataDefaults() {
	if (contextSize != 0 || modelContextLength == 0) {
		return;
	}
	const auto safeContextLength = static_cast<int>(std::min<uint64_t>(
		modelContextLength,
		static_cast<uint64_t>(std::numeric_limits<int>::max())));
	if (!modelContextWindowManuallyEdited) {
		modelContextWindow = safeContextLength;
	}
	if (!modelAutoCompactManuallyEdited) {
		modelAutoCompactTokenLimit = compactLimitForContext(modelContextWindow);
	}
}

void ofApp::refreshServerStatus() {
	std::string requestServerUrl;
	std::string requestBaseUrl;
	std::string requestModelAlias;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestServerUrl = serverUrl;
		requestBaseUrl = baseUrl;
		requestModelAlias = modelAlias;
	}
	const auto probe = ofxGgmlLlamaCodexLocal::probeServerHealth(requestServerUrl, 2);
	const auto servedModels = probe.ready
		? ofxGgmlLlamaCodexLocal::probeServedModels(requestBaseUrl, requestModelAlias, 2)
		: ofxGgmlLlamaServedModels {};
	std::lock_guard<std::mutex> lock(stateMutex);
	serverReady = probe.ready;
	if (serverReady) {
		wireApi = ofxGgmlLlamaCodexLocal::detectCodexWireApi(baseUrl);
		wireApiProbeStatus = "wire_api auto-detected as " + wireApi;
		servedModelAliases = servedModels.models;
		if (servedModels.ready && !servedModels.models.empty()) {
			servedModelStatus = "served model aliases: " + joinAliases(servedModels.models);
			if (!modelAlias.empty() && !servedModels.expectedModelServed) {
				servedModelStatus += " (current alias is not advertised)";
			}
		} else {
			servedModelStatus = "served model aliases unavailable: " +
				ofxGgmlLlamaCodexLocal::trimCopy(servedModels.message);
		}
	} else {
		endpointReady = false;
		wireApiProbeStatus = "wire_api not available (server not ready)";
		servedModelAliases.clear();
		servedModelStatus = "served model aliases unavailable (server not ready)";
	}
	status = probe.ready
		? "llama-server ready for Codex at " + baseUrl
		: "llama-server is not ready at " + requestServerUrl + " (" +
			ofxGgmlLlamaCodexLocal::describeProbe(probe) + ")";
	rebuildLines();
}

void ofApp::applyPreset(int index) {
	const auto & presets = codexLocalPresets();
	if (presets.empty()) {
		return;
	}
	const auto safeIndex = ofClamp(index, 0, static_cast<int>(presets.size()) - 1);
	presetIndex = safeIndex;
	const auto & preset = presets[static_cast<std::size_t>(safeIndex)];
	contextSize = preset.contextSize;
	parallel = preset.parallel;
	batchSize = preset.batchSize;
	ubatchSize = preset.ubatchSize;
	threads = preset.threads;
	threadsBatch = preset.threadsBatch;
	threadsHttp = preset.threadsHttp;
	cacheReuse = preset.cacheReuse;
	kvCacheKeyType = preset.kvCacheKeyType;
	kvCacheValueType = preset.kvCacheValueType;
	modelContextWindow = preset.modelContextWindow;
	modelAutoCompactTokenLimit = preset.modelAutoCompactTokenLimit;
	modelContextWindowManuallyEdited = false;
	modelAutoCompactManuallyEdited = false;
	applyModelContextMetadataDefaults();
	toolOutputTokenLimit = preset.toolOutputTokenLimit;
	agentMaxConcurrentThreadsPerSession = preset.agentMaxConcurrentThreads;
	applyInteractiveThreadBudget(true, true, true, true);
	agentMaxDepth = preset.agentMaxDepth;
	agentMinWaitTimeoutMs = preset.agentMinWaitMs;
	agentMaxWaitTimeoutMs = preset.agentMaxWaitMs;
	agentDefaultWaitTimeoutMs = preset.agentDefaultWaitMs;
	startupTimeoutSeconds = preset.startupTimeoutSeconds;
	temperature = preset.temperature;
	topP = preset.topP;
	minP = preset.minP;
	gpuLayersAll = true;
}

void ofApp::applyInteractiveThreadBudget(
	bool overwriteAgentOverride,
	bool overwriteThreadOverride,
	bool overwriteBatchThreadOverride,
	bool overwriteHttpThreadOverride) {
	parallel = std::max(1, parallel);
	if (overwriteAgentOverride && agentMaxConcurrentThreadsPerSession > 0) {
		agentMaxConcurrentThreadsPerSession = std::max(1, parallel);
	}
}

bool ofApp::adoptServedModelAliasIfNeeded() {
	std::string requestBaseUrl;
	std::string requestModelAlias;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestBaseUrl = baseUrl;
		requestModelAlias = modelAlias;
	}

	const auto servedModels = ofxGgmlLlamaCodexLocal::probeServedModels(
		requestBaseUrl,
		requestModelAlias,
		2);
	std::lock_guard<std::mutex> lock(stateMutex);
	servedModelAliases = servedModels.models;
	if (!servedModels.ready || servedModels.models.empty()) {
		servedModelStatus = "served model aliases unavailable: " +
			ofxGgmlLlamaCodexLocal::trimCopy(servedModels.message);
		rebuildLines();
		return false;
	}
	servedModelStatus = "served model aliases: " + joinAliases(servedModels.models);
	if (servedModels.expectedModelServed) {
		rebuildLines();
		return true;
	}
	if (servedModels.models.size() == 1) {
		modelAlias = servedModels.models.front();
		modelAliasManuallyEdited = true;
		configWriteStatus = "using server-advertised Codex model alias: " + modelAlias;
		rebuildLines();
		return true;
	}
	servedModelStatus += " (choose the matching alias before writing Codex config)";
	rebuildLines();
	return false;
}

bool ofApp::syncCodexConfig() {
	ofxGgmlLlamaCodexProviderConfig config;
	std::string requestConfigPath;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		config = makeCodexConfig();
		requestConfigPath = configPath;
	}
	const auto result = ofxGgmlLlamaCodexLocal::writeCodexConfig(requestConfigPath, config);
	std::lock_guard<std::mutex> lock(stateMutex);
	configPath = result.path;
	configWriteStatus = result.message;
	rebuildLines();
	return result.ok;
}

std::vector<std::string> ofApp::collectPreflightIssues(
	bool requireLocalServer,
	bool requireCodexExecutable) const {
	std::vector<std::string> issues;
	const bool localProviderMode = usesLocalCodexProvider(codexProviderMode);
	const bool llamaCppProviderMode = usesLlamaCppCodexProvider(codexProviderMode);
	const bool localHermesEndpointMode = usesLocalHermesEndpoint(codexProviderMode);
	if (localHermesEndpointMode && baseUrl.empty()) {
		issues.push_back("Codex base URL is empty");
	}
	if (localHermesEndpointMode && serverUrl.empty()) {
		issues.push_back("llama-server root is empty");
	}
	if (localHermesEndpointMode && modelAlias.empty()) {
		issues.push_back("model alias is empty");
	}
	if (llamaCppProviderMode && requireLocalServer) {
		if (modelPath.empty()) {
			issues.push_back("GGUF model path is empty");
		} else if (!ofxGgmlLlamaCodexLocal::fileExists(modelPath)) {
			issues.push_back("GGUF model file was not found");
		}
		if (serverExe.empty()) {
			issues.push_back("llama-server executable is empty");
		} else if (!ofxGgmlLlamaCodexLocal::fileExists(serverExe)) {
			issues.push_back("llama-server executable was not found");
		}
	}
	if (requireCodexExecutable) {
		if (configPath.empty()) {
			issues.push_back("Codex config path is empty");
		}
		if (codexExe.empty()) {
			issues.push_back("Codex executable is empty");
		} else if (!ofxGgmlLlamaCodexLocal::fileExists(codexExe) && codexExe != "codex") {
			issues.push_back("Codex executable was not found");
		}
	}
	if (contextSize < 0) {
		issues.push_back("context size must be zero or positive");
	}
	if (parallel < 1) {
		issues.push_back("parallel slots must be at least 1");
	}
	if (batchSize < 1 || ubatchSize < 1) {
		issues.push_back("batch and ubatch sizes must be at least 1");
	}
	if (agentMaxConcurrentThreadsPerSession > 0 &&
		agentMaxConcurrentThreadsPerSession > std::max(1, parallel)) {
		issues.push_back("agent max threads is higher than server parallel slots");
	}
	return issues;
}

std::string ofApp::formatPreflightSummary(const std::vector<std::string> & issues) const {
	if (issues.empty()) {
		if (isLocalCodexProviderMode(codexProviderMode)) {
			return "preflight: ready for local Codex launch";
		}
		if (usesLocalCodexProvider(codexProviderMode) && usesOpenAiCodexLaunch(codexProviderMode)) {
			return "preflight: ready for hybrid OpenAI launch with local agents";
		}
		if (usesLocalHermesEndpoint(codexProviderMode) && usesOpenAiCodexLaunch(codexProviderMode)) {
			return "preflight: ready for OpenAI Codex launch with local Hermes endpoint";
		}
		return "preflight: ready for OpenAI Codex launch";
	}
	return "preflight: " + joinIssues(issues);
}

std::string ofApp::buildCodexConfigSnippetText() const {
	if (!usesLocalCodexProvider(codexProviderMode)) {
		return "";
	}
	return ofxGgmlLlamaCodexLocal::buildCodexConfigSnippet(makeCodexConfig());
}

std::string ofApp::buildHermesConfigSnippetText() const {
	if (!usesLocalHermesEndpoint(codexProviderMode)) {
		return "";
	}
	const auto effectiveModelAlias = modelAlias.empty()
		? defaultModelForProviderMode(codexProviderMode)
		: modelAlias;
	std::ostringstream snippet;
	snippet
		<< "# Hermes Agent custom endpoint; point it at the same loaded llama-server used by Codex.\n"
		<< "# Use `hermes model` and choose Custom Endpoint, or mirror this model section in ~/.hermes/config.yaml.\n"
		<< "model:\n"
		<< "  default: " << effectiveModelAlias << "\n"
		<< "  provider: custom\n"
		<< "  base_url: " << baseUrl << "\n"
		<< "  api_key: local-dummy-key\n"
		<< "  context_length: " << modelContextWindow << "\n"
		<< "terminal:\n"
		<< "  backend: local\n";
	return snippet.str();
}

std::string ofApp::buildManualServerCommand() const {
	const auto effectiveModelAlias = modelAlias.empty()
		? ofxGgmlLlamaCodexLocal::modelAliasFromPath(modelPath)
		: modelAlias;
	std::vector<std::string> arguments {
		"scripts\\start-llama-server.bat",
		"-HostName",
		"127.0.0.1",
		"-Port",
		std::to_string(ofxGgmlLlamaCodexLocal::serverPortFromUrl(serverUrl, 8001)),
		"-ContextSize",
		std::to_string(contextSize),
		"-GpuLayers",
		gpuLayersAll ? std::string("all") : std::to_string(gpuLayers),
		"-ModelPath",
		modelPath,
		"-Alias",
		effectiveModelAlias
	};
	arguments.push_back("-Parallel");
	arguments.push_back(std::to_string(parallel));
	arguments.push_back("-BatchSize");
	arguments.push_back(std::to_string(batchSize));
	arguments.push_back("-UBatchSize");
	arguments.push_back(std::to_string(ubatchSize));
	if (threads > 0) {
		arguments.push_back("-Threads");
		arguments.push_back(std::to_string(threads));
	}
	if (threadsBatch > 0) {
		arguments.push_back("-ThreadsBatch");
		arguments.push_back(std::to_string(threadsBatch));
	}
	if (threadsHttp > 0) {
		arguments.push_back("-ThreadsHttp");
		arguments.push_back(std::to_string(threadsHttp));
	}
	if (cacheReuse > 0) {
		arguments.push_back("-CacheReuse");
		arguments.push_back(std::to_string(cacheReuse));
	}
	appendCommandArgument(arguments, "-KvCacheKeyType", kvCacheKeyType);
	appendCommandArgument(arguments, "-KvCacheValueType", kvCacheValueType);
	appendCommandArgument(arguments, "-SpecType", specType);
	appendCommandArgument(arguments, "-DraftModel", draftModelPath);
	appendCommandArgument(arguments, "-DraftGpuLayers", draftGpuLayers);
	if (draftMaxTokens > 0) {
		arguments.push_back("-DraftMaxTokens");
		arguments.push_back(std::to_string(draftMaxTokens));
	}
	if (draftMinTokens > 0) {
		arguments.push_back("-DraftMinTokens");
		arguments.push_back(std::to_string(draftMinTokens));
	}
	if (draftPSplit >= 0.0f) {
		arguments.push_back("-DraftPSplit");
		arguments.push_back(std::to_string(draftPSplit));
	}
	if (draftPMin >= 0.0f) {
		arguments.push_back("-DraftPMin");
		arguments.push_back(std::to_string(draftPMin));
	}
	arguments.push_back("-Jinja");
	arguments.push_back("-FlashAttention");
	if (noCudaGraphs) {
		arguments.push_back("-NoCudaGraphs");
	}
	if (skipChatParsing) {
		arguments.push_back("-SkipChatParsing");
	}
	arguments.push_back("-Temperature");
	arguments.push_back(ofToString(temperature, 3));
	arguments.push_back("-TopP");
	arguments.push_back(ofToString(topP, 3));
	arguments.push_back("-MinP");
	arguments.push_back(ofToString(minP, 3));

	std::ostringstream command;
	for (std::size_t i = 0; i < arguments.size(); ++i) {
		if (i > 0) {
			command << " ";
		}
		command << quoteCommandArgument(arguments[i]);
	}
	return command.str();
}

std::string ofApp::buildCodexLaunchCommand() const {
	const auto config = makeCodexConfig();
	const bool localProviderMode = usesLocalCodexProvider(codexProviderMode);
	const bool localLaunchMode = isLocalCodexProviderMode(codexProviderMode);
	const bool openAiLaunchMode = usesOpenAiCodexLaunch(codexProviderMode);
	const auto effectiveModelAlias = modelAlias.empty()
		? defaultModelForProviderMode(codexProviderMode)
		: modelAlias;
	const auto launchModel = openAiLaunchMode ? openAiModelAlias : effectiveModelAlias;

	ofxGgmlLlamaCodexLaunchCommandSettings settings;
	settings.executable = codexExe;
	settings.profile = codexProfile;
	settings.model = launchModel;
	settings.sandbox = codexSandbox;
	settings.provider = config;
	settings.includeLocalProviderToolGuards = localProviderMode;
	settings.includeLocalProviderOverrides = localLaunchMode;
	return ofxGgmlLlamaCodexLocal::buildLaunchCommand(settings);
}

void ofApp::copyTextToClipboard(const std::string & label, const std::string & text) {
	if (text.empty()) {
		configWriteStatus = label + " is empty";
		return;
	}
	ofSetClipboardString(text);
	configWriteStatus = "copied " + label + " to clipboard";
}

void ofApp::rebuildLines() {
	lines.clear();
	const bool localProviderMode = usesLocalCodexProvider(codexProviderMode);
	const bool llamaCppProviderMode = usesLlamaCppCodexProvider(codexProviderMode);
	const bool openAiLaunchMode = usesOpenAiCodexLaunch(codexProviderMode);
	const bool localHermesEndpointMode = usesLocalHermesEndpoint(codexProviderMode);
	if (localProviderMode) {
		std::istringstream snippet(buildCodexConfigSnippetText());
		std::string line;
		while (std::getline(snippet, line)) {
			lines.push_back(line);
		}
	}
	if (openAiLaunchMode && localProviderMode) {
		lines.push_back("Hybrid mode: cheap explorer/worker agents use local llama.cpp.");
		lines.push_back("OpenAI handles the main Codex launch and expensive reasoning.");
	} else if (openAiLaunchMode && localHermesEndpointMode) {
		lines.push_back("OpenAI + local Hermes mode: Codex uses the selected OpenAI profile.");
		lines.push_back("Hermes Agent can use the local llama.cpp endpoint as an explicit sidecar.");
	} else if (openAiLaunchMode) {
		lines.push_back("OpenAI profile mode: Codex uses the selected profile from your existing config.");
		lines.push_back("Local llama-server provider overrides and local agent role file writes are skipped.");
	}
	if (llamaCppProviderMode && gpuLayersAll) {
		lines.push_back(modelLayerCount > 0
			? "GPU layers all: " + std::to_string(modelLayerCount) + " model layers"
			: "GPU layers all: model layer count unknown");
	}
	if (llamaCppProviderMode && modelContextLength > 0 && contextSize == 0) {
		lines.push_back(
			"Model metadata context: " + std::to_string(modelContextLength) +
			" tokens");
	}
	if (llamaCppProviderMode) {
		lines.push_back(
			"Server perf: ctx=" + std::to_string(contextSize) +
			" parallel=" + std::to_string(parallel) +
			" batch=" + std::to_string(batchSize) +
			" ubatch=" + std::to_string(ubatchSize) +
			" cacheReuse=" + std::to_string(std::max(0, cacheReuse)) +
			" ctk=" + (kvCacheKeyType.empty() ? std::string("default") : kvCacheKeyType) +
			" ctv=" + (kvCacheValueType.empty() ? std::string("default") : kvCacheValueType) +
			" spec=" + (specType.empty() ? std::string("default") : specType) +
			" draft=" + (draftModelPath.empty() ? std::string("none") : draftModelPath) +
			" draft_ngl=" + (draftGpuLayers.empty() ? std::string("auto") : draftGpuLayers) +
			" draft_n=" + (draftMaxTokens > 0 ? std::to_string(draftMaxTokens) : std::string("default")) +
			" cudaGraph=" + std::string(noCudaGraphs ? "off" : "on"));
	}
	if (localHermesEndpointMode && !servedModelAliases.empty()) {
		lines.push_back("Server advertises: " + joinAliases(servedModelAliases));
	}
	if (localHermesEndpointMode) {
		const auto hermesModel = modelAlias.empty() ? defaultModelForProviderMode(codexProviderMode) : modelAlias;
		const auto endpointUse = localProviderMode
			? "This reuses the same loaded model as local Codex"
			: "This local model is separate from the OpenAI Codex launch";
		appendWrapped(
			lines,
			"Hermes shared endpoint: use Custom Endpoint with base_url " + baseUrl +
				" and model " + hermesModel +
				". " + endpointUse + "; conversation memory remains client-local.",
			96);
	}
	lines.push_back(formatPreflightSummary(collectPreflightIssues(false, true)));
	appendWrapped(
		lines,
		"Codex launch command: " + buildCodexLaunchCommand(),
		96);
	if (llamaCppProviderMode) {
		appendWrapped(
			lines,
			"Manual server command: " + buildManualServerCommand(),
			96);
		appendWrapped(
			lines,
			"Use this provider selection with Codex after the server is ready. The reusable config and llama-server helpers live in ofxGgmlLlama/src/codex.",
			96);
	} else if (openAiLaunchMode) {
		appendWrapped(
			lines,
			"OpenAI launch command uses " +
				(codexProfile.empty() ? std::string("the default profile") : "-p " + codexProfile) +
				(openAiModelAlias.empty() ? std::string() : " and --model " + openAiModelAlias) + ".",
			96);
	}
}

void ofApp::joinWorker() {
	if (worker.joinable()) {
		worker.join();
	}
}

ofxGgmlLlamaCodexProviderConfig ofApp::makeCodexConfig() const {
	ofxGgmlLlamaCodexProviderConfig config;
	config.providerId = providerIdForMode(codexProviderMode);
	config.providerName = providerNameForMode(codexProviderMode);
	config.profile = codexProfile.empty() ? profileForMode(codexProviderMode) : codexProfile;
	config.baseUrl = baseUrl;
	config.modelAlias = modelAlias;
	config.wireApi = wireApi.empty() ? "responses" : wireApi;
	config.webSearch = webSearch.empty() ? "live" : webSearch;
	config.modelContextWindow = modelContextWindow;
	config.modelAutoCompactTokenLimit = modelAutoCompactTokenLimit;
	config.toolOutputTokenLimit = toolOutputTokenLimit;
	config.modelReasoningEffort = reasoningEffortFromIndex(reasoningEffortIndex);
	config.modelReasoningSummary = "auto";
	config.agentMaxConcurrentThreadsPerSession = agentMaxConcurrentThreadsPerSession;
	config.agentMaxDepth = agentMaxDepth;
	config.agentMinWaitTimeoutMs = agentMinWaitTimeoutMs;
	config.agentMaxWaitTimeoutMs = agentMaxWaitTimeoutMs;
	config.agentDefaultWaitTimeoutMs = agentDefaultWaitTimeoutMs;
	config.hideAgentReasoning = true;
	config.writeTopLevelSelection = true;
	if (usesLocalCodexProvider(codexProviderMode) && usesOpenAiCodexLaunch(codexProviderMode)) {
		config.profile = profileForMode(codexProviderMode);
		config.writeTopLevelSelection = false;
	}
	return config;
}

ofxGgmlLlamaServerStartSettings ofApp::makeServerSettings() const {
	std::lock_guard<std::mutex> lock(stateMutex);
	ofxGgmlLlamaServerStartSettings settings;
	settings.serverExe = serverExe;
	settings.modelPath = modelPath;
	settings.serverUrl = serverUrl;
	settings.modelAlias = modelAlias.empty()
		? ofxGgmlLlamaCodexLocal::modelAliasFromPath(modelPath)
		: modelAlias;
	settings.gpuLayers = gpuLayers;
	settings.gpuLayersAll = gpuLayersAll;
	settings.contextSize = contextSize;
	settings.parallel = parallel;
	settings.batchSize = batchSize;
	settings.ubatchSize = ubatchSize;
	settings.threads = threads;
	settings.threadsBatch = threadsBatch;
	settings.threadsHttp = threadsHttp;
	settings.cacheReuse = cacheReuse;
	settings.kvCacheKeyType = kvCacheKeyType;
	settings.kvCacheValueType = kvCacheValueType;
	settings.specType = specType;
	settings.draftModelPath = draftModelPath;
	settings.draftGpuLayers = draftGpuLayers;
	settings.draftMaxTokens = draftMaxTokens;
	settings.draftMinTokens = draftMinTokens;
	settings.draftPSplit = draftPSplit;
	settings.draftPMin = draftPMin;
	settings.temperature = temperature;
	settings.topP = topP;
	settings.minP = minP;
	settings.noCudaGraphs = noCudaGraphs;
	settings.skipChatParsing = skipChatParsing;
	return settings;
}

bool ofApp::syncHermesConfig() {
	ofxGgmlLlamaHermesConfig config;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		config = makeHermesConfig();
	}
	ofxGgmlLlamaHermesConfigResult result;
	try {
		result = ofxGgmlLlamaCodexLocal::writeHermesConfig(std::string(), config);
	} catch (const std::exception & error) {
		result.ok = false;
		result.message = std::string("failed to write Hermes config: ") + error.what();
	} catch (...) {
		result.ok = false;
		result.message = "failed to write Hermes config: unknown error";
	}
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		hermesConfigWriteStatus = result.message;
	}
	rebuildLines();
	return result.ok;
}

ofxGgmlLlamaHermesConfig ofApp::makeHermesConfig() const {
	ofxGgmlLlamaHermesConfig config;
	config.modelAlias = modelAlias.empty()
		? defaultModelForProviderMode(codexProviderMode)
		: modelAlias;
	config.baseUrl = baseUrl;
	config.apiKey = "local-dummy-key";
	config.contextLength = modelContextWindow;
	config.terminalBackend = "local";
	return config;
}
