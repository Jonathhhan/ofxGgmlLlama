#include "ofxGgmlEmbedding.h"

#include <chrono>
#include <cmath>
#include <utility>

ofxGgmlEmbeddingBridgeBackend::ofxGgmlEmbeddingBridgeBackend(
	EmbedFunction embedFunction,
	std::string displayName)
	: embedCallback(std::move(embedFunction))
	, displayName(std::move(displayName)) {
}

void ofxGgmlEmbeddingBridgeBackend::setEmbedFunction(
	EmbedFunction embedFunction) {
	std::lock_guard<std::mutex> lock(callbackMutex);
	embedCallback = std::move(embedFunction);
}

bool ofxGgmlEmbeddingBridgeBackend::isConfigured() const {
	std::lock_guard<std::mutex> lock(callbackMutex);
	return static_cast<bool>(embedCallback);
}

std::string ofxGgmlEmbeddingBridgeBackend::getBackendName() const {
	return displayName.empty() ? "EmbeddingBridge" : displayName;
}

ofxGgmlEmbeddingResult ofxGgmlEmbeddingBridgeBackend::embed(
	const ofxGgmlEmbeddingRequest & request) const {
	EmbedFunction callback;
	{
		std::lock_guard<std::mutex> lock(callbackMutex);
		callback = embedCallback;
	}

	ofxGgmlEmbeddingResult result;
	result.backendName = getBackendName();
	if (!callback) {
		result.error =
			"embedding bridge backend is not configured. Attach an embedding "
			"adapter callback before calling embed().";
		return result;
	}

	const auto started = std::chrono::steady_clock::now();
	result = callback(request);
	if (result.backendName.empty()) {
		result.backendName = getBackendName();
	}
	if (result.elapsedMs <= 0.0f) {
		result.elapsedMs = std::chrono::duration<float, std::milli>(
			std::chrono::steady_clock::now() - started).count();
	}
	return result;
}

ofxGgmlEmbeddingGenerator::ofxGgmlEmbeddingGenerator()
	: backendPtr(createEmbeddingBridgeBackend()) {
}

std::shared_ptr<ofxGgmlEmbeddingBackend>
ofxGgmlEmbeddingGenerator::createEmbeddingBridgeBackend(
	ofxGgmlEmbeddingBridgeBackend::EmbedFunction embedFunction,
	const std::string & displayName) {
	return std::make_shared<ofxGgmlEmbeddingBridgeBackend>(
		std::move(embedFunction),
		displayName);
}

void ofxGgmlEmbeddingGenerator::setBackend(
	std::shared_ptr<ofxGgmlEmbeddingBackend> backend) {
	std::lock_guard<std::mutex> lock(backendMutex);
	backendPtr = backend ? std::move(backend) : createEmbeddingBridgeBackend();
}

std::shared_ptr<ofxGgmlEmbeddingBackend>
ofxGgmlEmbeddingGenerator::getBackend() const {
	std::lock_guard<std::mutex> lock(backendMutex);
	return backendPtr;
}

ofxGgmlEmbeddingResult ofxGgmlEmbeddingGenerator::embed(
	const ofxGgmlEmbeddingRequest & request) const {
	std::shared_ptr<ofxGgmlEmbeddingBackend> backend;
	{
		std::lock_guard<std::mutex> lock(backendMutex);
		backend = backendPtr ? backendPtr : createEmbeddingBridgeBackend();
	}
	return backend->embed(request);
}

ofxGgmlEmbeddingResult ofxGgmlEmbeddingGenerator::embed(
	const std::string & input,
	const ofxGgmlEmbeddingSettings & settings) const {
	ofxGgmlEmbeddingRequest request;
	request.input = input;
	request.settings = settings;
	return embed(request);
}

float ofxGgmlEmbeddingUtils::dotProduct(
	const std::vector<float> & a,
	const std::vector<float> & b) {
	if (a.empty() || a.size() != b.size()) {
		return 0.0f;
	}
	double sum = 0.0;
	for (std::size_t i = 0; i < a.size(); ++i) {
		sum += static_cast<double>(a[i]) * static_cast<double>(b[i]);
	}
	return static_cast<float>(sum);
}

float ofxGgmlEmbeddingUtils::l2Norm(const std::vector<float> & values) {
	if (values.empty()) {
		return 0.0f;
	}
	double sum = 0.0;
	for (const float value : values) {
		sum += static_cast<double>(value) * static_cast<double>(value);
	}
	return static_cast<float>(std::sqrt(sum));
}

float ofxGgmlEmbeddingUtils::cosineSimilarity(
	const std::vector<float> & a,
	const std::vector<float> & b) {
	const float normA = l2Norm(a);
	const float normB = l2Norm(b);
	if (normA <= 0.0f || normB <= 0.0f || a.size() != b.size()) {
		return 0.0f;
	}
	return dotProduct(a, b) / (normA * normB);
}
