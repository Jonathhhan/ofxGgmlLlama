#include "ofApp.h"

#include "imgui_stdlib.h"
#include "model/ofxGgmlModel.h"

#include <algorithm>
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
	int modelContextWindow;
	int modelAutoCompactTokenLimit;
	int toolOutputTokenLimit;
	int agentMaxConcurrentThreads;
	int agentMaxDepth;
	int agentMinWaitMs;
	int agentMaxWaitMs;
	int agentDefaultWaitMs;
	int startupTimeoutSeconds;
};

const std::vector<CodexLocalPreset> & codexLocalPresets() {
	static const std::vector<CodexLocalPreset> presets {
		{"memory", "Memory saver", 16384, 1, 1024, 256, 16384, 12000, 3000, 1, 1, 2500, 90000, 30000, 300},
		{"balanced", "Balanced local", 40960, 1, 2048, 512, 40960, 30000, 5000, 1, 1, 2500, 120000, 30000, 300},
		{"long", "Long context", 131072, 1, 4096, 1024, 131072, 100000, 8000, 1, 1, 5000, 300000, 30000, 600},
		{"concurrent", "Concurrent agents", 65536, 2, 2048, 512, 32768, 24000, 5000, 2, 1, 2500, 180000, 30000, 600}
	};
	return presets;
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
}

void ofApp::setup() {
	ofSetWindowTitle("ofxGgmlLlama Codex Local");
	gui.setup();

	presetIndex = presetIndexFromId(
		ofxGgmlLlamaCodexLocal::getEnvOrDefault("OFXGGML_CODEX_PRESET", "balanced"));
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
	modelContextWindow = envInt("OFXGGML_CODEX_MODEL_CONTEXT_WINDOW", modelContextWindow);
	modelAutoCompactTokenLimit = envInt(
		"OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT",
		modelAutoCompactTokenLimit);
	toolOutputTokenLimit = envInt("OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT", toolOutputTokenLimit);
	agentMaxConcurrentThreadsPerSession = envInt(
		"OFXGGML_CODEX_AGENT_MAX_AGENTS",
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
	startupTimeoutSeconds = envInt("OFXGGML_CODEX_STARTUP_TIMEOUT", startupTimeoutSeconds);
	temperature = envFloat("OFXGGML_CODEX_TEMP", temperature);
	topP = envFloat("OFXGGML_CODEX_TOP_P", topP);
	minP = envFloat("OFXGGML_CODEX_MIN_P", minP);
	noCudaGraphs = envBool("OFXGGML_CODEX_NO_CUDA_GRAPHS", noCudaGraphs);
	skipChatParsing = envBool("OFXGGML_CODEX_SKIP_CHAT_PARSING", skipChatParsing);
	autoConfig = envBool("OFXGGML_CODEX_AUTO_CONFIG", autoConfig);
	multiAgentV2Enabled = envBool("OFXGGML_CODEX_MULTI_AGENT_V2", multiAgentV2Enabled);

	refreshRuntimeDiscovery();
	if (modelAlias.empty()) {
		modelAlias = ofxGgmlLlamaCodexLocal::modelAliasFromPath(modelPath);
	}
	refreshModelMetadata();
	status = "ready";
	wireApiProbeStatus = "wire_api defaults to responses";
	rebuildLines();
}

void ofApp::draw() {
	ofBackground(18, 20, 24);

	bool startRequested = false;
	bool forceStartRequested = false;
	bool smokeRequested = false;
	bool writeConfigRequested = false;
	bool launchRequested = false;
	bool refreshRequested = false;

	gui.begin();
	if (ImGui::Begin("OpenAI Codex + local llama-server")) {
		std::lock_guard<std::mutex> lock(stateMutex);
		ImGui::TextWrapped("%s", status.empty() ? "ready" : status.c_str());
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
			rebuildLines();
		}
		if (ImGui::InputText("GGUF model", &modelPath)) {
			if (modelAlias.empty()) {
				modelAlias = ofxGgmlLlamaCodexLocal::modelAliasFromPath(modelPath);
			}
			refreshModelMetadata();
			rebuildLines();
		}
		ImGui::SameLine();
		if (ImGui::Button("Choose model")) {
			const auto selected = chooseFile("Choose GGUF model", modelPath);
			if (!selected.empty()) {
				modelPath = selected;
				modelAlias = ofxGgmlLlamaCodexLocal::modelAliasFromPath(modelPath);
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
		ImGui::InputInt("Model context window", &modelContextWindow);
		ImGui::InputInt("Auto compact tokens", &modelAutoCompactTokenLimit);
		ImGui::InputInt("Tool output tokens", &toolOutputTokenLimit);
		ImGui::InputInt("Startup timeout seconds", &startupTimeoutSeconds);
		ImGui::SliderFloat("Temperature", &temperature, 0.0f, 2.0f, "%.2f");
		ImGui::SliderFloat("Top P", &topP, 0.05f, 1.0f, "%.2f");
		ImGui::SliderFloat("Min P", &minP, 0.0f, 0.2f, "%.3f");
		ImGui::Separator();
		ImGui::TextUnformatted("Agent settings");
		ImGui::Checkbox("Multi-agent v2", &multiAgentV2Enabled);
		ImGui::InputInt("Max agents", &agentMaxConcurrentThreadsPerSession);
		ImGui::InputInt("Agent max depth", &agentMaxDepth);
		ImGui::InputInt("Agent min wait ms", &agentMinWaitTimeoutMs);
		ImGui::InputInt("Agent max wait ms", &agentMaxWaitTimeoutMs);
		ImGui::InputInt("Agent default wait ms", &agentDefaultWaitTimeoutMs);
		ImGui::Checkbox("No CUDA graphs", &noCudaGraphs);
		ImGui::Checkbox("Skip chat parsing", &skipChatParsing);
		ImGui::Checkbox("Auto-write Codex config", &autoConfig);

		ImGui::Separator();
		ImGui::BeginDisabled(running);
		startRequested = ImGui::Button("Start server");
		ImGui::SameLine();
		forceStartRequested = ImGui::Button("Force new");
		ImGui::SameLine();
		smokeRequested = ImGui::Button("Smoke endpoint");
		ImGui::SameLine();
		writeConfigRequested = ImGui::Button("Write config");
		ImGui::SameLine();
		launchRequested = ImGui::Button("Launch Codex");
		ImGui::EndDisabled();
		ImGui::SameLine();
		refreshRequested = ImGui::Button("Refresh");

		ImGui::Separator();
		ImGui::Text("server: %s", serverReady ? "ready" : "not ready");
		ImGui::Text("endpoint: %s", endpointReady ? "ready" : "not ready");
		ImGui::TextWrapped("wire_api: %s", wireApi.empty() ? "(not detected)" : wireApi.c_str());
		ImGui::TextWrapped("%s", wireApiProbeStatus.c_str());
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
	std::string requestModelAlias;
	int requestModelContextWindow = 40960;
	int requestModelAutoCompactTokenLimit = 30000;
	int requestToolOutputTokenLimit = 5000;
	int requestAgentMaxConcurrentThreadsPerSession = 1;
	int requestAgentMaxDepth = 1;
	int requestAgentMinWaitTimeoutMs = 2500;
	int requestAgentMaxWaitTimeoutMs = 120000;
	int requestAgentDefaultWaitTimeoutMs = 30000;
	bool requestMultiAgentV2Enabled = true;
	bool requestAutoConfig = false;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestCodexExe = codexExe;
		requestProfile = codexProfile.empty() ? "ofxggml_local" : codexProfile;
		requestModelAlias = modelAlias;
		requestModelContextWindow = modelContextWindow;
		requestModelAutoCompactTokenLimit = modelAutoCompactTokenLimit;
		requestToolOutputTokenLimit = toolOutputTokenLimit;
		requestAgentMaxConcurrentThreadsPerSession = agentMaxConcurrentThreadsPerSession;
		requestAgentMaxDepth = agentMaxDepth;
		requestAgentMinWaitTimeoutMs = agentMinWaitTimeoutMs;
		requestAgentMaxWaitTimeoutMs = agentMaxWaitTimeoutMs;
		requestAgentDefaultWaitTimeoutMs = agentDefaultWaitTimeoutMs;
		requestMultiAgentV2Enabled = multiAgentV2Enabled;
		requestAutoConfig = autoConfig;
	}

	if (requestAutoConfig && !syncCodexConfig()) {
		ofLogWarning(LogModule) << "Codex auto-config failed; attempting launch with existing config";
	}

	std::string arguments;
	if (ofxGgmlLlamaCodexLocal::executableSupportsArgument(requestCodexExe, "--no-alt-screen")) {
		arguments += "--no-alt-screen ";
	}
	if (ofxGgmlLlamaCodexLocal::executableSupportsArgument(requestCodexExe, "--disable")) {
		arguments += "--disable apps --disable image_generation --disable browser_use --disable computer_use --disable tool_search ";
	}
	arguments += "-p " + ofxGgmlLlamaCodexLocal::quoteArgument(requestProfile) + " ";
	arguments += "-c " + ofxGgmlLlamaCodexLocal::quoteArgument("web_search=\"disabled\"") + " ";
	arguments += "-c model_provider=llama_cpp ";
	arguments += "-c model_context_window=" + std::to_string(requestModelContextWindow) + " ";
	arguments += "-c model_auto_compact_token_limit=" + std::to_string(requestModelAutoCompactTokenLimit) + " ";
	arguments += "-c tool_output_token_limit=" + std::to_string(requestToolOutputTokenLimit) + " ";
	arguments += "-c features.multi_agent_v2.enabled=" +
		std::string(requestMultiAgentV2Enabled ? "true" : "false") + " ";
	arguments += "-c features.multi_agent_v2.max_concurrent_threads_per_session=" +
		std::to_string(requestAgentMaxConcurrentThreadsPerSession) + " ";
	arguments += "-c features.multi_agent_v2.min_wait_timeout_ms=" +
		std::to_string(requestAgentMinWaitTimeoutMs) + " ";
	arguments += "-c features.multi_agent_v2.max_wait_timeout_ms=" +
		std::to_string(requestAgentMaxWaitTimeoutMs) + " ";
	arguments += "-c features.multi_agent_v2.default_wait_timeout_ms=" +
		std::to_string(requestAgentDefaultWaitTimeoutMs) + " ";
	if (!requestMultiAgentV2Enabled) {
		arguments += "-c agents.max_threads=" +
			std::to_string(requestAgentMaxConcurrentThreadsPerSession) + " ";
	}
	arguments += "-c agents.max_depth=" + std::to_string(requestAgentMaxDepth) + " ";
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
	if (serverExe.empty() || !ofxGgmlLlamaCodexLocal::fileExists(serverExe)) {
		serverExe = ofxGgmlLlamaCodexLocal::discoverLlamaServer();
	}
	if (modelPath.empty() || !ofxGgmlLlamaCodexLocal::fileExists(modelPath)) {
		modelPath = ofxGgmlLlamaCodexLocal::discoverTextModel();
	}
	if (codexExe.empty() || !ofxGgmlLlamaCodexLocal::fileExists(codexExe)) {
		codexExe = ofxGgmlLlamaCodexLocal::discoverCodexExecutable();
	}
	if (modelAlias.empty()) {
		modelAlias = ofxGgmlLlamaCodexLocal::modelAliasFromPath(modelPath);
	}
	refreshModelMetadata();
	rebuildLines();
}

void ofApp::refreshModelMetadata() {
	modelLayerCount = 0;
	if (modelPath.empty() || !ofxGgmlLlamaCodexLocal::fileExists(modelPath)) {
		return;
	}
	const auto result = ofxGgmlModel().inspect(modelPath);
	if (result.isOk()) {
		modelLayerCount = result.value().layerCount;
	}
}

void ofApp::refreshServerStatus() {
	std::string requestServerUrl;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestServerUrl = serverUrl;
	}
	const auto probe = ofxGgmlLlamaCodexLocal::probeServerHealth(requestServerUrl, 2);
	std::lock_guard<std::mutex> lock(stateMutex);
	serverReady = probe.ready;
	if (serverReady) {
		wireApi = ofxGgmlLlamaCodexLocal::detectCodexWireApi(baseUrl);
		wireApiProbeStatus = "wire_api auto-detected as " + wireApi;
	} else {
		endpointReady = false;
		wireApiProbeStatus = "wire_api not available (server not ready)";
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
	modelContextWindow = preset.modelContextWindow;
	modelAutoCompactTokenLimit = preset.modelAutoCompactTokenLimit;
	toolOutputTokenLimit = preset.toolOutputTokenLimit;
	agentMaxConcurrentThreadsPerSession = preset.agentMaxConcurrentThreads;
	agentMaxDepth = preset.agentMaxDepth;
	agentMinWaitTimeoutMs = preset.agentMinWaitMs;
	agentMaxWaitTimeoutMs = preset.agentMaxWaitMs;
	agentDefaultWaitTimeoutMs = preset.agentDefaultWaitMs;
	startupTimeoutSeconds = preset.startupTimeoutSeconds;
	gpuLayersAll = true;
	multiAgentV2Enabled = true;
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
	config.multiAgentV2Enabled = multiAgentV2Enabled;
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
	settings.temperature = temperature;
	settings.topP = topP;
	settings.minP = minP;
	settings.noCudaGraphs = noCudaGraphs;
	settings.skipChatParsing = skipChatParsing;
	return settings;
}
