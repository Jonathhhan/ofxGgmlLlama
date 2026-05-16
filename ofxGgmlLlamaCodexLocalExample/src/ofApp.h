#pragma once

#include "ofMain.h"
#include "ofxGgmlLlama.h"
#include "ofxImGui.h"

#include <atomic>
#include <cstddef>
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
	void refreshRuntimeDiscovery();
	void refreshServerStatus();
	void applyBaseUrlToServerUrl();
	void applyServerUrlToBaseUrl();
	void appendWrapped(const std::string & text, std::size_t maxChars);
	void rebuildLines();
	static std::string envValue(const char * name);
	static std::string getEnvOrDefault(const char * name, const std::string & fallback);
	static std::string normalizeEnvPath(const std::string & path);
	static std::string trimCopy(const std::string & value);
	static std::string serverRootFromBaseUrl(const std::string & value);
	static std::string baseUrlFromServerRoot(const std::string & value);
	static int serverPortFromUrl(const std::string & value, int fallbackPort);
	static bool fileExists(const std::string & path);

	std::string baseUrl;
	std::string serverUrl;
	std::string modelAlias;
	std::string modelPath;
	std::string serverExe;
	std::string status;
	std::string endpointStatus;
	std::string endpointOutput;
	std::vector<std::string> lines;
	ofxImGui::Gui gui;
	std::thread worker;
	std::mutex stateMutex;
	std::atomic_bool cancelRequested { false };
	int gpuLayers = 999;
	int contextSize = 131072;
	int startupTimeoutSeconds = 120;
	float temperature = 1.0f;
	float topP = 0.95f;
	float minP = 0.01f;
	bool noCudaGraphs = true;
	bool autoStartServer = true;
	bool serverReady = false;
	bool endpointReady = false;
	bool running = false;
};
