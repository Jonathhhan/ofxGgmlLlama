#pragma once

#include "ofMain.h"
#include "ofxGgmlLlama.h"
#include "ofxImGui.h"

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class ofApp : public ofBaseApp {
public:
    void setup() override;
    void draw() override;
    void keyPressed(int key) override;
    void exit() override;

private:
    void requestStartServer(bool force);
    void runStartServerWorker(bool force);
    void requestEndpointSmoke();
    void runEndpointSmokeWorker();
    void requestWriteConfig();
    void requestLaunchCodex();
    void runLaunchCodexWorker();
    void refreshRuntimeDiscovery();
    void refreshServerStatus();
    void refreshModelMetadata();
    void refreshModelAliasForPath(const std::string & previousModelPath);
    void applyModelContextMetadataDefaults();
    void applyPreset(int index);
    void applyInteractiveThreadBudget(
        bool overwriteAgentOverride,
        bool overwriteThreadOverride,
        bool overwriteBatchThreadOverride,
        bool overwriteHttpThreadOverride);
    bool adoptServedModelAliasIfNeeded();
    bool syncCodexConfig();
    bool syncHermesConfig();
    std::vector<std::string> collectPreflightIssues(
        bool requireLocalServer,
        bool requireCodexExecutable) const;
    std::string formatPreflightSummary(const std::vector<std::string> & issues) const;
    std::string buildCodexConfigSnippetText() const;
    std::string buildHermesConfigSnippetText() const;
    std::string buildHermesBridgeConfigSnippetText() const;
    std::string buildManualServerCommand() const;
    std::string buildCodexLaunchCommand() const;
    void copyTextToClipboard(const std::string & label, const std::string & text);
    void rebuildLines();
    void joinWorker();

    ofxGgmlLlamaCodexProviderConfig makeCodexConfig() const;
    ofxGgmlLlamaServerStartSettings makeServerSettings() const;
    ofxGgmlLlamaHermesConfig makeHermesConfig() const;

    ofxImGui::Gui gui;
    std::thread worker;
    mutable std::mutex stateMutex;
    std::atomic_bool cancelRequested { false };

    std::string baseUrl;
    std::string serverUrl;
    std::string modelAlias;
    std::string openAiModelAlias = "gpt-5";
    std::string modelPath;
    std::string codexExe;
    std::string serverExe;
    std::string hermesExe;
    std::string codexProfile;
    std::string codexSandbox = "";
    std::string configPath;
    std::string wireApi = "responses";
    std::string webSearch = "live";

    std::string status;
    std::string endpointStatus;
    std::string endpointOutput;
    std::string configWriteStatus;
    std::string hermesConfigWriteStatus;
    std::string preflightStatus;
    std::string wireApiProbeStatus;
    std::string servedModelStatus;
    std::vector<std::string> servedModelAliases;
    std::vector<std::string> lines;

    int gpuLayers = 999;
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
    int modelContextWindow = 65536;
    int modelAutoCompactTokenLimit = 56000;
    int toolOutputTokenLimit = 12000;
    int agentMaxConcurrentThreadsPerSession = 1;
    int agentMaxDepth = 0;
    int agentMinWaitTimeoutMs = 2500;
    int agentMaxWaitTimeoutMs = 180000;
    int agentDefaultWaitTimeoutMs = 30000;
    int reasoningEffortIndex = 2;
    int startupTimeoutSeconds = 600;
    int presetIndex = 1;
    uint64_t modelLayerCount = 0;
    uint64_t modelContextLength = 0;
    float temperature = 0.2f;
    float topP = 0.85f;
    float minP = 0.03f;
    bool gpuLayersAll = true;
    bool noCudaGraphs = false;
    bool skipChatParsing = false;
    bool autoConfig = true;
    bool codexSandboxManuallyEdited = false;
    bool modelAliasManuallyEdited = false;
    bool modelContextWindowManuallyEdited = false;
    bool modelAutoCompactManuallyEdited = false;
    bool serverReady = false;
    bool endpointReady = false;
    bool running = false;
    int codexProviderMode = 0;
};
