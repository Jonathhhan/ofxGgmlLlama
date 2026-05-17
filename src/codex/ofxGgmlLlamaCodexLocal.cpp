#include "ofxGgmlLlamaCodexLocal.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <mutex>
#include <sstream>
#include <thread>

#if __has_include("ofMain.h")
#include "ofMain.h"
#define OFXGGML_LLAMA_HAS_OF_RUNTIME 1
#endif

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace {
constexpr const char * LogModule = "ofxGgmlLlamaCodexLocal";

std::string escapeTomlString(const std::string & value);

std::string toString(const std::filesystem::path & path) {
	return path.lexically_normal().string();
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

std::string executableHelpOutput(const std::string & executable) {
	static std::mutex helpCacheMutex;
	static std::map<std::string, std::string> helpCache;

	{
		std::lock_guard<std::mutex> lock(helpCacheMutex);
		const auto found = helpCache.find(executable);
		if (found != helpCache.end()) {
			return found->second;
		}
	}

	const auto output = readCommandOutput(
		ofxGgmlLlamaCodexLocal::quoteArgument(executable) + " --help 2>&1");

	{
		std::lock_guard<std::mutex> lock(helpCacheMutex);
		const auto inserted = helpCache.emplace(executable, output);
		return inserted.first->second;
	}
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

void addUniquePath(
	std::vector<std::filesystem::path> & paths,
	const std::filesystem::path & path) {
	if (path.empty()) {
		return;
	}
	const auto normalized = path.lexically_normal();
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
		auto parent = roots[i];
		for (int depth = 0; depth < 8 && !parent.empty(); ++depth) {
			addUniquePath(roots, parent);
			parent = parent.parent_path();
		}
	}
	return roots;
}

std::string findFirstExistingFile(const std::vector<std::filesystem::path> & candidates) {
	for (const auto & candidate : candidates) {
		std::error_code error;
		if (std::filesystem::is_regular_file(candidate, error)) {
			return toString(candidate);
		}
	}
	return {};
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
	const std::filesystem::path path(filePath);
	std::error_code error;
	if (!path.parent_path().empty()) {
		std::filesystem::create_directories(path.parent_path(), error);
		if (error) {
			return false;
		}
	}
	std::ofstream output(filePath, std::ios::binary | std::ofstream::trunc);
	if (!output.is_open()) {
		return false;
	}
	output << text;
	return output.good();
}

std::filesystem::path codexConfigParent(const std::string & configPath) {
	const std::filesystem::path path(configPath);
	const auto parent = path.parent_path();
	if (!parent.empty()) {
		return parent;
	}
	std::error_code error;
	return std::filesystem::current_path(error);
}

std::filesystem::path codexAgentRoleDirectory(const std::string & configPath) {
	return codexConfigParent(configPath) / "ofxggml" / "agents";
}

std::string localAgentRoleToml(
	const std::string & role,
	const ofxGgmlLlamaCodexProviderConfig & config) {
	const int contextWindow = std::max(4096, config.modelContextWindow);
	const int compactLimit = std::max(2048, config.modelAutoCompactTokenLimit);
	const int toolLimit = std::max(1024, config.toolOutputTokenLimit);
	const int maxAgents = std::max(1, config.agentMaxConcurrentThreadsPerSession);
	const int maxDepth = std::max(1, config.agentMaxDepth);
	const int minWaitMs = std::max(0, config.agentMinWaitTimeoutMs);
	const int maxWaitMs = std::max(minWaitMs, config.agentMaxWaitTimeoutMs);
	const int defaultWaitMs = std::min(
		maxWaitMs,
		std::max(minWaitMs, config.agentDefaultWaitTimeoutMs));
	std::ostringstream output;
	output << "# Generated by ofxGgmlLlamaCodexLocal.\n";
	output << "model_provider = \"" << escapeTomlString(
		config.providerId.empty() ? "llama_cpp" : config.providerId) << "\"\n";
	output << "web_search = \"disabled\"\n";
	output << "model_context_window = " << contextWindow << "\n";
	output << "model_auto_compact_token_limit = " << compactLimit << "\n";
	output << "tool_output_token_limit = " << toolLimit << "\n";
	output << "model_reasoning_effort = \"" <<
		escapeTomlString(config.modelReasoningEffort) << "\"\n";
	output << "model_reasoning_summary = \"" <<
		escapeTomlString(config.modelReasoningSummary) << "\"\n";
	output << "hide_agent_reasoning = " << (config.hideAgentReasoning ? "true" : "false") << "\n";
	if (role == "explorer") {
		output << "developer_instructions = \""
			"Use the explorer role for narrow, read-only codebase questions. "
			"Use rg first, read exact files before answering, cite paths or lines when useful, "
			"and return concise findings. Do not edit files and avoid spawning more agents "
			"unless explicitly asked.\"\n";
	} else {
		output << "developer_instructions = \""
			"Use the worker role for bounded code changes. Read local patterns first, "
			"follow openFrameworks addon conventions, preserve existing dirty files, "
			"keep edits scoped, use apply_patch for manual edits, run the smallest useful "
			"validation, and report residual risk.\"\n";
	}
	output << "\n[features.multi_agent_v2]\n";
	output << "enabled = " << (config.multiAgentV2Enabled ? "true" : "false") << "\n";
	output << "max_concurrent_threads_per_session = " << maxAgents << "\n";
	output << "min_wait_timeout_ms = " << minWaitMs << "\n";
	output << "max_wait_timeout_ms = " << maxWaitMs << "\n";
	output << "default_wait_timeout_ms = " << defaultWaitMs << "\n";
	output << "usage_hint_enabled = false\n";
	output << "hide_spawn_agent_metadata = true\n";
	output << "non_code_mode_only = true\n";
	output << "\n[agents]\n";
	output << "max_threads = " << maxAgents << "\n";
	output << "max_depth = " << maxDepth << "\n\n";
	return output.str();
}

bool writeAgentRoleFiles(
	const std::string & configPath,
	const ofxGgmlLlamaCodexProviderConfig & config,
	std::string & message) {
	const auto directory = codexAgentRoleDirectory(configPath);
	const auto explorerPath = directory / "local-explorer.toml";
	const auto workerPath = directory / "local-worker.toml";
	if (!writeAllText(toString(explorerPath), localAgentRoleToml("explorer", config)) ||
		!writeAllText(toString(workerPath), localAgentRoleToml("worker", config))) {
		message = "failed to write Codex agent role files under " + toString(directory);
		return false;
	}
	return true;
}

bool replaceSection(std::string & configText, const std::string & sectionName) {
	const std::string sectionHeader = "[" + sectionName + "]";
	std::istringstream input(configText);
	std::ostringstream output;
	bool inTargetSection = false;
	bool sectionFound = false;
	std::string line;

	while (std::getline(input, line)) {
		const auto trimmed = ofxGgmlLlamaCodexLocal::trimCopy(line);
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

bool replaceTopLevelAssignments(
	std::string & configText,
	const std::vector<std::string> & keys) {
	std::istringstream input(configText);
	std::ostringstream output;
	bool inSection = false;
	bool updated = false;
	std::string line;
	while (std::getline(input, line)) {
		const auto trimmed = ofxGgmlLlamaCodexLocal::trimCopy(line);
		if (!trimmed.empty() && trimmed.front() == '[' && trimmed.back() == ']') {
			inSection = true;
		}
		if (!inSection) {
			const bool shouldKeep = std::none_of(keys.begin(), keys.end(), [&](const std::string & key) {
				const std::string prefix = key + " =";
				return trimmed.rfind(prefix, 0) == 0;
			});
			if (!shouldKeep) {
				updated = true;
				continue;
			}
		}
		output << line << '\n';
	}
	configText = output.str();
	return updated;
}

void appendSection(std::string & configText, const std::string & sectionBody) {
	if (!configText.empty() && configText.back() != '\n') {
		configText.push_back('\n');
	}
	configText += sectionBody;
	if (!sectionBody.empty() && sectionBody.back() != '\n') {
		configText.push_back('\n');
	}
}

std::string escapeTomlString(const std::string & value) {
	std::string escaped;
	escaped.reserve(value.size());
	for (char c : value) {
		if (c == '\\' || c == '"') {
			escaped.push_back('\\');
		}
		escaped.push_back(c);
	}
	return escaped;
}

bool isPortableExecutableName(const std::string & executable) {
	return executable.find('\\') == std::string::npos &&
		executable.find('/') == std::string::npos &&
		executable.find(':') == std::string::npos;
}

void addUniqueModelId(std::vector<std::string> & models, const std::string & value) {
	const auto trimmed = ofxGgmlLlamaCodexLocal::trimCopy(value);
	if (trimmed.empty()) {
		return;
	}
	if (std::find(models.begin(), models.end(), trimmed) == models.end()) {
		models.push_back(trimmed);
	}
}
}

std::string ofxGgmlLlamaCodexLocal::trimCopy(const std::string & value) {
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

std::string ofxGgmlLlamaCodexLocal::trimTrailingSlash(std::string value) {
	while (!value.empty() && value.back() == '/') {
		value.pop_back();
	}
	return value;
}

std::string ofxGgmlLlamaCodexLocal::envValue(const char * name) {
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

std::string ofxGgmlLlamaCodexLocal::getEnvOrDefault(
	const char * name,
	const std::string & fallback) {
	const auto value = envValue(name);
	return value.empty() ? fallback : value;
}

std::string ofxGgmlLlamaCodexLocal::serverRootFromBaseUrl(const std::string & baseUrl) {
	auto normalized = trimTrailingSlash(trimCopy(baseUrl));
	const std::string suffix = "/v1";
	if (normalized.size() >= suffix.size() &&
		normalized.compare(normalized.size() - suffix.size(), suffix.size(), suffix) == 0) {
		normalized.resize(normalized.size() - suffix.size());
	}
	return normalized.empty() ? "http://127.0.0.1:8001" : normalized;
}

std::string ofxGgmlLlamaCodexLocal::baseUrlFromServerRoot(const std::string & serverRoot) {
	return trimTrailingSlash(serverRootFromBaseUrl(serverRoot)) + "/v1";
}

int ofxGgmlLlamaCodexLocal::serverPortFromUrl(const std::string & serverUrl, int fallbackPort) {
	const auto normalized = trimTrailingSlash(trimCopy(serverUrl));
	const auto scheme = normalized.find("://");
	const auto hostStart = scheme == std::string::npos ? 0 : scheme + 3;
	const auto colon = normalized.find(':', hostStart);
	if (colon == std::string::npos) {
		return fallbackPort;
	}
	const auto portStart = colon + 1;
	auto portEnd = normalized.find('/', portStart);
	if (portEnd == std::string::npos) {
		portEnd = normalized.size();
	}
	try {
		return std::stoi(normalized.substr(portStart, portEnd - portStart));
	} catch (...) {
		return fallbackPort;
	}
}

std::string ofxGgmlLlamaCodexLocal::codexApiRootFromBaseUrl(const std::string & baseUrl) {
	auto trimmed = trimTrailingSlash(trimCopy(baseUrl));
	const std::string suffix = "/v1";
	if (trimmed.size() >= suffix.size() &&
		trimmed.compare(trimmed.size() - suffix.size(), suffix.size(), suffix) == 0) {
		return trimmed;
	}
	return trimmed.empty() ? "http://127.0.0.1:8001/v1" : trimmed + suffix;
}

std::string ofxGgmlLlamaCodexLocal::modelAliasFromPath(const std::string & modelPath) {
	if (modelPath.empty()) {
		return {};
	}
	auto stem = std::filesystem::path(modelPath).stem().string();
	std::string slug;
	slug.reserve(stem.size());
	for (unsigned char c : stem) {
		if (std::isalnum(c) || c == '.' || c == '_' || c == '-') {
			slug.push_back(static_cast<char>(c));
		} else if (!slug.empty() && slug.back() != '-') {
			slug.push_back('-');
		}
	}
	while (!slug.empty() && slug.back() == '-') {
		slug.pop_back();
	}
	return slug.empty() ? std::string() : "local/" + slug;
}

std::string ofxGgmlLlamaCodexLocal::resolveCodexConfigPath() {
	const auto explicitPath = envValue("OFXGGML_CODEX_CONFIG_PATH");
	if (!explicitPath.empty()) {
		return toString(std::filesystem::absolute(std::filesystem::path(trimCopy(explicitPath))).lexically_normal());
	}

	std::vector<std::filesystem::path> candidates;
	const auto addIfSet = [&](const char * envVar, const std::filesystem::path & suffix) {
		const auto value = envValue(envVar);
		if (!value.empty()) {
			candidates.emplace_back(std::filesystem::path(value) / suffix);
		}
	};

	addIfSet("CODEX_HOME", "config.toml");
#if defined(_WIN32)
	addIfSet("USERPROFILE", ".codex/config.toml");
	addIfSet("LOCALAPPDATA", "OpenAI/Codex/config.toml");
	addIfSet("APPDATA", "OpenAI/Codex/config.toml");
#else
	addIfSet("HOME", ".codex/config.toml");
#endif

	for (const auto & candidate : candidates) {
		std::error_code error;
		if (std::filesystem::exists(candidate, error)) {
			return toString(candidate);
		}
	}
	return candidates.empty() ? std::string() : toString(candidates.front());
}

std::string ofxGgmlLlamaCodexLocal::discoverCodexExecutable() {
	const auto explicitCodexExe = trimCopy(envValue("OFXGGML_CODEX_EXE"));
	if (!explicitCodexExe.empty() && fileExists(explicitCodexExe)) {
		return explicitCodexExe;
	}

#if defined(_WIN32)
	std::vector<std::filesystem::path> candidates;
	const auto addIfSet = [&](const char * envVar, const std::filesystem::path & suffix) {
		const auto value = envValue(envVar);
		if (!value.empty()) {
			candidates.emplace_back(std::filesystem::path(value) / suffix);
		}
	};
	addIfSet("LOCALAPPDATA", "OpenAI/Codex/bin/codex.exe");
	addIfSet("PROGRAMFILES", "OpenAI/Codex/bin/codex.exe");
	addIfSet("PROGRAMFILES(X86)", "OpenAI/Codex/bin/codex.exe");
	addIfSet("USERPROFILE", "AppData/Local/OpenAI/Codex/bin/codex.exe");
	const auto found = findFirstExistingFile(candidates);
	if (!found.empty()) {
		return found;
	}
	const auto wherePath = trimCopy(readCommandOutput("where.exe codex 2>NUL"));
	std::istringstream lines(wherePath);
	std::string line;
	while (std::getline(lines, line)) {
		line = trimCopy(line);
		if (!line.empty() && fileExists(line)) {
			return line;
		}
	}
#endif
	return {};
}

std::string ofxGgmlLlamaCodexLocal::discoverLlamaServer() {
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
		"libs/llama.cpp/build/bin/Debug",
		"../ofxGgmlLlama/libs/llama/bin",
		"../ofxGgmlLlama/libs/llama.cpp/build/bin/Release"
	};

	std::vector<std::filesystem::path> candidates;
	for (const auto & root : searchRoots()) {
		for (const auto & relative : relativeDirectories) {
			candidates.push_back(root / relative / executableName);
		}
	}
	return findFirstExistingFile(candidates);
}

std::string ofxGgmlLlamaCodexLocal::discoverTextModel() {
	const std::vector<std::filesystem::path> relativeDirectories = {
		"",
		"data",
		"data/models",
		"models",
		"../models",
		"../../models",
		"ofxGgmlLlamaCodexLocalExample/bin/data",
		"ofxGgmlLlamaCodexLocalExample/bin/data/models",
		"ofxGgmlLlamaCodexLocalExample/models"
	};

	std::vector<std::string> models;
	for (const auto & root : searchRoots()) {
		for (const auto & relative : relativeDirectories) {
			const auto directory = (root / relative).lexically_normal();
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

bool ofxGgmlLlamaCodexLocal::fileExists(const std::string & path) {
	if (path.empty()) {
		return false;
	}
	std::error_code error;
	return std::filesystem::is_regular_file(std::filesystem::path(path), error);
}

ofxGgmlLlamaServerProbe ofxGgmlLlamaCodexLocal::probeEndpoint(
	const std::string & endpointUrl,
	int timeoutSeconds) {
	ofxGgmlLlamaServerProbe probe;
#if defined(OFXGGML_LLAMA_HAS_OF_RUNTIME)
	ofHttpRequest request(endpointUrl, "llama-server-probe");
	request.method = ofHttpRequest::GET;
	request.timeoutSeconds = std::max(1, timeoutSeconds);
	ofURLFileLoader loader;
	const auto response = loader.handleRequest(request);
	probe.status = response.status;
	probe.reachable = response.status > 0;
	probe.ready = response.status >= 200 && response.status < 500 && response.status != 404;
	probe.message = response.error.empty() ? response.data.getText() : response.error;
	probe.message = trimTrailingSlash(probe.message);
#else
	(void)endpointUrl;
	(void)timeoutSeconds;
	probe.message = "openFrameworks HTTP runtime is not available";
#endif
	return probe;
}

ofxGgmlLlamaServerProbe ofxGgmlLlamaCodexLocal::probeServerHealth(
	const std::string & serverUrl,
	int timeoutSeconds) {
	auto probe = probeEndpoint(trimTrailingSlash(serverRootFromBaseUrl(serverUrl)) + "/health", timeoutSeconds);
	probe.ready = probe.status >= 200 && probe.status < 300;
	return probe;
}

ofxGgmlLlamaServedModels ofxGgmlLlamaCodexLocal::probeServedModels(
	const std::string & baseUrl,
	const std::string & expectedModel,
	int timeoutSeconds) {
	ofxGgmlLlamaServedModels result;
	const auto probe = probeEndpoint(codexApiRootFromBaseUrl(baseUrl) + "/models", timeoutSeconds);
	result.reachable = probe.reachable;
	result.ready = probe.ready && probe.status >= 200 && probe.status < 300;
	result.status = probe.status;
	result.message = probe.message;
	if (!result.ready) {
		return result;
	}
#if defined(OFXGGML_LLAMA_HAS_OF_RUNTIME)
	try {
		const auto json = ofJson::parse(probe.message);
		if (json.contains("data") && json["data"].is_array()) {
			for (const auto & item : json["data"]) {
				if (item.contains("id") && item["id"].is_string()) {
					addUniqueModelId(result.models, item["id"].get<std::string>());
				}
				if (item.contains("aliases") && item["aliases"].is_array()) {
					for (const auto & alias : item["aliases"]) {
						if (alias.is_string()) {
							addUniqueModelId(result.models, alias.get<std::string>());
						}
					}
				}
			}
		}
		if (json.contains("models") && json["models"].is_array()) {
			for (const auto & item : json["models"]) {
				for (const auto & key : { "model", "name", "id" }) {
					if (item.contains(key) && item[key].is_string()) {
						addUniqueModelId(result.models, item[key].get<std::string>());
					}
				}
			}
		}
		std::sort(result.models.begin(), result.models.end());
		result.expectedModelServed = !expectedModel.empty() &&
			std::find(result.models.begin(), result.models.end(), expectedModel) != result.models.end();
		if (result.models.empty()) {
			result.message = "server did not advertise model ids";
		}
	} catch (const std::exception & exception) {
		result.ready = false;
		result.message = std::string("failed to parse /v1/models: ") + exception.what();
	}
#else
	(void)expectedModel;
#endif
	return result;
}

ofxGgmlLlamaServerProbe ofxGgmlLlamaCodexLocal::waitForServerReady(
	const std::string & serverUrl,
	int timeoutSeconds,
	const std::function<bool()> & shouldCancel) {
	const auto deadline = std::chrono::steady_clock::now() +
		std::chrono::seconds(std::max(1, timeoutSeconds));
	ofxGgmlLlamaServerProbe lastProbe;
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

std::string ofxGgmlLlamaCodexLocal::describeProbe(const ofxGgmlLlamaServerProbe & probe) {
	std::string detail = probe.reachable
		? "HTTP " + std::to_string(probe.status)
		: "unreachable";
	if (!probe.message.empty()) {
		detail += ": " + probe.message;
	}
	return detail;
}

std::string ofxGgmlLlamaCodexLocal::detectCodexWireApi(const std::string & baseUrl) {
	const auto root = codexApiRootFromBaseUrl(baseUrl);
	const auto responsesProbe = probeEndpoint(root + "/responses", 2);
	if (responsesProbe.ready || !responsesProbe.reachable) {
		return "responses";
	}
	return "responses";
}

std::string ofxGgmlLlamaCodexLocal::buildCodexConfigSnippet(
	const ofxGgmlLlamaCodexProviderConfig & config) {
	const auto providerId = config.providerId.empty() ? "llama_cpp" : config.providerId;
	const auto profile = config.profile.empty() ? "ofxggml_local" : config.profile;
	const auto wireApi = config.wireApi.empty() ? "responses" : config.wireApi;
	std::ostringstream output;
	if (config.writeTopLevelSelection) {
		output << "model = \"" << escapeTomlString(config.modelAlias) << "\"\n";
		output << "model_provider = \"" << escapeTomlString(providerId) << "\"\n";
		output << "web_search = \"disabled\"\n\n";
		output << "model_context_window = " << std::max(1024, config.modelContextWindow) << "\n";
		output << "model_auto_compact_token_limit = " << std::max(1024, config.modelAutoCompactTokenLimit) << "\n";
		output << "tool_output_token_limit = " << std::max(512, config.toolOutputTokenLimit) << "\n\n";
		output << "model_reasoning_effort = \"" <<
			escapeTomlString(config.modelReasoningEffort) << "\"\n";
		output << "model_reasoning_summary = \"" <<
			escapeTomlString(config.modelReasoningSummary) << "\"\n";
		output << "hide_agent_reasoning = " << (config.hideAgentReasoning ? "true" : "false") << "\n\n";
	}
	output << "[model_providers." << providerId << "]\n";
	output << "name = \"" << escapeTomlString(config.providerName) << "\"\n";
	output << "base_url = \"" << escapeTomlString(codexApiRootFromBaseUrl(config.baseUrl)) << "\"\n";
	output << "wire_api = \"" << escapeTomlString(wireApi) << "\"\n";
	output << "stream_idle_timeout_ms = " << std::max(1000, config.streamIdleTimeoutMs) << "\n\n";
	output << "[profiles." << profile << "]\n";
	output << "model = \"" << escapeTomlString(config.modelAlias) << "\"\n";
	output << "model_provider = \"" << escapeTomlString(providerId) << "\"\n";
	output << "web_search = \"disabled\"\n";
	output << "model_reasoning_effort = \"" <<
		escapeTomlString(config.modelReasoningEffort) << "\"\n";
	output << "model_reasoning_summary = \"" <<
		escapeTomlString(config.modelReasoningSummary) << "\"\n";
	if (config.writeAgentSettings) {
		const int minWaitMs = std::max(0, config.agentMinWaitTimeoutMs);
		const int maxWaitMs = std::max(minWaitMs, config.agentMaxWaitTimeoutMs);
		const int defaultWaitMs = std::min(
			maxWaitMs,
			std::max(minWaitMs, config.agentDefaultWaitTimeoutMs));
		output << "\n[features.multi_agent_v2]\n";
		output << "enabled = " << (config.multiAgentV2Enabled ? "true" : "false") << "\n";
		output << "max_concurrent_threads_per_session = " <<
			std::max(1, config.agentMaxConcurrentThreadsPerSession) << "\n";
		output << "min_wait_timeout_ms = " << minWaitMs << "\n";
		output << "max_wait_timeout_ms = " << maxWaitMs << "\n";
		output << "default_wait_timeout_ms = " << defaultWaitMs << "\n";
		output << "usage_hint_enabled = false\n";
		output << "hide_spawn_agent_metadata = true\n";
		output << "non_code_mode_only = true\n\n";
		output << "[agents]\n";
		output << "max_threads = " <<
			std::max(1, config.agentMaxConcurrentThreadsPerSession) << "\n";
		output << "max_depth = " << std::max(1, config.agentMaxDepth) << "\n\n";
		output << "[agents.explorer]\n";
		output << "description = \"Fast read-only codebase questions for local llama.cpp sessions.\"\n";
		output << "config_file = \"ofxggml/agents/local-explorer.toml\"\n";
		output << "nickname_candidates = [\"Scout\", \"Trace\"]\n\n";
		output << "[agents.worker]\n";
		output << "description = \"Bounded code edits with focused validation for local llama.cpp sessions.\"\n";
		output << "config_file = \"ofxggml/agents/local-worker.toml\"\n";
		output << "nickname_candidates = [\"Patch\", \"Build\"]\n";
	}
	return output.str();
}

ofxGgmlLlamaCodexConfigResult ofxGgmlLlamaCodexLocal::writeCodexConfig(
	const std::string & configPath,
	const ofxGgmlLlamaCodexProviderConfig & config) {
	ofxGgmlLlamaCodexConfigResult result;
	result.path = configPath.empty() ? resolveCodexConfigPath() : configPath;
	if (result.path.empty()) {
		result.message = "failed to resolve Codex config path";
		return result;
	}
	if (config.modelAlias.empty()) {
		result.message = "model alias is required";
		return result;
	}
	if (config.writeAgentSettings && config.writeAgentRoleFiles) {
		if (!writeAgentRoleFiles(result.path, config, result.message)) {
			return result;
		}
	}

	const auto providerId = config.providerId.empty() ? "llama_cpp" : config.providerId;
	const auto profile = config.profile.empty() ? "ofxggml_local" : config.profile;
	const auto existing = readAllText(result.path);
	auto updated = existing;
	const bool removedProvider = replaceSection(updated, "model_providers." + providerId);
	const bool removedProfile = replaceSection(updated, "profiles." + profile);
	const bool removedMultiAgent = config.writeAgentSettings &&
		replaceSection(updated, "features.multi_agent_v2");
	const bool removedAgents = config.writeAgentSettings &&
		replaceSection(updated, "agents");
	const bool removedExplorerAgent = config.writeAgentSettings &&
		replaceSection(updated, "agents.explorer");
	const bool removedWorkerAgent = config.writeAgentSettings &&
		replaceSection(updated, "agents.worker");
	const bool removedTopLevel = replaceTopLevelAssignments(
		updated,
		{
			"model",
			"model_provider",
			"web_search",
			"model_context_window",
			"model_auto_compact_token_limit",
			"tool_output_token_limit",
			"model_reasoning_effort",
			"model_reasoning_summary",
			"hide_agent_reasoning"
		});
	if (config.writeTopLevelSelection) {
		updated.insert(0, buildCodexConfigSnippet(config) + "\n");
	} else {
		appendSection(updated, buildCodexConfigSnippet(config));
	}

	if (!writeAllText(result.path, updated)) {
		result.message = "failed to write Codex config: " + result.path;
		return result;
	}

	result.ok = true;
	result.created = existing.empty();
	const bool replaced = removedProvider ||
		removedProfile ||
		removedMultiAgent ||
		removedAgents ||
		removedExplorerAgent ||
		removedWorkerAgent ||
		removedTopLevel;
	result.message = result.created
		? "Created Codex config at " + result.path
		: (replaced ? "Updated Codex config at " : "Appended Codex config at ") + result.path;
	if (config.writeAgentSettings && config.writeAgentRoleFiles) {
		result.message += " and agent role files under " +
			toString(codexAgentRoleDirectory(result.path));
	}
	return result;
}

std::string ofxGgmlLlamaCodexLocal::quoteArgument(const std::string & value) {
	if (value.empty()) {
		return "\"\"";
	}
	if (value.find_first_of(" \t\r\n\"") == std::string::npos) {
		return value;
	}
	std::string escaped;
	escaped.reserve(value.size());
	for (char c : value) {
		if (c == '"') {
			escaped += "\\\"";
		} else {
			escaped += c;
		}
	}
	return "\"" + escaped + "\"";
}

bool ofxGgmlLlamaCodexLocal::executableSupportsArgument(
	const std::string & executable,
	const std::string & argument) {
	if (executable.empty() || argument.empty()) {
		return false;
	}
	const auto output = executableHelpOutput(executable);
	return output.empty() || output.find(argument) != std::string::npos;
}

bool ofxGgmlLlamaCodexLocal::launchDetachedProcess(
	const std::string & executable,
	const std::string & arguments) {
	if (executable.empty()) {
		return false;
	}
#if defined(_WIN32)
	auto normalizedExe = executable;
	if (!isPortableExecutableName(normalizedExe)) {
		normalizedExe = toString(std::filesystem::path(executable).lexically_normal());
	}
	const auto executableWide = std::filesystem::path(normalizedExe).wstring();
	const auto argumentWide = std::wstring(arguments.begin(), arguments.end());
	auto commandLine = L"\"" + executableWide + L"\"" +
		(arguments.empty() ? L"" : L" " + argumentWide);

	STARTUPINFOW startupInfo {};
	startupInfo.cb = sizeof(startupInfo);
	PROCESS_INFORMATION processInfo {};
	const BOOL started = CreateProcessW(
		nullptr,
		commandLine.data(),
		nullptr,
		nullptr,
		FALSE,
		CREATE_NEW_CONSOLE,
		nullptr,
		nullptr,
		&startupInfo,
		&processInfo);
	if (started) {
		CloseHandle(processInfo.hThread);
		CloseHandle(processInfo.hProcess);
		return true;
	}
#if defined(OFXGGML_LLAMA_HAS_OF_RUNTIME)
	ofLogError(LogModule) << "Failed to launch process: " << GetLastError();
#endif
	return false;
#else
	auto command = quoteArgument(executable);
	if (!arguments.empty()) {
		command += " " + arguments;
	}
	command += " >/dev/null 2>&1 &";
	return std::system(command.c_str()) == 0;
#endif
}

bool ofxGgmlLlamaCodexLocal::startLlamaServer(
	const ofxGgmlLlamaServerStartSettings & settings) {
	if (settings.serverExe.empty() || settings.modelPath.empty()) {
		return false;
	}
	const auto serverRoot = serverRootFromBaseUrl(settings.serverUrl);
	const int port = serverPortFromUrl(serverRoot, 8001);
	std::ostringstream args;
	args << "-m " << quoteArgument(settings.modelPath);
	args << " --host 127.0.0.1 --port " << port;
	args << " -ngl " << (settings.gpuLayersAll
		? std::string("all")
		: std::to_string(std::max(0, settings.gpuLayers)));
	args << " --ctx-size " << std::max(512, settings.contextSize);
	args << " --parallel " << std::max(1, settings.parallel);
	args << " --batch-size " << std::max(1, settings.batchSize);
	args << " --ubatch-size " << std::max(1, settings.ubatchSize);
	if (settings.threads > 0 && executableSupportsArgument(settings.serverExe, "--threads")) {
		args << " --threads " << settings.threads;
	}
	if (settings.threadsBatch > 0 &&
		executableSupportsArgument(settings.serverExe, "--threads-batch")) {
		args << " --threads-batch " << settings.threadsBatch;
	}
	if (settings.threadsHttp > 0 &&
		executableSupportsArgument(settings.serverExe, "--threads-http")) {
		args << " --threads-http " << settings.threadsHttp;
	}
	if (settings.cacheReuse > 0 &&
		executableSupportsArgument(settings.serverExe, "--cache-reuse")) {
		args << " --cache-reuse " << settings.cacheReuse;
	}
	if (!settings.modelAlias.empty()) {
		args << " --alias " << quoteArgument(settings.modelAlias);
	}
	if (settings.jinja && executableSupportsArgument(settings.serverExe, "--jinja")) {
		args << " --jinja";
	}
	if (settings.flashAttention && executableSupportsArgument(settings.serverExe, "--flash-attn")) {
		args << " --flash-attn on";
	}
	if (settings.noCudaGraphs && executableSupportsArgument(settings.serverExe, "--no-cuda-graphs")) {
		args << " --no-cuda-graphs";
	}
	if (settings.skipChatParsing && executableSupportsArgument(settings.serverExe, "--skip-chat-parsing")) {
		args << " --skip-chat-parsing";
	}
	if (settings.reasoningOff && executableSupportsArgument(settings.serverExe, "--reasoning")) {
		args << " --reasoning off";
	}
	if (settings.reasoningOff && executableSupportsArgument(settings.serverExe, "--reasoning-budget")) {
		args << " --reasoning-budget 0";
	}
	args << " --temp " << settings.temperature;
	args << " --top-p " << settings.topP;
	args << " --min-p " << settings.minP;
	for (const auto & extra : settings.extraArgs) {
		if (!extra.empty()) {
			args << " " << extra;
		}
	}

#if defined(OFXGGML_LLAMA_HAS_OF_RUNTIME)
	ofLogNotice(LogModule)
		<< "starting llama-server\n"
		<< "exe: " << settings.serverExe << "\n"
		<< "model: " << settings.modelPath << "\n"
		<< "server: " << serverRoot << "\n"
		<< "alias: " << settings.modelAlias;
#endif
	return launchDetachedProcess(settings.serverExe, args.str());
}
