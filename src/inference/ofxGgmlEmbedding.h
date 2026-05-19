#pragma once

#include <functional>
#include <memory>
#include <string>
#include <mutex>
#include <utility>
#include <vector>

struct ofxGgmlEmbeddingSettings {
	std::string serverUrl;
	std::string serverModel;
	int timeoutSeconds = 180;
};

struct ofxGgmlEmbeddingRequest {
	std::string input;
	std::vector<std::string> inputs;
	ofxGgmlEmbeddingSettings settings;
};

struct ofxGgmlEmbeddingResult {
	bool success = false;
	float elapsedMs = 0.0f;
	std::vector<float> embedding;
	std::vector<std::vector<float>> embeddings;
	std::string error;
	std::string backendName;
	std::string rawOutput;
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

class ofxGgmlEmbeddingBackend {
public:
	virtual ~ofxGgmlEmbeddingBackend() = default;
	virtual std::string getBackendName() const = 0;
	virtual ofxGgmlEmbeddingResult embed(
		const ofxGgmlEmbeddingRequest & request) const = 0;
};

class ofxGgmlEmbeddingBridgeBackend : public ofxGgmlEmbeddingBackend {
public:
	using EmbedFunction = std::function<ofxGgmlEmbeddingResult(
		const ofxGgmlEmbeddingRequest &)>;

	explicit ofxGgmlEmbeddingBridgeBackend(
		EmbedFunction embedFunction = {},
		std::string displayName = "EmbeddingBridge");

	void setEmbedFunction(EmbedFunction embedFunction);
	bool isConfigured() const;

	std::string getBackendName() const override;
	ofxGgmlEmbeddingResult embed(
		const ofxGgmlEmbeddingRequest & request) const override;

private:
	EmbedFunction embedCallback;
	std::string displayName;
	mutable std::mutex callbackMutex;
};

class ofxGgmlEmbeddingGenerator {
public:
	ofxGgmlEmbeddingGenerator();

	static std::shared_ptr<ofxGgmlEmbeddingBackend> createEmbeddingBridgeBackend(
		ofxGgmlEmbeddingBridgeBackend::EmbedFunction embedFunction = {},
		const std::string & displayName = "EmbeddingBridge");

	void setBackend(std::shared_ptr<ofxGgmlEmbeddingBackend> backend);
	std::shared_ptr<ofxGgmlEmbeddingBackend> getBackend() const;

	ofxGgmlEmbeddingResult embed(
		const ofxGgmlEmbeddingRequest & request) const;
	ofxGgmlEmbeddingResult embed(
		const std::string & input,
		const ofxGgmlEmbeddingSettings & settings = {}) const;

private:
	std::shared_ptr<ofxGgmlEmbeddingBackend> backendPtr;
	mutable std::mutex backendMutex;
};

namespace ofxGgmlEmbeddingUtils {

float dotProduct(
	const std::vector<float> & a,
	const std::vector<float> & b);
float l2Norm(const std::vector<float> & values);
float cosineSimilarity(
	const std::vector<float> & a,
	const std::vector<float> & b);

} // namespace ofxGgmlEmbeddingUtils
