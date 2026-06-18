#pragma once

#include <functional>
#include <string>
#include <vector>

struct ofxGgmlLlamaServerProbe {
	bool reachable = false;
	bool ready = false;
	int status = 0;
	std::string message;

	explicit operator bool() const {
		return ready;
	}
};

struct ofxGgmlLlamaServedModels {
	bool reachable = false;
	bool ready = false;
	bool expectedModelServed = false;
	int status = 0;
	std::vector<std::string> models;
	std::string message;
};

struct ofxGgmlLlamaCodexProviderConfig {
	std::string providerId = "llama_cpp";
	std::string providerName = "llama.cpp local";
	std::string profile = "ofxggml_local";
	std::string baseUrl = "http://127.0.0.1:8001/v1";
	std::string modelAlias;
	std::string wireApi = "responses";
	std::string webSearch = "live";
	int modelContextWindow = 65536;
	int modelAutoCompactTokenLimit = 56000;
	int toolOutputTokenLimit = 12000;
	int agentMaxConcurrentThreadsPerSession = 1;
	int agentMaxDepth = 0;
	int agentMinWaitTimeoutMs = 2500;
	int agentMaxWaitTimeoutMs = 180000;
	int agentDefaultWaitTimeoutMs = 30000;
	std::string modelReasoningEffort = "medium";
	std::string modelReasoningSummary = "none";
	std::string modelVerbosity = "low";
	bool hideAgentReasoning = true;
	int streamIdleTimeoutMs = 10000000;
	bool writeTopLevelSelection = true;
	bool writeLocalProviderToolGuards = true;
	bool writeAgentSettings = true;
	bool writeAgentRoleFiles = true;
	bool writeThreadMcpServer = true;
	std::string threadMcpServerId = "ofxggml_codex_threads";
	std::string threadMcpServerCwd;
};

struct ofxGgmlLlamaCodexConfigResult {
	bool ok = false;
	bool created = false;
	std::string path;
	std::string message;
};

struct ofxGgmlLlamaServerStartSettings {
	std::string serverExe;
	std::string modelPath;
	std::string serverUrl = "http://127.0.0.1:8001";
	std::string modelAlias;
	int gpuLayers = 999;
	bool gpuLayersAll = true;
	int contextSize = 65536;
	int parallel = 1;
	int batchSize = 1024;
	int ubatchSize = 256;
	int threads = 0;
	int threadsBatch = 0;
	int threadsHttp = 0;
	int cacheReuse = 256;
	std::string kvCacheKeyType = "q4_0";
	std::string kvCacheValueType = "q4_0";
	std::string specType;
	std::string draftModelPath;
	std::string draftGpuLayers;
	int draftMaxTokens = 0;
	int draftMinTokens = 0;
	float draftPSplit = -1.0f;
	float draftPMin = -1.0f;
	float temperature = 0.2f;
	float topP = 0.85f;
	float minP = 0.03f;
	bool noCudaGraphs = false;
	bool skipChatParsing = false;
	bool jinja = true;
	bool flashAttention = true;
	bool reasoningOff = true;
	std::vector<std::string> extraArgs;
};

struct ofxGgmlLlamaCodexLaunchCommandSettings {
	std::string executable = "codex";
	std::string profile;
	std::string model;
	std::string sandbox;
	ofxGgmlLlamaCodexProviderConfig provider;
	bool includeLocalProviderToolGuards = false;
	bool includeLocalProviderOverrides = false;
	bool includeAgentOverrides = true;
};


struct ofxGgmlLlamaHermesConfig {
	std::string modelAlias;
	std::string baseUrl = "http://127.0.0.1:8001/v1";
	std::string apiKey = "local-dummy-key";
	int contextLength = 65536;
	std::string terminalBackend = "local";
	std::string hermesExe;
};

struct ofxGgmlLlamaHermesConfigResult {
	bool ok = false;
	bool created = false;
	std::string path;
	std::string message;
};

class ofxGgmlLlamaCodexLocal {
public:
	static std::string trimCopy(const std::string & value);
	static std::string normalizeEnvValue(const std::string & value);
	static std::string trimTrailingSlash(std::string value);
	static std::string envValue(const char * name);
	static std::string getEnvOrDefault(const char * name, const std::string & fallback);

	static std::string serverRootFromBaseUrl(const std::string & baseUrl);
	static std::string baseUrlFromServerRoot(const std::string & serverRoot);
	static int serverPortFromUrl(const std::string & serverUrl, int fallbackPort = 8001);
	static std::string codexApiRootFromBaseUrl(const std::string & baseUrl);

	static std::string modelAliasFromPath(const std::string & modelPath);
	static std::string resolveCodexConfigPath();
	static std::string discoverCodexExecutable();
	static std::string discoverLlamaServer();
	static std::string discoverTextModel();
	static bool fileExists(const std::string & path);

	static ofxGgmlLlamaServerProbe probeEndpoint(
		const std::string & endpointUrl,
		int timeoutSeconds = 2);
	static ofxGgmlLlamaServerProbe probeServerHealth(
		const std::string & serverUrl,
		int timeoutSeconds = 2);
	static ofxGgmlLlamaServedModels probeServedModels(
		const std::string & baseUrl,
		const std::string & expectedModel,
		int timeoutSeconds = 2);
	static ofxGgmlLlamaServerProbe waitForServerReady(
		const std::string & serverUrl,
		int timeoutSeconds,
		const std::function<bool()> & shouldCancel = {});
	static std::string describeProbe(const ofxGgmlLlamaServerProbe & probe);
	static std::string detectCodexWireApi(const std::string & baseUrl);

	static std::string buildCodexConfigSnippet(
		const ofxGgmlLlamaCodexProviderConfig & config);
	static ofxGgmlLlamaCodexConfigResult writeCodexConfig(
		const std::string & configPath,
		const ofxGgmlLlamaCodexProviderConfig & config);

	static std::string quoteArgument(const std::string & value);
	static std::string quotePowerShellArgument(const std::string & value);
	static std::string buildLaunchCommand(
		const ofxGgmlLlamaCodexLaunchCommandSettings & settings);
	static bool executableSupportsArgument(
		const std::string & executable,
		const std::string & argument);
	static bool launchDetachedProcess(
		const std::string & executable,
		const std::string & arguments);
	static bool launchUiProcess(const std::string & executable);
	static bool startLlamaServer(const ofxGgmlLlamaServerStartSettings & settings);

	static std::string resolveHermesConfigPath();
	static std::string discoverHermesExecutable();
	static std::string buildHermesConfigSnippet(
		const ofxGgmlLlamaHermesConfig & config);
	static ofxGgmlLlamaHermesConfigResult writeHermesConfig(
		const std::string & configPath,
		const ofxGgmlLlamaHermesConfig & config);
};
