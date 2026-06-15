#include "ofApp.h"

#include "imgui_stdlib.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cctype>
#include <filesystem>
#include <functional>
#include <memory>
#include <sstream>
#include <thread>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace {
constexpr const char * LogModule = "ofxGgmlLlamaCodexLocalExample";

std::string toString(const std::filesystem::path & path) {
	return path.lexically_normal().string();
}

bool pathExists(const std::filesystem::path & path) {
	std::error_code error;
	return std::filesystem::is_regular_file(path, error);
}

std::filesystem::path executableDirectory() {
#if defined(_WIN32)
	std::wstring buffer(MAX_PATH, L'\0');
	DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
	while (length == buffer.size()) {
		buffer.resize(buffer.size() * 2);
		length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
	}
	if (length > 0) {
		buffer.resize(length);
		return std::filesystem::path(buffer).parent_path();
	}
#endif
	std::error_code error;
	return std::filesystem::current_path(error);
}

void addUniquePath(std::vector<std::filesystem::path> & paths, const std::filesystem::path & path) {
	if (path.empty()) {
		return;
	}
	const std::filesystem::path normalized = path.lexically_normal();
	for (const auto & existing : paths) {
		if (existing == normalized) {
			return;
		}
	}
	paths.push_back(normalized);
}

std::vector<std::filesystem::path> searchRoots() {
	std::vector<std::filesystem::path> roots;
	std::error_code error;
	addUniquePath(roots, executableDirectory());
	addUniquePath(roots, std::filesystem::current_path(error));
	const std::size_t initialCount = roots.size();
	for (std::size_t i = 0; i < initialCount; ++i) {
		std::filesystem::path parent = roots[i];
		for (int depth = 0; depth < 7 && !parent.empty(); ++depth) {
			addUniquePath(roots, parent);
			parent = parent.parent_path();
		}
	}
	return roots;
}

std::string findFirstFile(const std::vector<std::filesystem::path> & candidates) {
	for (const auto & candidate : candidates) {
		if (pathExists(candidate)) {
			return toString(candidate);
		}
	}
	return {};
}

std::string discoverLlamaServer() {
#if defined(_WIN32)
	const std::string executableName = "llama-server.exe";
#else
	const std::string executableName = "llama-server";
#endif
	const std::vector<std::filesystem::path> relativeDirectories = {
		"",
		"bin",
		"data/bin",
		"tools",
		"libs/llama/bin",
		"libs/llama.cpp/build/bin",
		"libs/llama.cpp/build/bin/Release",
		"libs/llama.cpp/build/bin/Debug"
	};

	std::vector<std::filesystem::path> candidates;
	for (const auto & root : searchRoots()) {
		for (const auto & relative : relativeDirectories) {
			candidates.push_back(root / relative / executableName);
		}
	}
	return findFirstFile(candidates);
}

std::string discoverTextModel() {
	const std::vector<std::filesystem::path> relativeDirectories = {
		"",
		"data",
		"data/models",
		"models",
		"../models",
		"ofxGgmlLlamaCodexLocalExample/bin/data",
		"ofxGgmlLlamaCodexLocalExample/bin/data/models",
		"ofxGgmlLlamaCodexLocalExample/models",
		"ofxGgmlTextExample/bin/data",
		"ofxGgmlTextExample/bin/data/models",
		"ofxGgmlTextExample/models",
		"ofxGgmlChatExample/bin/data",
		"ofxGgmlChatExample/bin/data/models",
		"ofxGgmlChatExample/models"
	};

	std::vector<std::string> models;
	for (const auto & root : searchRoots()) {
		for (const auto & relative : relativeDirectories) {
			const std::filesystem::path directory = (root / relative).lexically_normal();
			std::error_code error;
			if (!std::filesystem::is_directory(directory, error)) {
				continue;
			}
			for (const auto & entry : std::filesystem::directory_iterator(directory, error)) {
				if (error) {
					break;
				}
				if (entry.is_regular_file(error) && entry.path().extension() == ".gguf") {
					models.push_back(toString(entry.path()));
				}
			}
		}
	}
	std::sort(models.begin(), models.end());
	models.erase(std::unique(models.begin(), models.end()), models.end());
	return models.empty() ? std::string() : models.front();
}

std::string quoteShellPath(const std::string & value) {
	return "\"" + value + "\"";
}

std::string trimTrailingSlash(std::string value) {
	while (!value.empty() && value.back() == '/') {
		value.pop_back();
	}
	return value;
}

int serverHealthStatus(const std::string & serverUrl) {
	ofHttpRequest request(trimTrailingSlash(serverUrl) + "/health", "llama-server-health");
	request.method = ofHttpRequest::GET;
	request.timeoutSeconds = 1;
	ofURLFileLoader loader;
	const ofHttpResponse response = loader.handleRequest(request);
	return response.status;
}

bool isServerReady(const std::string & serverUrl) {
	const int status = serverHealthStatus(serverUrl);
	return status >= 200 && status < 300;
}

bool waitForServerReady(
	const std::string & serverUrl,
	int timeoutSeconds,
	const std::function<bool()> & shouldCancel) {
	const auto deadline = std::chrono::steady_clock::now() +
		std::chrono::seconds(std::max(1, timeoutSeconds));
	while (std::chrono::steady_clock::now() < deadline) {
		if (shouldCancel && shouldCancel()) {
			return false;
		}
		if (isServerReady(serverUrl)) {
			return true;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(500));
	}
	return isServerReady(serverUrl);
}

bool startBundledServer(
	const std::string & serverExe,
	const std::string & modelPath,
	const std::string & serverUrl,
	const std::string & modelAlias,
	int gpuLayers,
	int contextSize,
	bool noCudaGraphs,
	float temperature,
	float topP,
	float minP) {
	if (serverExe.empty() || modelPath.empty()) {
		return false;
	}
	const int port = [] (const std::string & value, int fallbackPort) {
		std::string normalized = value;
		while (!normalized.empty() && std::isspace(static_cast<unsigned char>(normalized.front()))) {
			normalized.erase(normalized.begin());
		}
		while (!normalized.empty() && std::isspace(static_cast<unsigned char>(normalized.back()))) {
			normalized.pop_back();
		}
		normalized = trimTrailingSlash(normalized);
		const std::size_t scheme = normalized.find("://");
		const std::size_t hostStart = scheme == std::string::npos ? 0 : scheme + 3;
		const std::size_t colon = normalized.find(':', hostStart);
		if (colon == std::string::npos) {
			return fallbackPort;
		}
		const std::size_t portStart = colon + 1;
		std::size_t portEnd = normalized.find('/', portStart);
		if (portEnd == std::string::npos) {
			portEnd = normalized.size();
		}
		try {
			return std::stoi(normalized.substr(portStart, portEnd - portStart));
		} catch (...) {
			return fallbackPort;
		}
	}(serverUrl, 8001);
#if defined(_WIN32)
	const std::filesystem::path exePath(serverExe);
	std::wstring command = L"\"" + exePath.wstring() + L"\" -m \"" +
		std::filesystem::path(modelPath).wstring() +
		L"\" --host 127.0.0.1 --port " + std::to_wstring(port) +
		L" -ngl " + std::to_wstring(std::max(0, gpuLayers)) +
		L" -c " + std::to_wstring(std::max(512, contextSize));
	if (!modelAlias.empty()) {
		command += L" --alias \"" + std::wstring(modelAlias.begin(), modelAlias.end()) + L"\"";
	}
	if (noCudaGraphs) {
		command += L" --no-cuda-graphs";
	}
	command += L" --temp " + std::to_wstring(temperature);
	command += L" --top-p " + std::to_wstring(topP);
	command += L" --min-p " + std::to_wstring(minP);

	STARTUPINFOW startupInfo {};
	startupInfo.cb = sizeof(startupInfo);
	startupInfo.dwFlags = STARTF_USESHOWWINDOW;
	startupInfo.wShowWindow = SW_HIDE;
	PROCESS_INFORMATION processInfo {};
	std::wstring workingDirectory = exePath.parent_path().wstring();
	const BOOL started = CreateProcessW(
		nullptr,
		command.data(),
		nullptr,
		nullptr,
		FALSE,
		CREATE_NO_WINDOW | DETACHED_PROCESS,
		nullptr,
		workingDirectory.empty() ? nullptr : workingDirectory.c_str(),
		&startupInfo,
		&processInfo);
	if (started) {
		CloseHandle(processInfo.hThread);
		CloseHandle(processInfo.hProcess);
	}
	return started == TRUE;
#else
	std::string command = quoteShellPath(serverExe) +
		" -m " + quoteShellPath(modelPath) +
		" --host 127.0.0.1 --port " + std::to_string(port) +
		" -ngl " + std::to_string(std::max(0, gpuLayers)) +
		" -c " + std::to_string(std::max(512, contextSize));
	if (!modelAlias.empty()) {
		command += " --alias " + quoteShellPath(modelAlias);
	}
	if (noCudaGraphs) {
		command += " --no-cuda-graphs";
	}
	command += " --temp " + std::to_string(temperature);
	command += " --top-p " + std::to_string(topP);
	command += " --min-p " + std::to_string(minP);
	command += " >/dev/null 2>&1 &";
	return std::system(command.c_str()) == 0;
#endif
}

} // namespace

void ofApp::setup() {
	ofSetWindowTitle("ofxGgmlLlama Codex Local Example");
	ofSetFrameRate(60);
	ofBackground(16);
	gui.setup(nullptr, false);

	baseUrl = getEnvOrDefault("OFXGGML_CODEX_BASE_URL", "http://127.0.0.1:8001/v1");
	modelAlias = getEnvOrDefault("OFXGGML_CODEX_MODEL", "unsloth/GLM-4.7-Flash");
	modelPath = normalizeEnvPath(envValue("OFXGGML_TEXT_MODEL"));
	serverExe = normalizeEnvPath(envValue("OFXGGML_LLAMA_SERVER"));
	gpuLayers = std::atoi(getEnvOrDefault("OFXGGML_CODEX_GPU_LAYERS", "999").c_str());
	contextSize = std::atoi(getEnvOrDefault("OFXGGML_CODEX_CONTEXT_SIZE", "131072").c_str());
	autoStartServer = getEnvOrDefault("OFXGGML_CODEX_AUTO_SERVER", "1") != "0";
	noCudaGraphs = getEnvOrDefault("OFXGGML_CODEX_NO_CUDA_GRAPHS", "1") != "0";
	temperature = std::stof(getEnvOrDefault("OFXGGML_CODEX_TEMP", "1.0"));
	topP = std::stof(getEnvOrDefault("OFXGGML_CODEX_TOP_P", "0.95"));
	minP = std::stof(getEnvOrDefault("OFXGGML_CODEX_MIN_P", "0.01"));
	applyBaseUrlToServerUrl();
	refreshRuntimeDiscovery();
	refreshServerStatus();
	rebuildLines();
	endpointStatus = "endpoint smoke not run";

	ofLogNotice(LogModule) << "Codex endpoint: " << baseUrl;
	ofLogNotice(LogModule) << "Codex model alias: " << modelAlias;
	if (autoStartServer && !serverReady) {
		requestStartServer(false);
	}
}

void ofApp::draw() {
	std::string baseUrlEdit;
	std::string serverUrlEdit;
	std::string modelAliasEdit;
	std::string modelPathEdit;
	std::string serverExeEdit;
	std::string statusSnapshot;
	std::string endpointStatusSnapshot;
	std::string endpointOutputSnapshot;
	std::vector<std::string> lineSnapshot;
	bool runningSnapshot = false;
	bool serverReadySnapshot = false;
	bool endpointReadySnapshot = false;
	bool autoStartSnapshot = false;
	bool noCudaGraphsSnapshot = false;
	int gpuLayersSnapshot = 0;
	int contextSizeSnapshot = 0;
	int startupTimeoutSnapshot = 0;
	float temperatureSnapshot = 0.0f;
	float topPSnapshot = 0.0f;
	float minPSnapshot = 0.0f;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		baseUrlEdit = baseUrl;
		serverUrlEdit = serverUrl;
		modelAliasEdit = modelAlias;
		modelPathEdit = modelPath;
		serverExeEdit = serverExe;
		statusSnapshot = status;
		endpointStatusSnapshot = endpointStatus;
		endpointOutputSnapshot = endpointOutput;
		lineSnapshot = lines;
		runningSnapshot = running;
		serverReadySnapshot = serverReady;
		endpointReadySnapshot = endpointReady;
		autoStartSnapshot = autoStartServer;
		noCudaGraphsSnapshot = noCudaGraphs;
		gpuLayersSnapshot = gpuLayers;
		contextSizeSnapshot = contextSize;
		startupTimeoutSnapshot = startupTimeoutSeconds;
		temperatureSnapshot = temperature;
		topPSnapshot = topP;
		minPSnapshot = minP;
	}

	bool startRequested = false;
	bool forceStartRequested = false;
	bool recheckRequested = false;
	bool smokeRequested = false;
	bool rediscoverRequested = false;

	ofBackground(16);
	gui.begin();
	const ImVec2 display = ImGui::GetIO().DisplaySize;
	ImGui::SetNextWindowPos(ImVec2(18.0f, 18.0f), ImGuiCond_Once);
	ImGui::SetNextWindowSize(
		ImVec2(std::min(1040.0f, std::max(420.0f, display.x - 36.0f)),
			std::min(720.0f, std::max(360.0f, display.y - 36.0f))),
		ImGuiCond_Once);

	if (ImGui::Begin("OpenAI Codex + local llama-server")) {
		ImGui::TextColored(
			serverReadySnapshot ? ImVec4(0.70f, 0.92f, 0.70f, 1.0f) : ImVec4(0.90f, 0.72f, 0.45f, 1.0f),
			"%s",
			statusSnapshot.empty() ? "checking llama-server..." : statusSnapshot.c_str());
		ImGui::SameLine();
		ImGui::TextDisabled(serverReadySnapshot ? "ready" : "not ready");
		ImGui::TextColored(
			endpointReadySnapshot ? ImVec4(0.70f, 0.92f, 0.70f, 1.0f) : ImVec4(0.70f, 0.78f, 0.90f, 1.0f),
			"%s",
			endpointStatusSnapshot.empty() ? "endpoint smoke not run" : endpointStatusSnapshot.c_str());

		if (runningSnapshot) {
			ImGui::BeginDisabled();
		}
		if (ImGui::Button("Start server")) {
			startRequested = true;
		}
		ImGui::SameLine();
		if (ImGui::Button("Force new")) {
			forceStartRequested = true;
		}
		ImGui::SameLine();
		if (ImGui::Button("Recheck")) {
			recheckRequested = true;
		}
		ImGui::SameLine();
		if (ImGui::Button("Test endpoint")) {
			smokeRequested = true;
		}
		ImGui::SameLine();
		if (ImGui::Button("Rediscover")) {
			rediscoverRequested = true;
		}
		if (runningSnapshot) {
			ImGui::EndDisabled();
		}

		ImGui::Separator();
		if (runningSnapshot) {
			ImGui::BeginDisabled();
		}
		if (ImGui::Checkbox("Auto-start local server", &autoStartSnapshot)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			autoStartServer = autoStartSnapshot;
		}
		ImGui::SetNextItemWidth(-1.0f);
		if (ImGui::InputText("Codex base URL", &baseUrlEdit)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			baseUrl = normalizeEnvPath(baseUrlEdit);
			applyBaseUrlToServerUrl();
			rebuildLines();
		}
		ImGui::SetNextItemWidth(-1.0f);
		if (ImGui::InputText("Server root", &serverUrlEdit)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			serverUrl = serverRootFromBaseUrl(serverUrlEdit);
			applyServerUrlToBaseUrl();
			rebuildLines();
		}
		ImGui::SetNextItemWidth(-1.0f);
		if (ImGui::InputText("Codex model alias", &modelAliasEdit)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			modelAlias = normalizeEnvPath(modelAliasEdit);
			rebuildLines();
		}
		ImGui::SetNextItemWidth(-1.0f);
		if (ImGui::InputText("GGUF model path", &modelPathEdit)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			modelPath = normalizeEnvPath(modelPathEdit);
		}
		ImGui::SetNextItemWidth(-1.0f);
		if (ImGui::InputText("llama-server path", &serverExeEdit)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			serverExe = normalizeEnvPath(serverExeEdit);
		}
		ImGui::SetNextItemWidth(180.0f);
		if (ImGui::InputInt("GPU layers", &gpuLayersSnapshot)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			gpuLayers = gpuLayersSnapshot;
		}
		ImGui::SameLine();
		ImGui::SetNextItemWidth(180.0f);
		if (ImGui::InputInt("Context", &contextSizeSnapshot)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			contextSize = contextSizeSnapshot;
		}
		ImGui::SameLine();
		ImGui::SetNextItemWidth(180.0f);
		if (ImGui::InputInt("Startup timeout", &startupTimeoutSnapshot)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			startupTimeoutSeconds = startupTimeoutSnapshot;
		}
		if (ImGui::Checkbox("Disable CUDA graphs", &noCudaGraphsSnapshot)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			noCudaGraphs = noCudaGraphsSnapshot;
		}
		ImGui::SetNextItemWidth(160.0f);
		if (ImGui::SliderFloat("Temp", &temperatureSnapshot, 0.0f, 2.0f, "%.2f")) {
			std::lock_guard<std::mutex> lock(stateMutex);
			temperature = temperatureSnapshot;
		}
		ImGui::SameLine();
		ImGui::SetNextItemWidth(160.0f);
		if (ImGui::SliderFloat("Top-p", &topPSnapshot, 0.1f, 1.0f, "%.2f")) {
			std::lock_guard<std::mutex> lock(stateMutex);
			topP = topPSnapshot;
		}
		ImGui::SameLine();
		ImGui::SetNextItemWidth(160.0f);
		if (ImGui::SliderFloat("Min-p", &minPSnapshot, 0.0f, 0.2f, "%.2f")) {
			std::lock_guard<std::mutex> lock(stateMutex);
			minP = minPSnapshot;
		}
		if (runningSnapshot) {
			ImGui::EndDisabled();
		}

		ImGui::Separator();
		if (!endpointOutputSnapshot.empty()) {
			ImGui::TextWrapped("Smoke output: %s", endpointOutputSnapshot.c_str());
			ImGui::Separator();
		}
		ImGui::TextUnformatted("Codex config.toml");
		ImGui::BeginChild("codex-local-config", ImVec2(0.0f, 0.0f), true);
		for (const auto & line : lineSnapshot) {
			if (line.empty()) {
				ImGui::Spacing();
			} else {
				ImGui::TextWrapped("%s", line.c_str());
			}
		}
		ImGui::EndChild();
	}
	ImGui::End();
	gui.end();
	gui.draw();

	if (rediscoverRequested) {
		refreshRuntimeDiscovery();
		rebuildLines();
	}
	if (recheckRequested) {
		refreshServerStatus();
	}
	if (smokeRequested) {
		requestEndpointSmoke();
	}
	if (startRequested) {
		requestStartServer(false);
	}
	if (forceStartRequested) {
		requestStartServer(true);
	}
}

void ofApp::keyPressed(int key) {
	if (ImGui::GetCurrentContext() && ImGui::GetIO().WantCaptureKeyboard) {
		return;
	}
	if (key == 'r' || key == 'R') {
		refreshRuntimeDiscovery();
		refreshServerStatus();
		rebuildLines();
		ofLogNotice(LogModule) << "refreshed local Codex runtime display";
	}
	if (key == 's' || key == 'S') {
		requestStartServer(false);
	}
	if (key == 't' || key == 'T') {
		requestEndpointSmoke();
	}
}

void ofApp::exit() {
	cancelRequested = true;
	if (worker.joinable()) {
		worker.join();
	}
}

void ofApp::requestStartServer(bool force) {
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		if (running) {
			status = "llama-server start is already running";
			return;
		}
	}
	if (worker.joinable()) {
		worker.join();
	}
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		running = true;
		cancelRequested = false;
		status = force ? "starting a new llama-server..." : "checking llama-server...";
	}
	worker = std::thread(&ofApp::runStartServerWorker, this, force);
}

void ofApp::runStartServerWorker(bool force) {
	std::string requestServerUrl;
	std::string requestModelPath;
	std::string requestServerExe;
	std::string requestModelAlias;
	int requestGpuLayers = 0;
	int requestContextSize = 0;
	int requestStartupTimeout = 0;
	bool requestNoCudaGraphs = false;
	float requestTemperature = 0.0f;
	float requestTopP = 0.0f;
	float requestMinP = 0.0f;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestServerUrl = serverUrl;
		requestModelPath = modelPath;
		requestServerExe = serverExe;
		requestModelAlias = modelAlias;
		requestGpuLayers = gpuLayers;
		requestContextSize = contextSize;
		requestStartupTimeout = startupTimeoutSeconds;
		requestNoCudaGraphs = noCudaGraphs;
		requestTemperature = temperature;
		requestTopP = topP;
		requestMinP = minP;
	}

	if (!force && isServerReady(requestServerUrl)) {
		std::lock_guard<std::mutex> lock(stateMutex);
		serverReady = true;
		status = "llama-server is already ready at " + requestServerUrl;
		running = false;
		return;
	}
	if (requestServerExe.empty() || !fileExists(requestServerExe)) {
		std::lock_guard<std::mutex> lock(stateMutex);
		serverReady = false;
		status = "llama-server executable not found; build llama.cpp or set the path";
		running = false;
		return;
	}
	if (requestModelPath.empty() || !fileExists(requestModelPath)) {
		std::lock_guard<std::mutex> lock(stateMutex);
		serverReady = false;
		status = "GGUF model not found; set a model path or place one under models";
		running = false;
		return;
	}

	ofLogNotice(LogModule)
		<< "starting llama-server\n"
		<< "exe: " << requestServerExe << "\n"
		<< "model: " << requestModelPath << "\n"
		<< "url: " << requestServerUrl << "\n"
		<< "alias: " << requestModelAlias;

	if (!startBundledServer(
		requestServerExe,
		requestModelPath,
		requestServerUrl,
		requestModelAlias,
		requestGpuLayers,
		requestContextSize,
		requestNoCudaGraphs,
		requestTemperature,
		requestTopP,
		requestMinP)) {
		std::lock_guard<std::mutex> lock(stateMutex);
		serverReady = false;
		status = "failed to start llama-server";
		running = false;
		return;
	}

	{
		std::lock_guard<std::mutex> lock(stateMutex);
		status = "waiting for llama-server at " + requestServerUrl;
	}
	const bool ready = waitForServerReady(
		requestServerUrl,
		requestStartupTimeout,
		[this]() { return cancelRequested.load(); });
	std::lock_guard<std::mutex> lock(stateMutex);
	serverReady = ready;
	status = ready
		? "llama-server ready for Codex at " + baseUrl
		: "llama-server did not become ready at " + requestServerUrl;
	running = false;
}

void ofApp::requestEndpointSmoke() {
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		if (running) {
			endpointStatus = "another operation is already running";
			return;
		}
	}
	if (worker.joinable()) {
		worker.join();
	}
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		running = true;
		cancelRequested = false;
		endpointReady = false;
		endpointOutput.clear();
		endpointStatus = "testing OpenAI-compatible endpoint...";
	}
	worker = std::thread(&ofApp::runEndpointSmokeWorker, this);
}

void ofApp::runEndpointSmokeWorker() {
	std::string requestBaseUrl;
	std::string requestModelAlias;
	float requestTemperature = 0.0f;
	float requestTopP = 0.0f;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestBaseUrl = baseUrl;
		requestModelAlias = modelAlias;
		requestTemperature = temperature;
		requestTopP = topP;
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
		endpointOutput = trimCopy(result.text);
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

void ofApp::refreshRuntimeDiscovery() {
	std::lock_guard<std::mutex> lock(stateMutex);
	if (serverExe.empty() || !fileExists(serverExe)) {
		serverExe = discoverLlamaServer();
	}
	if (modelPath.empty() || !fileExists(modelPath)) {
		modelPath = discoverTextModel();
	}
	if (status.empty()) {
		status = "runtime discovery complete";
	}
}

void ofApp::refreshServerStatus() {
	const std::string requestServerUrl = [&]() {
		std::lock_guard<std::mutex> lock(stateMutex);
		return serverUrl;
	}();
	const bool ready = isServerReady(requestServerUrl);
	std::lock_guard<std::mutex> lock(stateMutex);
	serverReady = ready;
	if (!ready) {
		endpointReady = false;
	}
	status = ready
		? "llama-server ready for Codex at " + baseUrl
		: "llama-server is not reachable at " + requestServerUrl;
}

void ofApp::applyBaseUrlToServerUrl() {
	serverUrl = serverRootFromBaseUrl(baseUrl);
}

void ofApp::applyServerUrlToBaseUrl() {
	baseUrl = baseUrlFromServerRoot(serverUrl);
}

void ofApp::appendWrapped(const std::string & text, std::size_t maxChars) {
	if (text.size() <= maxChars) {
		lines.push_back(text);
		return;
	}

	std::istringstream words(text);
	std::string word;
	std::string line;
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

void ofApp::rebuildLines() {
	lines.clear();
	lines.push_back("[model_providers.llama_cpp]");
	lines.push_back("name = \"llama.cpp local\"");
	lines.push_back("base_url = \"" + baseUrl + "\"");
	lines.push_back("wire_api = \"responses\"");
	lines.push_back("stream_idle_timeout_ms = 10000000");
	lines.push_back("");
	lines.push_back("[profiles.ofxggml_local]");
	lines.push_back("model = \"" + modelAlias + "\"");
	lines.push_back("model_provider = \"llama_cpp\"");
	lines.push_back("");
	lines.push_back("Runtime");
	lines.push_back("  server root: " + serverUrl);
	lines.push_back("  GGUF model:  " + (modelPath.empty() ? "(not found)" : modelPath));
	lines.push_back("  server exe:  " + (serverExe.empty() ? "(not found)" : serverExe));
	lines.push_back("  GPU layers:  " + std::to_string(gpuLayers));
	lines.push_back("  context:     " + std::to_string(contextSize));
	appendWrapped("Use this provider/profile with Codex after the server is ready and the endpoint smoke has answered. The example starts llama-server locally but does not edit Codex config.", 96);
}

std::string ofApp::envValue(const char * name) {
#if defined(_WIN32)
	char * value = nullptr;
	std::size_t length = 0;
	if (_dupenv_s(&value, &length, name) != 0 || !value) {
		return {};
	}
	std::string result(value, length > 0 ? length - 1 : 0);
	free(value);
	return result;
#else
	const char * value = std::getenv(name);
	return value ? std::string(value) : std::string();
#endif
}

std::string ofApp::getEnvOrDefault(const char * name, const std::string & fallback) {
	const std::string value = envValue(name);
	return value.empty() ? fallback : value;
}

std::string ofApp::normalizeEnvPath(const std::string & path) {
	return trimCopy(path);
}

std::string ofApp::trimCopy(const std::string & value) {
	std::size_t first = 0;
	while (first < value.size() && std::isspace(static_cast<unsigned char>(value[first]))) {
		++first;
	}
	std::size_t last = value.size();
	while (last > first && std::isspace(static_cast<unsigned char>(value[last - 1]))) {
		--last;
	}
	std::string normalized = value.substr(first, last - first);
	if (normalized.size() >= 2 && normalized.front() == '"' && normalized.back() == '"') {
		normalized = normalized.substr(1, normalized.size() - 2);
	}
	return normalized;
}

std::string ofApp::serverRootFromBaseUrl(const std::string & value) {
	std::string normalized = trimTrailingSlash(trimCopy(value));
	const std::string suffix = "/v1";
	if (normalized.size() >= suffix.size() &&
		normalized.compare(normalized.size() - suffix.size(), suffix.size(), suffix) == 0) {
		normalized.resize(normalized.size() - suffix.size());
	}
	return normalized.empty() ? "http://127.0.0.1:8001" : normalized;
}

std::string ofApp::baseUrlFromServerRoot(const std::string & value) {
	return trimTrailingSlash(serverRootFromBaseUrl(value)) + "/v1";
}

int ofApp::serverPortFromUrl(const std::string & value, int fallbackPort) {
	const std::string normalized = trimTrailingSlash(value);
	const std::size_t scheme = normalized.find("://");
	const std::size_t hostStart = scheme == std::string::npos ? 0 : scheme + 3;
	const std::size_t colon = normalized.find(':', hostStart);
	if (colon == std::string::npos) {
		return fallbackPort;
	}
	const std::size_t portStart = colon + 1;
	std::size_t portEnd = normalized.find('/', portStart);
	if (portEnd == std::string::npos) {
		portEnd = normalized.size();
	}
	try {
		return std::stoi(normalized.substr(portStart, portEnd - portStart));
	} catch (...) {
		return fallbackPort;
	}
}

bool ofApp::fileExists(const std::string & path) {
	return !path.empty() && ofFile::doesFileExist(path, false);
}
