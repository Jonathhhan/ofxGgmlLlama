#include "ofApp.h"

#include "imgui_stdlib.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <functional>
#include <iomanip>
#include <memory>
#include <sstream>
#include <thread>
#include <utility>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#else
#include <unistd.h>
#endif

namespace {

std::string trimText(const std::string & text) {
	std::size_t first = 0;
	while (first < text.size() &&
		std::isspace(static_cast<unsigned char>(text[first]))) {
		++first;
	}
	std::size_t last = text.size();
	while (last > first &&
		std::isspace(static_cast<unsigned char>(text[last - 1]))) {
		--last;
	}
	return text.substr(first, last - first);
}

std::string toString(const std::filesystem::path & path) {
	return path.lexically_normal().string();
}

bool pathExists(const std::filesystem::path & path) {
	std::error_code error;
	return std::filesystem::is_regular_file(path, error);
}

bool fileExists(const std::string & path) {
	return !path.empty() && ofFile::doesFileExist(path, false);
}

std::filesystem::path executableDirectory() {
#if defined(_WIN32)
	std::wstring buffer(MAX_PATH, L'\0');
	DWORD length = GetModuleFileNameW(
		nullptr,
		buffer.data(),
		static_cast<DWORD>(buffer.size()));
	while (length == buffer.size()) {
		buffer.resize(buffer.size() * 2);
		length = GetModuleFileNameW(
			nullptr,
			buffer.data(),
			static_cast<DWORD>(buffer.size()));
	}
	if (length > 0) {
		buffer.resize(length);
		return std::filesystem::path(buffer).parent_path();
	}
#elif defined(__APPLE__)
	uint32_t size = 0;
	_NSGetExecutablePath(nullptr, &size);
	std::string buffer(size, '\0');
	if (_NSGetExecutablePath(buffer.data(), &size) == 0) {
		return std::filesystem::path(buffer.c_str()).parent_path();
	}
#else
	std::string buffer(4096, '\0');
	const ssize_t length = readlink("/proc/self/exe", buffer.data(), buffer.size() - 1);
	if (length > 0) {
		buffer.resize(static_cast<std::size_t>(length));
		return std::filesystem::path(buffer).parent_path();
	}
#endif
	std::error_code error;
	return std::filesystem::current_path(error);
}

void addUniquePath(
	std::vector<std::filesystem::path> & paths,
	const std::filesystem::path & path) {
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
		for (int depth = 0; depth < 6 && !parent.empty(); ++depth) {
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

std::vector<std::string> findFilesByExtension(
	const std::vector<std::filesystem::path> & roots,
	const std::vector<std::filesystem::path> & relativeDirectories,
	const std::string & extension) {
	std::vector<std::string> files;
	for (const auto & root : roots) {
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
				if (entry.is_regular_file(error) && entry.path().extension() == extension) {
					files.push_back(toString(entry.path()));
				}
			}
		}
	}
	std::sort(files.begin(), files.end());
	files.erase(std::unique(files.begin(), files.end()), files.end());
	return files;
}

std::string discoverLlamaServer() {
#if defined(_WIN32)
	const std::vector<std::string> executableNames = {
		"llama-server.exe"
	};
#else
	const std::vector<std::string> executableNames = {
		"llama-server"
	};
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
			for (const auto & name : executableNames) {
				candidates.push_back(root / relative / name);
			}
		}
	}
	return findFirstFile(candidates);
}

std::string discoverEmbeddingModel() {
	const auto models = findFilesByExtension(
		searchRoots(),
		{
			"",
			"data",
			"data/models",
			"models",
			"../models",
			"ofxGgmlEmbeddingExample/bin/data",
			"ofxGgmlEmbeddingExample/bin/data/models",
			"ofxGgmlEmbeddingExample/models",
			"ofxGgmlTextExample/bin/data",
			"ofxGgmlTextExample/bin/data/models",
			"ofxGgmlTextExample/models",
			"ofxGgmlChatExample/bin/data",
			"ofxGgmlChatExample/bin/data/models",
			"ofxGgmlChatExample/models"
		},
		".gguf");
	return models.empty() ? std::string() : models.front();
}

bool isLocalServerUrl(const std::string & serverUrl) {
	return serverUrl.find("127.0.0.1") != std::string::npos ||
		serverUrl.find("localhost") != std::string::npos ||
		serverUrl.find("::1") != std::string::npos;
}

std::string trimTrailingSlash(std::string value) {
	while (!value.empty() && value.back() == '/') {
		value.pop_back();
	}
	return value;
}

int serverPortFromUrl(const std::string & serverUrl, int fallbackPort = 8081) {
	const std::string normalized = trimTrailingSlash(serverUrl);
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

int llamaServerHealthStatus(const std::string & serverUrl) {
	ofHttpRequest request(trimTrailingSlash(serverUrl) + "/health", "llama-server-health");
	request.method = ofHttpRequest::GET;
	request.timeoutSeconds = 1;
	ofURLFileLoader loader;
	const ofHttpResponse response = loader.handleRequest(request);
	return response.status;
}

bool isLlamaServerReady(const std::string & serverUrl) {
	const int status = llamaServerHealthStatus(serverUrl);
	return status >= 200 && status < 300;
}

bool waitForLlamaServerReady(const std::string & serverUrl, int timeoutSeconds) {
	const auto deadline = std::chrono::steady_clock::now() +
		std::chrono::seconds(std::max(1, timeoutSeconds));
	while (std::chrono::steady_clock::now() < deadline) {
		if (isLlamaServerReady(serverUrl)) {
			return true;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(500));
	}
	return isLlamaServerReady(serverUrl);
}

std::string quoteShellPath(const std::string & value) {
	return "\"" + value + "\"";
}

bool startBundledEmbeddingServer(
	const std::string & serverExe,
	const std::string & modelPath,
	const std::string & serverUrl) {
	if (serverExe.empty() || modelPath.empty()) {
		return false;
	}
	const int port = serverPortFromUrl(serverUrl);
#if defined(_WIN32)
	const std::filesystem::path exePath(serverExe);
	std::wstring command = L"\"" + exePath.wstring() + L"\" -m \"" +
		std::filesystem::path(modelPath).wstring() +
		L"\" --host 127.0.0.1 --port " + std::to_wstring(port) +
		L" -ngl 28 -c 4096 --embeddings --pooling mean";
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
	const std::string command = quoteShellPath(serverExe) +
		" -m " + quoteShellPath(modelPath) +
		" --host 127.0.0.1 --port " + std::to_string(port) +
		" -ngl 28 -c 4096 --embeddings --pooling mean >/dev/null 2>&1 &";
	return std::system(command.c_str()) == 0;
#endif
}

std::string modelDisplayName(
	const std::string & serverModel,
	const std::string & localModelPath,
	bool localModelWasStarted) {
	if (!serverModel.empty()) {
		return serverModel;
	}
	if (localModelWasStarted && !localModelPath.empty()) {
		return localModelPath;
	}
	return "server default";
}

ImVec2 fitWindowSize(float preferredWidth, float preferredHeight) {
	const ImVec2 display = ImGui::GetIO().DisplaySize;
	const float availableWidth = std::max(420.0f, display.x - 32.0f);
	const float availableHeight = std::max(360.0f, display.y - 32.0f);
	return ImVec2(
		std::min(preferredWidth, availableWidth),
		std::min(preferredHeight, availableHeight));
}

} // namespace

void ofApp::setup() {
	ofSetWindowTitle("ofxGgml embedding example");
	ofBackground(12);
	gui.setup(nullptr, false);

	settings.serverUrl = normalizeEnvText(envValue("OFXGGML_EMBEDDING_SERVER_URL"));
	settings.serverModel = normalizeEnvText(envValue("OFXGGML_EMBEDDING_SERVER_MODEL"));
	if (settings.serverUrl.empty()) {
		settings.serverUrl = "http://127.0.0.1:8081";
	}
	modelPath = normalizeEnvText(envValue("OFXGGML_EMBEDDING_MODEL"));
	if (modelPath.empty()) {
		modelPath = normalizeEnvText(envValue("OFXGGML_TEXT_MODEL"));
	}
	if (modelPath.empty()) {
		modelPath = discoverEmbeddingModel();
	}
	configureGenerator();

	inputA = "openFrameworks local inference";
	inputB = "interactive creative coding with local AI";
	inputAEdit = inputA;
	inputBEdit = inputB;
	inputAEdit.reserve(4096);
	inputBEdit.reserve(4096);

	std::lock_guard<std::mutex> lock(stateMutex);
	status = "ready";
	loadedModel = "not loaded";
	loadedBackend = "not loaded";
}

void ofApp::draw() {
	std::string statusSnapshot;
	std::string errorSnapshot;
	std::string serverUrlSnapshot;
	std::string serverModelSnapshot;
	std::string modelPathSnapshot;
	std::string loadedModelSnapshot;
	std::string loadedBackendSnapshot;
	std::vector<std::vector<float>> embeddingsSnapshot;
	float similaritySnapshot = 0.0f;
	bool hasSimilaritySnapshot = false;
	bool runningSnapshot = false;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		statusSnapshot = status;
		errorSnapshot = error;
		serverUrlSnapshot = settings.serverUrl;
		serverModelSnapshot = settings.serverModel;
		modelPathSnapshot = modelPath;
		loadedModelSnapshot = loadedModel;
		loadedBackendSnapshot = loadedBackend;
		embeddingsSnapshot = embeddings;
		similaritySnapshot = similarity;
		hasSimilaritySnapshot = hasSimilarity;
		runningSnapshot = running;
	}

	bool shouldRun = false;

	ofBackground(12);
	gui.begin();
	ImGui::SetNextWindowPos(ImVec2(16.0f, 16.0f), ImGuiCond_Once);
	ImGui::SetNextWindowSize(fitWindowSize(900.0f, 480.0f), ImGuiCond_Once);
	if (ImGui::Begin("ofxGgml Embedding Example")) {
		if (runningSnapshot) {
			ImGui::BeginDisabled();
		}
		if (ImGui::Button("Run", ImVec2(72.0f, 0.0f))) {
			shouldRun = true;
		}
		if (runningSnapshot) {
			ImGui::EndDisabled();
		}

		ImGui::Separator();
		const ImVec4 statusColor = runningSnapshot
			? ImVec4(0.45f, 0.75f, 1.0f, 1.0f)
			: ImVec4(0.70f, 0.92f, 0.70f, 1.0f);
		ImGui::TextColored(statusColor, "%s", statusSnapshot.c_str());
		ImGui::Text("State: %s", runningSnapshot ? "running" : "idle");
		ImGui::TextWrapped("Loaded model: %s", loadedModelSnapshot.c_str());
		ImGui::TextWrapped("Loaded backend: %s", loadedBackendSnapshot.c_str());

		if (ImGui::CollapsingHeader("Runtime", ImGuiTreeNodeFlags_DefaultOpen)) {
			std::string serverUrlEdit = serverUrlSnapshot;
			std::string serverModelEdit = serverModelSnapshot;
			std::string modelPathEdit = modelPathSnapshot;
			if (runningSnapshot) {
				ImGui::BeginDisabled();
			}
			ImGui::SetNextItemWidth(-1.0f);
			if (ImGui::InputText("Server URL", &serverUrlEdit)) {
				std::lock_guard<std::mutex> lock(stateMutex);
				settings.serverUrl = normalizeEnvText(serverUrlEdit);
				configureGenerator();
			}
			ImGui::SetNextItemWidth(-1.0f);
			if (ImGui::InputText("Server model", &serverModelEdit)) {
				std::lock_guard<std::mutex> lock(stateMutex);
				settings.serverModel = normalizeEnvText(serverModelEdit);
			}
			ImGui::SetNextItemWidth(-1.0f);
			if (ImGui::InputText("Local model path", &modelPathEdit)) {
				std::lock_guard<std::mutex> lock(stateMutex);
				modelPath = normalizeEnvText(modelPathEdit);
			}
			if (runningSnapshot) {
				ImGui::EndDisabled();
			}
			ImGui::TextWrapped(
				"Local embedding server: %s | Local model: %s",
				isLocalServerUrl(serverUrlSnapshot) ? "auto-start enabled" : "external",
				fileExists(modelPathSnapshot) ? "found" : "missing");
		}

		ImGui::Spacing();
		ImGui::TextUnformatted("Input A");
		ImGui::Separator();
		ImGui::InputTextMultiline(
			"##embedding-input-a",
			&inputAEdit,
			ImVec2(0.0f, 64.0f),
			runningSnapshot ? ImGuiInputTextFlags_ReadOnly : ImGuiInputTextFlags_None);
		ImGui::Spacing();
		ImGui::TextUnformatted("Input B");
		ImGui::Separator();
		ImGui::InputTextMultiline(
			"##embedding-input-b",
			&inputBEdit,
			ImVec2(0.0f, 64.0f),
			runningSnapshot ? ImGuiInputTextFlags_ReadOnly : ImGuiInputTextFlags_None);

		ImGui::Spacing();
		ImGui::TextUnformatted("Embeddings");
		ImGui::Separator();
		ImGui::BeginChild("ofxGgmlEmbeddingOutput", ImVec2(0.0f, 164.0f), true);
		if (!errorSnapshot.empty()) {
			ImGui::TextWrapped("Error: %s", errorSnapshot.c_str());
		} else if (embeddingsSnapshot.empty()) {
			ImGui::TextDisabled("(none)");
		} else {
			if (hasSimilaritySnapshot) {
				ImGui::Text("Cosine similarity: %.4f", similaritySnapshot);
				ImGui::Separator();
			}
			for (std::size_t i = 0; i < embeddingsSnapshot.size(); ++i) {
				ImGui::Text(
					"%c dimension: %d",
					static_cast<char>('A' + static_cast<int>(i)),
					static_cast<int>(embeddingsSnapshot[i].size()));
				const std::string preview = embeddingPreview(embeddingsSnapshot[i]);
				ImGui::TextWrapped("%s", preview.c_str());
				if (i + 1 < embeddingsSnapshot.size()) {
					ImGui::Spacing();
				}
			}
		}
		ImGui::EndChild();
	}
	ImGui::End();
	gui.end();
	gui.draw();

	if (shouldRun) {
		startEmbedding();
	}
}

void ofApp::keyPressed(int key) {
	if (ImGui::GetCurrentContext() && ImGui::GetIO().WantCaptureKeyboard) {
		return;
	}
	if (key == 'r' || key == 'R') {
		startEmbedding();
	}
}

void ofApp::exit() {
	if (worker.joinable()) {
		worker.join();
	}
}

void ofApp::startEmbedding() {
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		if (running) {
			status = "embedding request is already running";
			return;
		}
	}

	if (worker.joinable()) {
		worker.join();
	}

	{
		std::lock_guard<std::mutex> lock(stateMutex);
		inputA = trimText(inputAEdit);
		inputB = trimText(inputBEdit);
		if (inputA.empty() || inputB.empty()) {
			status = "type both input texts first";
			error.clear();
			embeddings.clear();
			hasSimilarity = false;
			return;
		}
		status = "requesting embedding...";
		error.clear();
		embeddings.clear();
		hasSimilarity = false;
		loadedModel = "loading...";
		loadedBackend = "llama-server embeddings";
		running = true;
	}

	worker = std::thread(&ofApp::runEmbeddingWorker, this);
}

void ofApp::runEmbeddingWorker() {
	ofxGgmlEmbeddingSettings requestSettings;
	std::string requestInputA;
	std::string requestInputB;
	std::string requestModelPath;
	{
		std::lock_guard<std::mutex> lock(stateMutex);
		requestSettings = settings;
		requestInputA = inputA;
		requestInputB = inputB;
		requestModelPath = modelPath;
	}
	bool startedBundledServer = false;

	if (requestSettings.serverUrl.empty()) {
		std::lock_guard<std::mutex> lock(stateMutex);
		status = "embedding error";
		error = "No embedding server URL configured.";
		loadedModel = "not loaded";
		loadedBackend = "not loaded";
		running = false;
		return;
	}

	if (isLocalServerUrl(requestSettings.serverUrl) &&
		!isLlamaServerReady(requestSettings.serverUrl)) {
		if (requestModelPath.empty() || !fileExists(requestModelPath)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			status = "embedding error";
			error = "No GGUF model found for the local embedding server. Set OFXGGML_EMBEDDING_MODEL or place one under addons\\models.";
			loadedModel = "not loaded";
			loadedBackend = "llama-server embeddings @ " + requestSettings.serverUrl;
			running = false;
			return;
		}
		const std::string serverExe = discoverLlamaServer();
		if (serverExe.empty()) {
			std::lock_guard<std::mutex> lock(stateMutex);
			status = "embedding error";
			error = "No bundled llama-server found. Run scripts\\build-llama-server.bat first.";
			loadedModel = "not loaded";
			loadedBackend = "llama-server embeddings @ " + requestSettings.serverUrl;
			running = false;
			return;
		}
		{
			std::lock_guard<std::mutex> lock(stateMutex);
			status = "starting bundled embedding server...";
		}
		ofLogNotice("example-emb")
			<< "starting embedding llama-server\n"
			<< "exe: " << serverExe << "\n"
			<< "model: " << requestModelPath << "\n"
			<< "url: " << requestSettings.serverUrl;
		if (!startBundledEmbeddingServer(
			serverExe,
			requestModelPath,
			requestSettings.serverUrl)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			status = "embedding error";
			error = "Failed to start bundled embedding llama-server.";
			loadedModel = "not loaded";
			loadedBackend = "llama-server embeddings @ " + requestSettings.serverUrl;
			running = false;
			return;
		}
		startedBundledServer = true;
		{
			std::lock_guard<std::mutex> lock(stateMutex);
			status = "waiting for embedding server...";
		}
		if (!waitForLlamaServerReady(requestSettings.serverUrl, 180)) {
			std::lock_guard<std::mutex> lock(stateMutex);
			status = "embedding error";
			error = "Embedding llama-server did not become ready at " + requestSettings.serverUrl + ".";
			loadedModel = "not loaded";
			loadedBackend = "llama-server embeddings @ " + requestSettings.serverUrl;
			running = false;
			return;
		}
	}

	ofxGgmlEmbeddingRequest request;
	request.inputs = { requestInputA, requestInputB };
	request.settings = requestSettings;

	ofLogNotice("example-emb")
		<< "input A\n" << requestInputA
		<< "\ninput B\n" << requestInputB;

	const auto result = generator.embed(request);

	if (result) {
		std::ostringstream log;
		log << "output\n";
		for (std::size_t i = 0; i < result.embeddings.size(); ++i) {
			log << static_cast<char>('A' + static_cast<int>(i))
				<< " dimension: " << result.embeddings[i].size() << "\n"
				<< embeddingPreview(result.embeddings[i]) << "\n";
		}
		if (result.embeddings.size() >= 2) {
			log << "cosine similarity: "
				<< ofxGgmlEmbeddingUtils::cosineSimilarity(
					result.embeddings[0],
					result.embeddings[1])
				<< "\n";
		}
		ofLogNotice("example-emb") << log.str();
	} else {
		std::string resultError = result.error;
		if (resultError.find("llama-server is not reachable") != std::string::npos) {
			resultError +=
				"\nStart the embedding example with scripts\\run-example.bat embedding -Build -Model C:\\path\\to\\embedding-model.gguf.";
		}
		ofLogError("example-emb") << "output error\n" << resultError;
	}

	std::lock_guard<std::mutex> lock(stateMutex);
	if (result) {
		embeddings = result.embeddings;
		hasSimilarity = embeddings.size() >= 2;
		similarity = hasSimilarity
			? ofxGgmlEmbeddingUtils::cosineSimilarity(embeddings[0], embeddings[1])
			: 0.0f;
		error.clear();
		loadedModel = modelDisplayName(
			requestSettings.serverModel,
			requestModelPath,
			startedBundledServer);
		loadedBackend = result.backendName + " @ " + requestSettings.serverUrl;
		status = "complete via " + result.backendName + " in " +
			std::to_string(static_cast<int>(result.elapsedMs)) + " ms";
	} else {
		std::string resultError = result.error;
		if (resultError.find("llama-server is not reachable") != std::string::npos) {
			resultError +=
				"\nStart the embedding example with scripts\\run-example.bat embedding -Build -Model C:\\path\\to\\embedding-model.gguf.";
		}
		embeddings.clear();
		similarity = 0.0f;
		hasSimilarity = false;
		error = resultError;
		loadedModel = "not loaded";
		loadedBackend = result.backendName.empty()
			? "llama-server embeddings @ " + requestSettings.serverUrl
			: result.backendName + " @ " + requestSettings.serverUrl;
		status = "embedding error";
	}
	running = false;
}

void ofApp::configureGenerator() {
	generator.setBackend(
		std::make_shared<ofxGgmlLlamaServerEmbeddingBackend>(settings.serverUrl));
}

std::string ofApp::normalizeEnvText(const std::string & text) {
	std::string normalized = trimText(text);
	if (normalized.size() >= 2 && normalized.front() == '"' && normalized.back() == '"') {
		normalized = normalized.substr(1, normalized.size() - 2);
	}
	return normalized;
}

std::string ofApp::embeddingPreview(const std::vector<float> & values) {
	std::ostringstream preview;
	preview << std::fixed << std::setprecision(5);
	const std::size_t count = std::min<std::size_t>(values.size(), 32);
	for (std::size_t i = 0; i < count; ++i) {
		if (i > 0) {
			preview << ", ";
		}
		preview << values[i];
	}
	if (values.size() > count) {
		preview << ", ...";
	}
	return preview.str();
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
