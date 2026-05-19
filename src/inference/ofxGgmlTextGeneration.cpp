#include "ofxGgmlTextGeneration.h"

#include <chrono>
#include <utility>

ofxGgmlTextBridgeBackend::ofxGgmlTextBridgeBackend(
	GenerateFunction generateFunction,
	std::string displayName)
	: generateCallback(std::move(generateFunction))
	, displayName(std::move(displayName)) {
}

void ofxGgmlTextBridgeBackend::setGenerateFunction(
	GenerateFunction generateFunction) {
	std::lock_guard<std::mutex> lock(callbackMutex);
	generateCallback = std::move(generateFunction);
}

bool ofxGgmlTextBridgeBackend::isConfigured() const {
	std::lock_guard<std::mutex> lock(callbackMutex);
	return static_cast<bool>(generateCallback);
}

std::string ofxGgmlTextBridgeBackend::getBackendName() const {
	return displayName.empty() ? "TextBridge" : displayName;
}

ofxGgmlTextResult ofxGgmlTextBridgeBackend::generate(
	const ofxGgmlTextRequest & request,
	ofxGgmlTextChunkCallback onChunk) const {
	GenerateFunction callback;
	{
		std::lock_guard<std::mutex> lock(callbackMutex);
		callback = generateCallback;
	}

	ofxGgmlTextResult result;
	result.backendName = getBackendName();
	if (!callback) {
		result.error =
			"text bridge backend is not configured. Attach a text generation "
			"adapter callback before calling generate().";
		return result;
	}

	const auto started = std::chrono::steady_clock::now();
	result = callback(request, onChunk);
	if (result.backendName.empty()) {
		result.backendName = getBackendName();
	}
	if (result.elapsedMs <= 0.0f) {
		result.elapsedMs = std::chrono::duration<float, std::milli>(
			std::chrono::steady_clock::now() - started).count();
	}
	return result;
}

ofxGgmlTextGenerator::ofxGgmlTextGenerator()
	: backendPtr(createTextBridgeBackend()) {
}

std::shared_ptr<ofxGgmlTextBackend>
ofxGgmlTextGenerator::createTextBridgeBackend(
	ofxGgmlTextBridgeBackend::GenerateFunction generateFunction,
	const std::string & displayName) {
	return std::make_shared<ofxGgmlTextBridgeBackend>(
		std::move(generateFunction),
		displayName);
}

void ofxGgmlTextGenerator::setBackend(std::shared_ptr<ofxGgmlTextBackend> backend) {
	std::lock_guard<std::mutex> lock(backendMutex);
	backendPtr = backend ? std::move(backend) : createTextBridgeBackend();
}

std::shared_ptr<ofxGgmlTextBackend> ofxGgmlTextGenerator::getBackend() const {
	std::lock_guard<std::mutex> lock(backendMutex);
	return backendPtr;
}

ofxGgmlTextResult ofxGgmlTextGenerator::generate(
	const ofxGgmlTextRequest & request,
	ofxGgmlTextChunkCallback onChunk) const {
	std::shared_ptr<ofxGgmlTextBackend> backend;
	{
		std::lock_guard<std::mutex> lock(backendMutex);
		backend = backendPtr ? backendPtr : createTextBridgeBackend();
	}
	return backend->generate(request, std::move(onChunk));
}

ofxGgmlTextResult ofxGgmlTextGenerator::generate(
	const std::string & prompt,
	const std::string & modelPath,
	const ofxGgmlTextGenerationSettings & settings,
	ofxGgmlTextChunkCallback onChunk) const {
	ofxGgmlTextRequest request;
	request.prompt = prompt;
	request.modelPath = modelPath;
	request.settings = settings;
	return generate(request, std::move(onChunk));
}
