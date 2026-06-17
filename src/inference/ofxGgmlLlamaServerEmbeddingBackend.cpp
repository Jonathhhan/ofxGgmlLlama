#include "ofxGgmlLlamaServerEmbeddingBackend.h"

#include <chrono>
#include <cctype>
#include <cstdlib>
#include <sstream>
#include <utility>

#include "ofxGgmlString.h"
namespace {

std::vector<float> parseNumberArray(
	const std::string & json,
	std::size_t openBracket) {
	std::vector<float> values;
	if (openBracket >= json.size() || json[openBracket] != '[') {
		return values;
	}

	std::size_t index = openBracket + 1;
	while (index < json.size()) {
		while (index < json.size() &&
			(std::isspace(static_cast<unsigned char>(json[index])) ||
			json[index] == ',')) {
			++index;
		}
		if (index >= json.size() || json[index] == ']') {
			break;
		}

		const char * start = json.c_str() + index;
		char * end = nullptr;
		const double parsed = std::strtod(start, &end);
		if (end == start) {
			break;
		}
		values.push_back(static_cast<float>(parsed));
		index = static_cast<std::size_t>(end - json.c_str());
	}
	return values;
}

} // namespace

ofxGgmlLlamaServerEmbeddingBackend::ofxGgmlLlamaServerEmbeddingBackend(
	std::string serverUrl,
	ofxGgmlTextServerRunner runner,
	std::string displayName)
	: serverUrl(std::move(serverUrl))
	, requestRunner(runner ? std::move(runner) : ofxGgmlLlamaServerTextBackend::runRequest)
	, displayName(std::move(displayName)) {
}

void ofxGgmlLlamaServerEmbeddingBackend::setServerUrl(std::string serverUrl) {
	this->serverUrl = std::move(serverUrl);
}

const std::string & ofxGgmlLlamaServerEmbeddingBackend::getServerUrl() const {
	return serverUrl;
}

void ofxGgmlLlamaServerEmbeddingBackend::setRequestRunner(
	ofxGgmlTextServerRunner runner) {
	requestRunner = runner ? std::move(runner) : ofxGgmlLlamaServerTextBackend::runRequest;
}

bool ofxGgmlLlamaServerEmbeddingBackend::hasRequestRunner() const {
	return static_cast<bool>(requestRunner);
}

std::string ofxGgmlLlamaServerEmbeddingBackend::getBackendName() const {
	return displayName.empty() ? "llama-server-embedding" : displayName;
}

ofxGgmlEmbeddingResult ofxGgmlLlamaServerEmbeddingBackend::embed(
	const ofxGgmlEmbeddingRequest & request) const {
	ofxGgmlEmbeddingResult result;
	result.backendName = getBackendName();

	if (request.input.empty() && request.inputs.empty()) {
		result.error = "embedding input is empty";
		return result;
	}

	const std::string configuredUrl = request.settings.serverUrl.empty()
		? serverUrl
		: request.settings.serverUrl;
	const std::string requestUrl = normalizeServerUrl(configuredUrl);
	if (requestUrl.empty()) {
		result.error = "server URL is empty";
		return result;
	}

	const auto started = std::chrono::steady_clock::now();
	ofxGgmlTextServerRequest serverRequest;
	serverRequest.url = requestUrl;
	serverRequest.body = buildRequestBody(
		request,
		request.settings.serverModel);
	serverRequest.timeoutSeconds = request.settings.timeoutSeconds;
	const ofxGgmlTextServerResponse response = requestRunner(serverRequest);
	result.elapsedMs = std::chrono::duration<float, std::milli>(
		std::chrono::steady_clock::now() - started).count();
	result.rawOutput = response.body;
	result.metadata.push_back({ "serverUrl", requestUrl });
	if (!request.settings.serverModel.empty()) {
		result.metadata.push_back({ "serverModel", request.settings.serverModel });
	}

	if (!response.started) {
		result.error = response.error.empty()
			? "llama-server embedding request did not start"
			: response.error;
		result.error += " (" + requestUrl + ")";
		return result;
	}
	if (response.status <= 0) {
		result.error = "llama-server is not reachable at " + requestUrl;
		if (!response.error.empty()) {
			result.error += ": " + response.error;
		}
		return result;
	}
	if (response.status < 200 || response.status >= 300) {
		result.error = "llama-server embedding request failed with HTTP " +
			std::to_string(response.status) + " at " + requestUrl;
		if (!response.error.empty()) {
			result.error += ": " + response.error;
		} else if (!response.body.empty()) {
			result.error += ": " + response.body;
		}
		return result;
	}

	result.embeddings = extractEmbeddingsFromResponse(response.body);
	if (result.embeddings.empty()) {
		result.error = "llama-server returned no embeddings";
		return result;
	}
	result.embedding = result.embeddings.front();
	result.success = true;
	return result;
}

std::string ofxGgmlLlamaServerEmbeddingBackend::normalizeServerUrl(
	const std::string & serverUrl) {
	std::string normalized = ofxGgmlString::trimCopy(serverUrl);
	if (normalized.empty()) {
		normalized = "http://127.0.0.1:8081";
	}
	if (ofxGgmlString::endsWith(normalized, "/v1/embeddings") ||
		ofxGgmlString::endsWith(normalized, "/embeddings")) {
		return normalized;
	}
	normalized = ofxGgmlString::stripTrailingSlash(normalized);
	if (ofxGgmlString::endsWith(normalized, "/v1")) {
		return normalized + "/embeddings";
	}
	return normalized + "/v1/embeddings";
}

std::string ofxGgmlLlamaServerEmbeddingBackend::buildRequestBody(
	const ofxGgmlEmbeddingRequest & request,
	const std::string & serverModel) {
	std::ostringstream body;
	body << "{";
	if (!serverModel.empty()) {
		body << "\"model\":\"" << ofxGgmlString::escapeJson(serverModel) << "\",";
	}
	body << "\"input\":";
	if (!request.inputs.empty()) {
		body << "[";
		for (std::size_t i = 0; i < request.inputs.size(); ++i) {
			if (i > 0) {
				body << ",";
			}
			body << "\"" << ofxGgmlString::escapeJson(request.inputs[i]) << "\"";
		}
		body << "]";
	} else {
		body << "\"" << ofxGgmlString::escapeJson(request.input) << "\"";
	}
	body << "}";
	return body.str();
}

std::vector<std::vector<float>>
ofxGgmlLlamaServerEmbeddingBackend::extractEmbeddingsFromResponse(
	const std::string & responseBody) {
	std::vector<std::vector<float>> embeddings;
	const std::string key = "\"embedding\"";
	std::size_t searchFrom = 0;
	while (true) {
		const std::size_t keyPos = responseBody.find(key, searchFrom);
		if (keyPos == std::string::npos) {
			break;
		}
		const std::size_t colon = responseBody.find(':', keyPos + key.size());
		const std::size_t open = colon == std::string::npos
			? std::string::npos
			: responseBody.find('[', colon + 1);
		if (open == std::string::npos) {
			break;
		}
		auto parsed = parseNumberArray(responseBody, open);
		if (!parsed.empty()) {
			embeddings.push_back(std::move(parsed));
		}
		searchFrom = open + 1;
	}
	return embeddings;
}
