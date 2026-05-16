#include "ofApp.h"

#include "imgui_stdlib.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdlib>
#include <cctype>
#include <cwctype>
#include <fstream>
#include <cstdio>
#include <filesystem>
#include <functional>
#include <memory>
#include <sstream>
#include <thread>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <tlhelp32.h>
#include <windows.h>
#endif

namespace {
constexpr const char * LogModule = "ofxGgmlLlamaCodexLocalExample";

struct ServerProbe {
	bool reachable = false;
	bool ready = false;
	int status = 0;
	std::string message;
};

std::string toString(const std::filesystem::path & path) {
	return path.lexically_normal().string();
}

bool pathExists(const std::filesystem::path & path) {
	std::error_code error;
	return std::filesystem::is_regular_file(path, error);
}

std::string chooseFile(const std::string & title, const std::string & currentPath) {
	const auto startPath = currentPath.empty() ? ofToDataPath("", true) : currentPath;
	auto result = ofSystemLoadDialog(title, false, startPath);
	return result.bSuccess ? result.getPath() : std::string();
}

std::string readAllText(const std::string & filePath) {
	std::ifstream input(filePath, std::ios::binary);
	if (!input.is_open()) {
		return {};
	}
	std::ostringstream stream;
	stream << input.rdbuf();
	return stream.str();
}

bool writeAllText(const std::string & filePath, const std::string & text) {
	std::ofstream output(filePath, std::ios::binary | std::ofstream::trunc);
	if (!output.is_open()) {
		return false;
	}
	output << text;
	return output.good();
}

std::string codexConfigPath() {
#if defined(_WIN32)
	const char * home = getenv("USERPROFILE");
	const std::string base = home ? home : "";
#else
	const char * home = getenv("HOME");
	const std::string base = home ? home : "";
#endif
	if (base.empty()) {
		return ".codex/config.toml";
	}
	const std::filesystem::path dir = std::filesystem::path(base) / ".codex";
	std::error_code error;
	std::filesystem::create_directories(dir, error);
	if (error) {
		return {};
	}
	return toString((dir / "config.toml"));
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

ServerProbe probeServerHealth(const std::string & serverUrl, int timeoutSeconds = 2) {
	ServerProbe probe;
	ofHttpRequest request(trimTrailingSlash(serverUrl) + "/health", "llama-server-health");
	request.method = ofHttpRequest::GET;
	request.timeoutSeconds = std::max(1, timeoutSeconds);
	ofURLFileLoader loader;
	const ofHttpResponse response = loader.handleRequest(request);
	probe.status = response.status;
	probe.reachable = response.status > 0;
	probe.ready = response.status >= 200 && response.status < 300;
	if (!response.error.empty()) {
		probe.message = response.error;
	} else {
		probe.message = response.data.getText();
	}
	probe.message = trimTrailingSlash(probe.message);
	return probe;
}

bool isServerReady(const std::string & serverUrl) {
	return probeServerHealth(serverUrl, 2).ready;
}

ServerProbe waitForServerReady(
	const std::string & serverUrl,
	int timeoutSeconds,
	const std::function<bool()> & shouldCancel) {
	const auto deadline = std::chrono::steady_clock::now() +
		std::chrono::seconds(std::max(1, timeoutSeconds));
	ServerProbe lastProbe;
	while (std::chrono::steady_clock::now() < deadline) {
		if (shouldCancel && shouldCancel()) {
			lastProbe.message = "cancelled";
			return lastProbe;
		}
		lastProbe = probeServerHealth(serverUrl, 2);
		if (lastProbe.ready) {
			return lastProbe;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(500));
	}
	return probeServerHealth(serverUrl, 2);
}

std::string describeProbe(const ServerProbe & probe) {
	std::string detail;
	if (probe.reachable) {
		detail = "HTTP " + std::to_string(probe.status);
	} else {
		detail = "unreachable";
	}
	if (!probe.message.empty()) {
		detail += ": " + probe.message;
	}
	return detail;
}

std::string readCommandOutput(const std::string & command) {
	std::array<char, 512> buffer {};
	std::string output;
#if defined(_WIN32)
	FILE * pipe = _popen(command.c_str(), "r");
#else
	FILE * pipe = popen(command.c_str(), "r");
#endif
	if (!pipe) {
		return output;
	}
	while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe)) {
		output += buffer.data();
	}
#if defined(_WIN32)
	_pclose(pipe);
#else
	pclose(pipe);
#endif
	return output;
}

bool serverSupportsArgument(const std::string & serverExe, const std::string & argument) {
	if (serverExe.empty() || argument.empty()) {
		return false;
	}
	const std::string output = readCommandOutput(quoteShellPath(serverExe) + " --help 2>&1");
	if (output.empty()) {
		return true;
	}
	return output.find(argument) != std::string::npos;
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
	const bool includeNoCudaGraphs = noCudaGraphs && serverSupportsArgument(serverExe, "--no-cuda-graphs");
	if (noCudaGraphs && !includeNoCudaGraphs) {
		ofLogWarning(LogModule)
			<< "llama-server does not support --no-cuda-graphs; using server CUDA graph default";
	}
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
	if (includeNoCudaGraphs) {
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
	if (includeNoCudaGraphs) {
		command += " --no-cuda-graphs";
	}
	command += " --temp " + std::to_string(temperature);
	command += " --top-p " + std::to_string(topP);
	command += " --min-p " + std::to_string(minP);
	command += " >/dev/null 2>&1 &";
	return std::system(command.c_str()) == 0;
#endif
}

#if defined(_WIN32)
std::wstring lowerWide(std::wstring value) {
	std::transform(
		value.begin(),
		value.end(),
		value.begin(),
		[](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
	return value;
}

std::wstring canonicalWidePath(const std::string & path) {
	if (path.empty()) {
		return {};
	}
	std::error_code error;
	const auto canonical = std::filesystem::weakly_canonical(std::filesystem::path(path), error);
	const auto normalized = error ? std::filesystem::path(path).lexically_normal() : canonical;
	return lowerWide(normalized.wstring());
}

std::wstring processImagePath(DWORD processId, HANDLE processHandle) {
	std::wstring imagePath(MAX_PATH, L'\0');
	DWORD size = static_cast<DWORD>(imagePath.size());
	while (!QueryFullProcessImageNameW(processHandle, 0, imagePath.data(), &size) &&
		GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
		imagePath.resize(imagePath.size() * 2);
		size = static_cast<DWORD>(imagePath.size());
	}
	if (size == 0) {
		(void)processId;
		return {};
	}
	imagePath.resize(size);
	return lowerWide(std::filesystem::path(imagePath).lexically_normal().wstring());
}

int terminateMatchingServerProcesses(const std::string & serverExe) {
	const std::wstring targetPath = canonicalWidePath(serverExe);
	if (targetPath.empty()) {
		return 0;
	}
	int terminated = 0;
	const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (snapshot == INVALID_HANDLE_VALUE) {
		return 0;
	}
	PROCESSENTRY32W entry {};
	entry.dwSize = sizeof(entry);
	if (Process32FirstW(snapshot, &entry)) {
		do {
			if (entry.th32ProcessID == GetCurrentProcessId()) {
				continue;
			}
			HANDLE process = OpenProcess(
				PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE,
				FALSE,
				entry.th32ProcessID);
			if (!process) {
				continue;
			}
			const std::wstring imagePath = processImagePath(entry.th32ProcessID, process);
			if (!imagePath.empty() && imagePath == targetPath) {
				if (TerminateProcess(process, 0)) {
					++terminated;
				}
			}
			CloseHandle(process);
		} while (Process32NextW(snapshot, &entry));
	}
	CloseHandle(snapshot);
	return terminated;
}
#else
int terminateMatchingServerProcesses(const std::string &) {
	return 0;
}
#endif

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
	autoConfig = getEnvOrDefault("OFXGGML_CODEX_AUTO_CONFIG", "1") != "0";
	noCudaGraphs = getEnvOrDefault("OFXGGML_CODEX_NO_CUDA_GRAPHS", "0") != "0";
	temperature = std::stof(getEnvOrDefault("OFXGGML_CODEX_TEMP", "1.0"));
	topP = std::stof(getEnvOrDefault("OFXGGML_CODEX_TOP_P", "0.95"));
	minP = std::stof(getEnvOrDefault("OFXGGML_CODEX_MIN_P", "0.01"));
	startupTimeoutSeconds = std::atoi(getEnvOrDefault("OFXGGML_CODEX_STARTUP_TIMEOUT", "300").c_str());
	if (startupTimeoutSeconds <= 0) {
		startupTimeoutSeconds = 300;
	}
	applyBaseUrlToServerUrl();
	refreshRuntimeDiscovery();
	refreshServerStatus();
	rebuildLines();
	if (configPath.empty()) {
		configPath = codexConfigPath();
	}
	if (configPath.empty()) {
		configWriteStatus = "Could not resolve local Codex config path";
	}
	else {
		configWriteStatus = "Codex config path: " + configPath;
	}
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
	bool autoConfigSnapshot = false;
	bool noCudaGraphsSnapshot = false;
	std::string configPathSnapshot;
	std::string configWriteStatusSnapshot;
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
		autoConfigSnapshot = autoConfig;
		noCudaGraphsSnapshot = noCudaGraphs;
		configPathSnapshot = configPath;
		configWriteStatusSnapshot = configWriteStatus;
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
	bool writeConfigRequested = false;
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
		if (ImGui::Checkbox("Auto-write Codex config", &autoConfigSnapshot)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			autoConfig = autoConfigSnapshot;
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
		if (ImGui::Button("Choose GGUF Model", ImVec2(150.0f, 0.0f))) {
			const auto selectedPath = chooseFile("Choose GGUF model", modelPathEdit);
			if (!selectedPath.empty()) {
				std::lock_guard<std::mutex> lock(stateMutex);
				modelPath = normalizeEnvPath(selectedPath);
				rebuildLines();
			}
		}
		ImGui::SetNextItemWidth(-1.0f);
		if (ImGui::InputText("llama-server path", &serverExeEdit)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			serverExe = normalizeEnvPath(serverExeEdit);
		}
		if (ImGui::Button("Choose llama-server", ImVec2(150.0f, 0.0f))) {
			const auto selectedPath = chooseFile("Choose llama-server executable", serverExeEdit);
			if (!selectedPath.empty()) {
				std::lock_guard<std::mutex> lock(stateMutex);
				serverExe = normalizeEnvPath(selectedPath);
				rebuildLines();
			}
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
		if (ImGui::Button("Write Codex config")) {
			writeConfigRequested = true;
		}
		if (!configWriteStatusSnapshot.empty()) {
			ImGui::TextWrapped("%s", configWriteStatusSnapshot.c_str());
		}
		if (!configPathSnapshot.empty()) {
			ImGui::TextWrapped("Config file: %s", configPathSnapshot.c_str());
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
	if (writeConfigRequested) {
		syncCodexConfig();
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
	bool requestAutoConfig = false;
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
		requestAutoConfig = autoConfig;
	}

	if (!force && isServerReady(requestServerUrl)) {
		if (requestAutoConfig && syncCodexConfig()) {
			std::lock_guard<std::mutex> lock(stateMutex);
			configWriteStatus = "Auto config applied to " + configPath;
		}
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
	if (force) {
		const int terminated = terminateMatchingServerProcesses(requestServerExe);
		if (terminated > 0) {
			ofLogNotice(LogModule)
				<< "stopped " << terminated << " existing llama-server process"
				<< (terminated == 1 ? "" : "es")
				<< " before restart";
			std::this_thread::sleep_for(std::chrono::milliseconds(750));
		}
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
	const ServerProbe probe = waitForServerReady(
		requestServerUrl,
		requestStartupTimeout,
		[this]() { return cancelRequested.load(); });
	if (probe.ready && requestAutoConfig) {
		if (!syncCodexConfig()) {
			ofLogWarning(LogModule) << "automatic Codex config update failed";
		}
	}
	std::lock_guard<std::mutex> lock(stateMutex);
	serverReady = probe.ready;
	status = probe.ready
		? "llama-server ready for Codex at " + baseUrl
		: "llama-server did not become ready at " + requestServerUrl + " (" + describeProbe(probe) + ")";
	running = false;
}

bool ofApp::replaceSection(std::string & configText, const std::string & sectionName) {
	const std::string sectionHeader = "[" + sectionName + "]";
	std::istringstream input(configText);
	std::ostringstream output;
	bool inTargetSection = false;
	bool sectionFound = false;
	std::string line;

	while (std::getline(input, line)) {
		const std::string trimmed = trimCopy(line);
		const bool isSectionHeader = !trimmed.empty() &&
			trimmed.front() == '[' &&
			trimmed.back() == ']';
		if (inTargetSection) {
			if (isSectionHeader) {
				inTargetSection = false;
			} else {
				continue;
			}
		}
		if (!inTargetSection && trimmed == sectionHeader) {
			sectionFound = true;
			inTargetSection = true;
			continue;
		}
		output << line << '\n';
	}

	configText = output.str();
	return sectionFound;
}

void ofApp::appendSection(std::string & configText, const std::string & sectionBody) {
	if (!configText.empty() && configText.back() != '\n') {
		configText.push_back('\n');
	}
	configText += sectionBody;
	if (!sectionBody.empty() && sectionBody.back() != '\n') {
		configText.push_back('\n');
	}
}

bool ofApp::syncCodexConfig() {
	std::string snapshotBaseUrl;
	std::string snapshotModelAlias;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		snapshotBaseUrl = baseUrl;
		snapshotModelAlias = modelAlias;
		if (configPath.empty()) {
			configPath = codexConfigPath();
		}
	}

	if (snapshotBaseUrl.empty() || snapshotModelAlias.empty()) {
		std::lock_guard<std::mutex> lock(stateMutex);
		configWriteStatus = "Cannot write Codex config: base URL and model alias are required";
		return false;
	}
	if (configPath.empty()) {
		std::lock_guard<std::mutex> lock(stateMutex);
		configWriteStatus = "Cannot write Codex config: failed to resolve path";
		return false;
	}

	const std::string existing = readAllText(configPath);
	const std::string providersSection = "[model_providers.llama_cpp]\n"
		"name = \"llama.cpp local\"\n"
		"base_url = \"" + snapshotBaseUrl + "\"\n"
		"wire_api = \"responses\"\n"
		"stream_idle_timeout_ms = 10000000\n";
	const std::string profilesSection = "[profiles.ofxggml_local]\n"
		"model = \"" + snapshotModelAlias + "\"\n"
		"model_provider = \"llama_cpp\"\n";

	bool updatedExisting = false;
	std::string updatedText = existing;
	const bool removedProvider = replaceSection(updatedText, "model_providers.llama_cpp");
	const bool removedProfile = replaceSection(updatedText, "profiles.ofxggml_local");
	updatedExisting = removedProvider || removedProfile || existing.empty();
	appendSection(updatedText, providersSection);
	appendSection(updatedText, profilesSection);

	if (!writeAllText(configPath, updatedText)) {
		std::lock_guard<std::mutex> lock(stateMutex);
		configWriteStatus = "Failed to write config file " + configPath;
		return false;
	}
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		configWriteStatus = updatedExisting
			? "Updated Codex config sections in " + configPath
			: "Created Codex config in " + configPath;
	}
	return true;
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
	bool requestAutoConfig = false;
	float requestTemperature = 0.0f;
	float requestTopP = 0.0f;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestBaseUrl = baseUrl;
		requestModelAlias = modelAlias;
		requestAutoConfig = autoConfig;
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
	const bool syncedConfig = result && requestAutoConfig && syncCodexConfig();

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
		if (requestAutoConfig) {
			endpointStatus += syncedConfig
				? " (Codex config updated)"
				: " (Codex config update skipped)";
		}
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
	const ServerProbe probe = probeServerHealth(requestServerUrl, 2);
	std::lock_guard<std::mutex> lock(stateMutex);
	serverReady = probe.ready;
	if (!probe.ready) {
		endpointReady = false;
	}
	status = probe.ready
		? "llama-server ready for Codex at " + baseUrl
		: "llama-server is not ready at " + requestServerUrl + " (" + describeProbe(probe) + ")";
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
	appendWrapped("Use this provider/profile with Codex after the server is ready. You can auto-write the same sections to local config from the UI.", 96);
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
