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

struct ofxGgmlLlamaCodexProviderConfig {
	std::string providerId = "llama_cpp";
	std::string providerName = "llama.cpp local";
	std::string profile = "ofxggml_local";
	std::string baseUrl = "http://127.0.0.1:8001/v1";
	std::string modelAlias;
	std::string wireApi = "responses";
	int modelContextWindow = 40960;
	int modelAutoCompactTokenLimit = 30000;
	int toolOutputTokenLimit = 5000;
	int agentMaxConcurrentThreadsPerSession = 1;
	int agentMaxDepth = 1;
	int agentMinWaitTimeoutMs = 2500;
	int agentMaxWaitTimeoutMs = 120000;
	int agentDefaultWaitTimeoutMs = 30000;
	bool multiAgentV2Enabled = true;
	int streamIdleTimeoutMs = 10000000;
	bool writeTopLevelSelection = true;
	bool writeAgentSettings = true;
	bool writeAgentRoleFiles = true;
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
	int contextSize = 40960;
	int parallel = 1;
	int batchSize = 2048;
	int ubatchSize = 512;
	float temperature = 1.0f;
	float topP = 0.95f;
	float minP = 0.01f;
	bool noCudaGraphs = true;
	bool skipChatParsing = false;
	bool jinja = true;
	bool flashAttention = true;
	bool reasoningOff = true;
	std::vector<std::string> extraArgs;
};

class ofxGgmlLlamaCodexLocal {
public:
	static std::string trimCopy(const std::string & value);
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
	static bool executableSupportsArgument(
		const std::string & executable,
		const std::string & argument);
	static bool launchDetachedProcess(
		const std::string & executable,
		const std::string & arguments);
	static bool startLlamaServer(const ofxGgmlLlamaServerStartSettings & settings);
};
