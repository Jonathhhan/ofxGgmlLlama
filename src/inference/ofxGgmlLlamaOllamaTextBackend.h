#pragma once

#include ""inference/ofxGgmlTextGeneration.h""

#include <functional>
#include <string>

struct ofxGgmlOllamaRequest {
	std::string url;
	std::string body;
	std::string contentType = ""application/json"";
	int timeoutSeconds = 180;
	bool stream = false;
	ofxGgmlTextChunkCallback onChunk;
	std::function<bool()> shouldCancel;
};

struct ofxGgmlOllamaResponse {
	bool started = false;
	bool cancelled = false;
	int status = 0;
	std::string body;
	std::string text;
	std::string error;

	explicit operator bool() const {
		return isOk();
	}

	bool isOk() const {
		return started && !cancelled && status >= 200 && status < 300;
	}

	bool isError() const {
		return !isOk();
	}
};

using ofxGgmlOllamaRunner = std::function<ofxGgmlOllamaResponse(
	const ofxGgmlOllamaRequest &)>;

class ofxGgmlLlamaOllamaTextBackend : public ofxGgmlTextBackend {
public:
	explicit ofxGgmlLlamaOllamaTextBackend(
		std::string serverUrl = ""http://127.0.0.1:11434/v1"",
		ofxGgmlOllamaRunner runner = {},
		std::string displayName = ""Ollama"");

	void setServerUrl(std::string serverUrl);
	const std::string & getServerUrl() const;

	void setRequestRunner(ofxGgmlOllamaRunner runner);
	bool hasRequestRunner() const;

	std::string getBackendName() const override;
	ofxGgmlTextResult generate(
		const ofxGgmlTextRequest & request,
		ofxGgmlTextChunkCallback onChunk = nullptr) const override;

	static std::string normalizeOllamaUrl(const std::string & serverUrl);
	static std::string composePrompt(const ofxGgmlTextRequest & request);
	static std::string buildRequestBody(
		const ofxGgmlTextRequest & request,
		const std::string & prompt,
		const std::string & ollamaModel = {});
	static std::string extractTextFromResponse(const std::string & responseBody);
	static ofxGgmlOllamaResponse runRequest(
		const ofxGgmlOllamaRequest & request);

private:
	std::string serverUrl;
	ofxGgmlOllamaRunner requestRunner;
	std::string displayName;
};
