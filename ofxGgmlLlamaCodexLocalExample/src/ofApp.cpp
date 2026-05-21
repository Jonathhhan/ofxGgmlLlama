#include "ofApp.h"

#include "imgui_stdlib.h"
#include "model/ofxGgmlModel.h"

#include <algorithm>
#include <limits>
#include <memory>
#include <sstream>

namespace {
constexpr const char * LogModule = "ofxGgmlLlamaCodexLocalExample";

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
		{"memory", "Memory saver", 16384, 1, 1024, 256, 0, 0, 0, 128, "", "", 16384, 12000, 3000, 1, 1, 2500, 90000, 30000, 300, 0.8f, 0.9f, 0.02f},
		{"fast", "Fast coding", 32768, 1, 4096, 1024, 0, 0, 0, 256, "", "", 32768, 24000, 5000, 1, 1, 2500, 120000, 30000, 300, 0.6f, 0.9f, 0.02f},
		{"balanced", "Balanced local", 40960, 1, 2048, 512, 0, 0, 0, 256, "", "", 40960, 30000, 5000, 1, 1, 2500, 120000, 30000, 300, 1.0f, 0.95f, 0.01f},
		{"quality", "Quality coding", 65536, 1, 3072, 768, 0, 0, 0, 256, "", "", 65536, 50000, 8000, 1, 1, 2500, 180000, 30000, 600, 0.7f, 0.9f, 0.02f},
		{"fullctx", "Full context Q8", 0, 1, 2048, 512, 0, 0, 0, 512, "q8_0", "q8_0", 131072, 112000, 12000, 1, 1, 5000, 240000, 30000, 600, 0.7f, 0.9f, 0.02f},
		{"fullctx-q5", "Full context Q5", 0, 1, 2048, 512, 0, 0, 0, 512, "q5_0", "q5_0", 131072, 112000, 12000, 1, 1, 5000, 240000, 30000, 600, 0.7f, 0.9f, 0.02f},
		{"fullctx-q4", "Full context Q4", 0, 1, 1536, 384, 0, 0, 0, 512, "q4_0", "q4_0", 131072, 112000, 12000, 1, 1, 5000, 240000, 30000, 600, 0.7f, 0.9f, 0.02f},
		{"long", "Long context", 131072, 1, 4096, 1024, 0, 0, 0, 512, "", "", 131072, 100000, 8000, 1, 1, 5000, 300000, 30000, 600, 0.8f, 0.92f, 0.02f},
		{"concurrent", "Concurrent agents", 65536, 2, 2048, 512, 0, 0, 0, 256, "", "", 32768, 24000, 5000, 2, 1, 2500, 180000, 30000, 600, 0.9f, 0.95f, 0.01f}
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
	return 3;
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

void appendCodexConfigOverride(
	std::string & arguments,
	const std::string & key,
	const std::string & value) {
	arguments += "-c ";
	arguments += ofxGgmlLlamaCodexLocal::quoteArgument(key + "=" + value);
	arguments += " ";
}
}

void ofApp::setup() {
	ofSetWindowTitle("ofxGgmlLlama Codex Local");
	gui.setup();

	presetIndex = presetIndexFromId(
		ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_CODEX_PRESET", "quality"));
	applyPreset(presetIndex);

	baseUrl = ofxGgmlLlamaCodexLocal::getEnvOrDefault(
		"OFXGGML_CODEX_BASE_URL",
		"http://127.0.0.1:8001/v1");
	serverUrl = ofxGgmlLlamaCodexLocal::serverRootFromBaseUrl(baseUrl);
	modelPath = ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_TEXT_MODEL", "");
	modelAlias = ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_CODEX_MODEL", "");
	serverExe = ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_LLAMA_SERVER_EXE", "");
	codexExe = ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_CODEX_EXE", "");
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
	agentMaxDepth = envInt("OFXGGML_CODEX_AGENT_MAX_DEPTH", agentMaxDepth);
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

	gui.begin();
	if (ImGui::Begin("OpenAI Codex + local llama-server")) {
		std::lock_guard<std::mutex> lock(stateMutex);
		ImGui::TextWrapped("%s", status.empty() ? "ready" : status.c_str());
		const auto serverPreflightIssues = collectPreflightIssues(true, false);
		const auto launchPreflightIssues = collectPreflightIssues(false, true);
		preflightStatus = formatPreflightSummary(launchPreflightIssues);
		ImGui::TextWrapped("%s", preflightStatus.c_str());
		ImGui::Separator();

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
		ImGui::BeginDisabled(servedModelAliases.empty());
		adoptServedAliasRequested = ImGui::Button("Use served alias");
		ImGui::EndDisabled();
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
		if (ImGui::InputText("Codex executable", &codexExe)) {
			rebuildLines();
		}
		if (ImGui::InputText("Codex profile", &codexProfile)) {
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
		ImGui::Checkbox("GPU layers all", &gpuLayersAll);
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
		ImGui::InputInt("GPU layers", &gpuLayers);
		ImGui::EndDisabled();
		ImGui::InputInt("Context size", &contextSize);
		ImGui::InputInt("Parallel", &parallel);
		ImGui::InputInt("Batch size", &batchSize);
		ImGui::InputInt("UBatch size", &ubatchSize);
		ImGui::InputInt("Threads (0 auto)", &threads);
		ImGui::InputInt("Batch threads (0 auto)", &threadsBatch);
		ImGui::InputInt("HTTP threads (0 auto)", &threadsHttp);
		ImGui::InputInt("Cache reuse tokens", &cacheReuse);
		if (drawStringCombo("KV cache K type", kvCacheKeyType, kvCacheTypes())) {
			rebuildLines();
		}
		if (drawStringCombo("KV cache V type", kvCacheValueType, kvCacheTypes())) {
			rebuildLines();
		}
		if (drawStringCombo("Spec type", specType, specTypes())) {
			rebuildLines();
		}
		if (ImGui::InputInt("Model context window", &modelContextWindow)) {
			modelContextWindowManuallyEdited = true;
		}
		if (ImGui::InputInt("Auto compact tokens", &modelAutoCompactTokenLimit)) {
			modelAutoCompactManuallyEdited = true;
		}
		ImGui::InputInt("Tool output tokens", &toolOutputTokenLimit);
		ImGui::InputInt("Startup timeout seconds", &startupTimeoutSeconds);
		ImGui::SliderFloat("Temperature", &temperature, 0.0f, 2.0f, "%.2f");
		ImGui::SliderFloat("Top P", &topP, 0.05f, 1.0f, "%.2f");
		ImGui::SliderFloat("Min P", &minP, 0.0f, 0.2f, "%.3f");
		ImGui::Separator();
		ImGui::TextUnformatted("Agent settings");
		ImGui::InputInt("Agent max threads", &agentMaxConcurrentThreadsPerSession);
		ImGui::InputInt("Agent max depth", &agentMaxDepth);
		ImGui::InputInt("Agent min wait ms", &agentMinWaitTimeoutMs);
		ImGui::InputInt("Agent max wait ms", &agentMaxWaitTimeoutMs);
		ImGui::InputInt("Agent default wait ms", &agentDefaultWaitTimeoutMs);
		if (ImGui::Combo(
				"Reasoning effort",
				&reasoningEffortIndex,
				codexReasoningEfforts().data(),
				static_cast<int>(codexReasoningEfforts().size()))) {
			rebuildLines();
		}
		ImGui::Checkbox("No CUDA graphs", &noCudaGraphs);
		ImGui::Checkbox("Skip chat parsing", &skipChatParsing);
		ImGui::Checkbox("Auto-write Codex config", &autoConfig);

		ImGui::Separator();
		const bool blockServerActions = running || !serverPreflightIssues.empty();
		const bool blockSmoke = running || modelAlias.empty() || baseUrl.empty();
		const bool blockConfigWrite = running || modelAlias.empty() || configPath.empty();
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
	std::string requestProfile;
	std::string requestBaseUrl;
	std::string requestModelAlias;
	int requestModelContextWindow = 65536;
	int requestModelAutoCompactTokenLimit = 50000;
	int requestToolOutputTokenLimit = 8000;
	int requestAgentMaxConcurrentThreadsPerSession = 1;
	int requestAgentMaxDepth = 1;
	int requestAgentMinWaitTimeoutMs = 2500;
	int requestAgentMaxWaitTimeoutMs = 180000;
	int requestAgentDefaultWaitTimeoutMs = 30000;
	std::string requestReasoningEffort;
	bool requestAutoConfig = false;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestCodexExe = codexExe;
		requestProfile = codexProfile.empty() ? "ofxggml_local" : codexProfile;
		requestBaseUrl = baseUrl;
		requestModelAlias = modelAlias;
		requestModelContextWindow = modelContextWindow;
		requestModelAutoCompactTokenLimit = modelAutoCompactTokenLimit;
		requestToolOutputTokenLimit = toolOutputTokenLimit;
		requestAgentMaxConcurrentThreadsPerSession = agentMaxConcurrentThreadsPerSession;
		requestAgentMaxDepth = agentMaxDepth;
		requestAgentMinWaitTimeoutMs = agentMinWaitTimeoutMs;
		requestAgentMaxWaitTimeoutMs = agentMaxWaitTimeoutMs;
		requestAgentDefaultWaitTimeoutMs = agentDefaultWaitTimeoutMs;
		requestReasoningEffort = reasoningEffortFromIndex(reasoningEffortIndex);
		requestAutoConfig = autoConfig;
	}

	if (requestAutoConfig && !syncCodexConfig()) {
		ofLogWarning(LogModule) << "Codex auto-config failed; attempting launch with existing config";
	}
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestModelAlias = modelAlias;
	}

	std::string arguments;
	if (ofxGgmlLlamaCodexLocal::executableSupportsArgument(requestCodexExe, "--no-alt-screen")) {
		arguments += "--no-alt-screen ";
	}
	if (ofxGgmlLlamaCodexLocal::executableSupportsArgument(requestCodexExe, "--disable")) {
		arguments += "--disable apps --disable image_generation --disable browser_use --disable computer_use --disable tool_search ";
	}
	arguments += "-p " + ofxGgmlLlamaCodexLocal::quoteArgument(requestProfile) + " ";
	appendCodexConfigOverride(arguments, "web_search", "\"disabled\"");
	appendCodexConfigOverride(arguments, "model_provider", "llama_cpp");
	appendCodexConfigOverride(arguments, "model_providers.llama_cpp.name", "\"llama.cpp local\"");
	appendCodexConfigOverride(
		arguments,
		"model_providers.llama_cpp.base_url",
		"\"" + ofxGgmlLlamaCodexLocal::codexApiRootFromBaseUrl(requestBaseUrl) + "\"");
	appendCodexConfigOverride(arguments, "model_providers.llama_cpp.wire_api", "\"responses\"");
	appendCodexConfigOverride(
		arguments,
		"model_providers.llama_cpp.stream_idle_timeout_ms",
		"10000000");
	appendCodexConfigOverride(
		arguments,
		"model_context_window",
		std::to_string(requestModelContextWindow));
	appendCodexConfigOverride(
		arguments,
		"model_auto_compact_token_limit",
		std::to_string(requestModelAutoCompactTokenLimit));
	appendCodexConfigOverride(
		arguments,
		"tool_output_token_limit",
		std::to_string(requestToolOutputTokenLimit));
	appendCodexConfigOverride(arguments, "model_reasoning_effort", requestReasoningEffort);
	appendCodexConfigOverride(arguments, "model_reasoning_summary", "none");
	appendCodexConfigOverride(arguments, "hide_agent_reasoning", "true");
	appendCodexConfigOverride(
		arguments,
		"agents.max_threads",
		std::to_string(requestAgentMaxConcurrentThreadsPerSession));
	appendCodexConfigOverride(arguments, "agents.max_depth", std::to_string(requestAgentMaxDepth));
	if (!requestModelAlias.empty()) {
		if (ofxGgmlLlamaCodexLocal::executableSupportsArgument(requestCodexExe, "--model")) {
			arguments += "--model " + ofxGgmlLlamaCodexLocal::quoteArgument(requestModelAlias);
		} else {
			arguments += "-m " + ofxGgmlLlamaCodexLocal::quoteArgument(requestModelAlias);
		}
	}

	const bool launched = ofxGgmlLlamaCodexLocal::launchDetachedProcess(requestCodexExe, arguments);
	std::lock_guard<std::mutex> lock(stateMutex);
	running = false;
	status = launched
		? "Launched Codex with profile " + requestProfile
		: "failed to launch Codex";
	configWriteStatus = launched
		? "Codex launch command: " + requestCodexExe + " " + arguments
		: "Codex launch failed; check CLI path";
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
	if (baseUrl.empty()) {
		issues.push_back("Codex base URL is empty");
	}
	if (serverUrl.empty()) {
		issues.push_back("llama-server root is empty");
	}
	if (modelAlias.empty()) {
		issues.push_back("model alias is empty");
	}
	if (requireLocalServer) {
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
	if (agentMaxConcurrentThreadsPerSession > std::max(1, parallel)) {
		issues.push_back("agent max threads is higher than server parallel slots");
	}
	return issues;
}

std::string ofApp::formatPreflightSummary(const std::vector<std::string> & issues) const {
	if (issues.empty()) {
		return "preflight: ready for local Codex launch";
	}
	return "preflight: " + joinIssues(issues);
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

void ofApp::rebuildLines() {
	lines.clear();
	const auto config = makeCodexConfig();
	std::istringstream snippet(ofxGgmlLlamaCodexLocal::buildCodexConfigSnippet(config));
	std::string line;
	while (std::getline(snippet, line)) {
		lines.push_back(line);
	}
	if (gpuLayersAll) {
		lines.push_back(modelLayerCount > 0
			? "GPU layers all: " + std::to_string(modelLayerCount) + " model layers"
			: "GPU layers all: model layer count unknown");
	}
	if (modelContextLength > 0 && contextSize == 0) {
		lines.push_back(
			"Model metadata context: " + std::to_string(modelContextLength) +
			" tokens");
	}
	lines.push_back(
		"Server perf: ctx=" + std::to_string(contextSize) +
		" parallel=" + std::to_string(parallel) +
		" batch=" + std::to_string(batchSize) +
		" ubatch=" + std::to_string(ubatchSize) +
		" cacheReuse=" + std::to_string(std::max(0, cacheReuse)) +
		" ctk=" + (kvCacheKeyType.empty() ? std::string("default") : kvCacheKeyType) +
		" ctv=" + (kvCacheValueType.empty() ? std::string("default") : kvCacheValueType) +
		" spec=" + (specType.empty() ? std::string("default") : specType) +
		" cudaGraph=" + std::string(noCudaGraphs ? "off" : "on"));
	if (!servedModelAliases.empty()) {
		lines.push_back("Server advertises: " + joinAliases(servedModelAliases));
	}
	lines.push_back(formatPreflightSummary(collectPreflightIssues(false, true)));
	appendWrapped(
		lines,
		"Manual server command: " + buildManualServerCommand(),
		96);
	appendWrapped(
		lines,
		"Use this provider/profile with Codex after the server is ready. The reusable config and llama-server helpers live in ofxGgmlLlama/src/codex.",
		96);
}

void ofApp::joinWorker() {
	if (worker.joinable()) {
		worker.join();
	}
}

ofxGgmlLlamaCodexProviderConfig ofApp::makeCodexConfig() const {
	ofxGgmlLlamaCodexProviderConfig config;
	config.profile = codexProfile.empty() ? "ofxggml_local" : codexProfile;
	config.baseUrl = baseUrl;
	config.modelAlias = modelAlias;
	config.wireApi = wireApi.empty() ? "responses" : wireApi;
	config.modelContextWindow = modelContextWindow;
	config.modelAutoCompactTokenLimit = modelAutoCompactTokenLimit;
	config.toolOutputTokenLimit = toolOutputTokenLimit;
	config.modelReasoningEffort = reasoningEffortFromIndex(reasoningEffortIndex);
	config.agentMaxConcurrentThreadsPerSession = agentMaxConcurrentThreadsPerSession;
	config.agentMaxDepth = agentMaxDepth;
	config.agentMinWaitTimeoutMs = agentMinWaitTimeoutMs;
	config.agentMaxWaitTimeoutMs = agentMaxWaitTimeoutMs;
	config.agentDefaultWaitTimeoutMs = agentDefaultWaitTimeoutMs;
	config.writeTopLevelSelection = true;
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
	settings.temperature = temperature;
	settings.topP = topP;
	settings.minP = minP;
	settings.noCudaGraphs = noCudaGraphs;
	settings.skipChatParsing = skipChatParsing;
	return settings;
}
