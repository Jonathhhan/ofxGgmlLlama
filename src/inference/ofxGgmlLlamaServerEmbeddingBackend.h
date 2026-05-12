#pragma once

#include "ofxGgmlEmbedding.h"
#include "ofxGgmlLlamaServerTextBackend.h"

class ofxGgmlLlamaServerEmbeddingBackend : public ofxGgmlEmbeddingBackend {
public:
	explicit ofxGgmlLlamaServerEmbeddingBackend(
		std::string serverUrl = "http://127.0.0.1:8081",
		ofxGgmlTextServerRunner runner = {},
		std::string displayName = "llama-server-embedding");

	void setServerUrl(std::string serverUrl);
	const std::string & getServerUrl() const;

	void setRequestRunner(ofxGgmlTextServerRunner runner);
	bool hasRequestRunner() const;

	std::string getBackendName() const override;
	ofxGgmlEmbeddingResult embed(
		const ofxGgmlEmbeddingRequest & request) const override;

	static std::string normalizeServerUrl(const std::string & serverUrl);
	static std::string buildRequestBody(
		const ofxGgmlEmbeddingRequest & request,
		const std::string & serverModel = {});
	static std::vector<std::vector<float>> extractEmbeddingsFromResponse(
		const std::string & responseBody);

private:
	std::string serverUrl;
	ofxGgmlTextServerRunner requestRunner;
	std::string displayName;
};
