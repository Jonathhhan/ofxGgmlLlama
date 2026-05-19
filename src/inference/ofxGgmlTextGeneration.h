#pragma once

#include <functional>
#include <memory>
#include <string>
#include <mutex>
#include <utility>
#include <vector>

enum class ofxGgmlTextRole {
	System = 0,
	User,
	Assistant
};

struct ofxGgmlTextMessage {
	ofxGgmlTextRole role = ofxGgmlTextRole::User;
	std::string content;
};

struct ofxGgmlTextGenerationSettings {
	int maxTokens = 256;
	float temperature = 0.8f;
	float topP = 0.95f;
	int topK = 40;
	float repeatPenalty = 1.05f;
	int contextSize = 2048;
	int batchSize = 512;
	int gpuLayers = -1;
	int threads = 0;
	int seed = -1;
	bool stream = false;
	bool useServerBackend = false;
	std::string serverUrl;
	std::string serverModel;
	std::string executablePath;
	std::vector<std::string> stopSequences;
};

struct ofxGgmlTextRequest {
	std::string modelPath;
	std::string prompt;
	std::string systemPrompt;
	std::vector<ofxGgmlTextMessage> messages;
	ofxGgmlTextGenerationSettings settings;
};

struct ofxGgmlTextResult {
	bool success = false;
	float elapsedMs = 0.0f;
	std::string text;
	std::string error;
	std::string backendName;
	std::string finishReason;
	std::string rawOutput;
	int tokensGenerated = 0;
	std::vector<std::pair<std::string, std::string>> metadata;

	explicit operator bool() const {
		return isOk();
	}

	bool isOk() const {
		return success;
	}

	bool isError() const {
		return !isOk();
	}
};

using ofxGgmlTextChunkCallback = std::function<bool(const std::string &)>;

class ofxGgmlTextBackend {
public:
	virtual ~ofxGgmlTextBackend() = default;
	virtual std::string getBackendName() const = 0;
	virtual ofxGgmlTextResult generate(
		const ofxGgmlTextRequest & request,
		ofxGgmlTextChunkCallback onChunk = nullptr) const = 0;
};

class ofxGgmlTextBridgeBackend : public ofxGgmlTextBackend {
public:
	using GenerateFunction = std::function<ofxGgmlTextResult(
		const ofxGgmlTextRequest &,
		const ofxGgmlTextChunkCallback &)>;

	explicit ofxGgmlTextBridgeBackend(
		GenerateFunction generateFunction = {},
		std::string displayName = "TextBridge");

	void setGenerateFunction(GenerateFunction generateFunction);
	bool isConfigured() const;

	std::string getBackendName() const override;
	ofxGgmlTextResult generate(
		const ofxGgmlTextRequest & request,
		ofxGgmlTextChunkCallback onChunk = nullptr) const override;

private:
	GenerateFunction generateCallback;
	std::string displayName;
	mutable std::mutex callbackMutex;
};

class ofxGgmlTextGenerator {
public:
	ofxGgmlTextGenerator();

	static std::shared_ptr<ofxGgmlTextBackend> createTextBridgeBackend(
		ofxGgmlTextBridgeBackend::GenerateFunction generateFunction = {},
		const std::string & displayName = "TextBridge");

	void setBackend(std::shared_ptr<ofxGgmlTextBackend> backend);
	std::shared_ptr<ofxGgmlTextBackend> getBackend() const;

	ofxGgmlTextResult generate(
		const ofxGgmlTextRequest & request,
		ofxGgmlTextChunkCallback onChunk = nullptr) const;
	ofxGgmlTextResult generate(
		const std::string & prompt,
		const std::string & modelPath = {},
		const ofxGgmlTextGenerationSettings & settings = {},
		ofxGgmlTextChunkCallback onChunk = nullptr) const;

private:
	std::shared_ptr<ofxGgmlTextBackend> backendPtr;
	mutable std::mutex backendMutex;
};
