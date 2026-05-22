#include "ofxGgmlLlamaServerTextBackend.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <sstream>
#include <utility>
#include <vector>

#if __has_include("ofMain.h")
#include "ofMain.h"
#define OFXGGML_HAS_OF_HTTP_RUNTIME 1
#endif

#if defined(OFXGGML_HAS_OF_HTTP_RUNTIME) && __has_include("curl/curl.h")
#if defined(_WIN32) && !defined(CURL_STATICLIB)
#define CURL_STATICLIB
#endif
#include "curl/curl.h"
#define OFXGGML_HAS_CURL_HTTP_RUNTIME 1
#endif

namespace {

std::string trimCopy(const std::string & value) {
	std::size_t first = 0;
	while (first < value.size() &&
		std::isspace(static_cast<unsigned char>(value[first]))) {
		++first;
	}
	std::size_t last = value.size();
	while (last > first &&
		std::isspace(static_cast<unsigned char>(value[last - 1]))) {
		--last;
	}
	return value.substr(first, last - first);
}

bool endsWith(const std::string & value, const std::string & suffix) {
	return value.size() >= suffix.size() &&
		value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool startsWith(const std::string & value, const std::string & prefix) {
	return value.size() >= prefix.size() &&
		value.compare(0, prefix.size(), prefix) == 0;
}

std::string stripTrailingSlash(std::string value) {
	while (!value.empty() && value.back() == '/') {
		value.pop_back();
	}
	return value;
}

std::string roleLabel(ofxGgmlTextRole role) {
	switch (role) {
	case ofxGgmlTextRole::System: return "system";
	case ofxGgmlTextRole::User: return "user";
	case ofxGgmlTextRole::Assistant: return "assistant";
	}
	return "user";
}

std::string escapeJson(const std::string & value) {
	std::ostringstream escaped;
	for (const unsigned char c : value) {
		switch (c) {
		case '\\': escaped << "\\\\"; break;
		case '"': escaped << "\\\""; break;
		case '\b': escaped << "\\b"; break;
		case '\f': escaped << "\\f"; break;
		case '\n': escaped << "\\n"; break;
		case '\r': escaped << "\\r"; break;
		case '\t': escaped << "\\t"; break;
		default:
			if (c < 0x20) {
				const char * hex = "0123456789abcdef";
				escaped << "\\u00" << hex[(c >> 4) & 0x0f] << hex[c & 0x0f];
			} else {
				escaped << static_cast<char>(c);
			}
			break;
		}
	}
	return escaped.str();
}

std::string eraseDelimitedBlock(
	std::string value,
	const std::string & beginMarker,
	const std::string & endMarker) {
	std::size_t begin = value.find(beginMarker);
	while (begin != std::string::npos) {
		const std::size_t end = value.find(endMarker, begin + beginMarker.size());
		const std::size_t eraseEnd = end == std::string::npos
			? value.size()
			: end + endMarker.size();
		value.erase(begin, eraseEnd - begin);
		begin = value.find(beginMarker, begin);
	}
	return value;
}

std::string stripReasoningBlocks(std::string value) {
	value = eraseDelimitedBlock(value, "<think>", "</think>");
	value = eraseDelimitedBlock(value, "<thinking>", "</thinking>");
	value = eraseDelimitedBlock(value, "[Start thinking]", "[End thinking]");
	value = eraseDelimitedBlock(value, "[Start thinking]", "[Stop thinking]");
	value = eraseDelimitedBlock(value, "[Thinking]", "[/Thinking]");
	return trimCopy(value);
}

std::string stripLeadingRoleEchoes(const std::string & value) {
	std::istringstream lines(value);
	std::ostringstream cleaned;
	std::string line;
	bool wroteLine = false;
	bool sawAssistantText = false;
	while (std::getline(lines, line)) {
		if (!line.empty() && line.back() == '\r') {
			line.pop_back();
		}
		if (!sawAssistantText) {
			const std::string trimmed = trimCopy(line);
			if (startsWith(trimmed, "System:") || startsWith(trimmed, "User:")) {
				continue;
			}
			if (startsWith(trimmed, "Assistant:")) {
				line = trimCopy(trimmed.substr(10));
				if (line.empty()) {
					continue;
				}
			}
			if (!trimCopy(line).empty()) {
				sawAssistantText = true;
			}
		}
		if (wroteLine) {
			cleaned << '\n';
		}
		cleaned << line;
		wroteLine = true;
	}
	return trimCopy(cleaned.str());
}

std::string sanitizeModelVisibleText(const std::string & value) {
	return stripLeadingRoleEchoes(stripReasoningBlocks(value));
}

class ReasoningStreamFilter {
public:
	std::string push(const std::string & chunk) {
		if (chunk.empty()) {
			return {};
		}
		pending += chunk;
		std::string visible;
		while (!pending.empty()) {
			if (insideReasoning) {
				const auto end = findEarliest(pending, endMarkers());
				if (end.found) {
					pending.erase(0, end.position + end.marker.size());
					insideReasoning = false;
					continue;
				}
				keepReasoningTail();
				break;
			}
			const auto begin = findEarliest(pending, beginMarkers());
			if (begin.found) {
				visible += pending.substr(0, begin.position);
				pending.erase(0, begin.position + begin.marker.size());
				insideReasoning = true;
				continue;
			}
			flushSafeVisiblePrefix(visible);
			break;
		}
		return visible;
	}

	std::string finish() {
		if (insideReasoning) {
			pending.clear();
			return {};
		}
		std::string visible = pending;
		pending.clear();
		return visible;
	}

private:
	struct MarkerMatch {
		bool found = false;
		std::size_t position = std::string::npos;
		std::string marker;
	};

	static const std::vector<std::string> & beginMarkers() {
		static const std::vector<std::string> markers = {
			"<think>",
			"<thinking>",
			"[Start thinking]",
			"[Thinking]"
		};
		return markers;
	}

	static const std::vector<std::string> & endMarkers() {
		static const std::vector<std::string> markers = {
			"</think>",
			"</thinking>",
			"[End thinking]",
			"[Stop thinking]",
			"[/Thinking]"
		};
		return markers;
	}

	static MarkerMatch findEarliest(
		const std::string & value,
		const std::vector<std::string> & markers) {
		MarkerMatch result;
		for (const auto & marker : markers) {
			const std::size_t position = value.find(marker);
			if (position != std::string::npos &&
				(!result.found || position < result.position)) {
				result.found = true;
				result.position = position;
				result.marker = marker;
			}
		}
		return result;
	}

	static std::size_t maxMarkerSize(const std::vector<std::string> & markers) {
		std::size_t size = 0;
		for (const auto & marker : markers) {
			size = std::max(size, marker.size());
		}
		return size;
	}

	void keepReasoningTail() {
		const std::size_t keep = maxMarkerSize(endMarkers()) - 1;
		if (pending.size() > keep) {
			pending.erase(0, pending.size() - keep);
		}
	}

	void flushSafeVisiblePrefix(std::string & visible) {
		const std::size_t keep = maxMarkerSize(beginMarkers()) - 1;
		if (pending.size() <= keep) {
			return;
		}
		const std::size_t flushCount = pending.size() - keep;
		visible += pending.substr(0, flushCount);
		pending.erase(0, flushCount);
	}

	std::string pending;
	bool insideReasoning = false;
};

bool appendDecodedJsonChar(const std::string & value, std::size_t & index, std::string & out) {
	if (index >= value.size()) {
		return false;
	}
	const char c = value[index++];
	if (c != '\\') {
		out.push_back(c);
		return true;
	}
	if (index >= value.size()) {
		return false;
	}
	const char escaped = value[index++];
	switch (escaped) {
	case '"': out.push_back('"'); return true;
	case '\\': out.push_back('\\'); return true;
	case '/': out.push_back('/'); return true;
	case 'b': out.push_back('\b'); return true;
	case 'f': out.push_back('\f'); return true;
	case 'n': out.push_back('\n'); return true;
	case 'r': out.push_back('\r'); return true;
	case 't': out.push_back('\t'); return true;
	case 'u':
		if (index + 4 <= value.size()) {
			index += 4;
		}
		return true;
	default:
		out.push_back(escaped);
		return true;
	}
}

std::string extractJsonStringField(const std::string & json, const std::string & key) {
	const std::string quotedKey = "\"" + key + "\"";
	std::size_t searchFrom = 0;
	while (true) {
		const std::size_t keyPos = json.find(quotedKey, searchFrom);
		if (keyPos == std::string::npos) {
			return {};
		}
		const std::size_t colon = json.find(':', keyPos + quotedKey.size());
		if (colon == std::string::npos) {
			return {};
		}
		std::size_t valueStart = colon + 1;
		while (valueStart < json.size() &&
			std::isspace(static_cast<unsigned char>(json[valueStart]))) {
			++valueStart;
		}
		if (valueStart >= json.size() || json[valueStart] != '"') {
			searchFrom = valueStart;
			continue;
		}
		++valueStart;
		std::string decoded;
		while (valueStart < json.size()) {
			if (json[valueStart] == '"') {
				return decoded;
			}
			if (!appendDecodedJsonChar(json, valueStart, decoded)) {
				return {};
			}
		}
		return {};
	}
}

bool processServerSentEventLine(
	const std::string & line,
	ofxGgmlTextServerResponse & response,
	const ofxGgmlTextChunkCallback & onChunk) {
	const std::string prefix = "data:";
	if (line.compare(0, prefix.size(), prefix) != 0) {
		return true;
	}
	std::string payload = trimCopy(line.substr(prefix.size()));
	if (payload.empty() || payload == "[DONE]") {
		return true;
	}
	response.body += payload;
	response.body.push_back('\n');
	const std::string text = ofxGgmlLlamaServerTextBackend::extractTextFromResponse(payload);
	if (text.empty()) {
		return true;
	}
	response.text += text;
	if (onChunk && !onChunk(text)) {
		response.cancelled = true;
		response.error = "llama-server request cancelled";
		return false;
	}
	return true;
}

#if defined(OFXGGML_HAS_CURL_HTTP_RUNTIME)
struct CurlStreamState {
	ofxGgmlTextServerResponse * response = nullptr;
	ofxGgmlTextChunkCallback onChunk;
	std::function<bool()> shouldCancel;
	bool parseServerSentEvents = false;
	std::string pending;
};

bool cancelCurlRequest(CurlStreamState & state) {
	if (!state.shouldCancel || !state.shouldCancel()) {
		return false;
	}
	if (state.response) {
		state.response->cancelled = true;
		state.response->error = "llama-server request cancelled";
	}
	return true;
}

int progressCurlResponse(
	void * userData,
	curl_off_t,
	curl_off_t,
	curl_off_t,
	curl_off_t) {
	auto * state = static_cast<CurlStreamState *>(userData);
	if (!state) {
		return 0;
	}
	return cancelCurlRequest(*state) ? 1 : 0;
}

std::size_t writeCurlResponse(
	char * data,
	std::size_t size,
	std::size_t count,
	void * userData) {
	const std::size_t bytes = size * count;
	auto * state = static_cast<CurlStreamState *>(userData);
	if (!state || !state->response || !data) {
		return 0;
	}
	if (cancelCurlRequest(*state)) {
		return 0;
	}
	if (!state->response->started) {
		state->response->started = true;
	}
	if (!state->parseServerSentEvents) {
		state->response->body.append(data, bytes);
		return bytes;
	}
	state->pending.append(data, bytes);
	while (true) {
		const std::size_t newline = state->pending.find('\n');
		if (newline == std::string::npos) {
			break;
		}
		std::string line = state->pending.substr(0, newline);
		state->pending.erase(0, newline + 1);
		if (!line.empty() && line.back() == '\r') {
			line.pop_back();
		}
		if (!processServerSentEventLine(line, *state->response, state->onChunk)) {
			return 0;
		}
	}
	return bytes;
}

ofxGgmlTextServerResponse runCurlRequest(
	const ofxGgmlTextServerRequest & request) {
	ofxGgmlTextServerResponse result;
	CURL * curl = curl_easy_init();
	if (!curl) {
		result.error = "curl_easy_init failed";
		return result;
	}

	struct curl_slist * headers = nullptr;
	const std::string acceptHeader = request.stream
		? "Accept: text/event-stream"
		: "Accept: application/json";
	const std::string contentTypeHeader = "Content-Type: " + request.contentType;
	headers = curl_slist_append(headers, acceptHeader.c_str());
	headers = curl_slist_append(headers, contentTypeHeader.c_str());

	CurlStreamState state;
	state.response = &result;
	state.parseServerSentEvents = request.stream;
	state.shouldCancel = request.shouldCancel;
	if (request.stream) {
		state.onChunk = request.onChunk;
	}

	curl_easy_setopt(curl, CURLOPT_URL, request.url.c_str());
	curl_easy_setopt(curl, CURLOPT_POST, 1L);
	curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
	curl_easy_setopt(curl, CURLOPT_POSTFIELDS, request.body.c_str());
	curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, static_cast<long>(request.body.size()));
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCurlResponse);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, &state);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT, static_cast<long>(request.timeoutSeconds));
	curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
	curl_easy_setopt(curl, CURLOPT_USERAGENT, "ofxGgml/llama-server");
	curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
	curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, progressCurlResponse);
	curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &state);

	const CURLcode code = curl_easy_perform(curl);
	long status = 0;
	curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
	result.status = static_cast<int>(status);
	result.started = true;

	if (code != CURLE_OK && !result.cancelled) {
		result.error = curl_easy_strerror(code);
	}
	if (request.stream && !state.pending.empty() && !result.cancelled) {
		processServerSentEventLine(state.pending, result, request.onChunk);
	}

	curl_slist_free_all(headers);
	curl_easy_cleanup(curl);
	return result;
}
#endif

} // namespace

ofxGgmlLlamaServerTextBackend::ofxGgmlLlamaServerTextBackend(
	std::string serverUrl,
	ofxGgmlTextServerRunner runner,
	std::string displayName)
	: serverUrl(std::move(serverUrl))
	, requestRunner(runner ? std::move(runner) : ofxGgmlLlamaServerTextBackend::runRequest)
	, displayName(std::move(displayName)) {
}

void ofxGgmlLlamaServerTextBackend::setServerUrl(std::string serverUrl) {
	this->serverUrl = std::move(serverUrl);
}

const std::string & ofxGgmlLlamaServerTextBackend::getServerUrl() const {
	return serverUrl;
}

void ofxGgmlLlamaServerTextBackend::setRequestRunner(
	ofxGgmlTextServerRunner runner) {
	requestRunner = runner ? std::move(runner) : ofxGgmlLlamaServerTextBackend::runRequest;
}

bool ofxGgmlLlamaServerTextBackend::hasRequestRunner() const {
	return static_cast<bool>(requestRunner);
}

std::string ofxGgmlLlamaServerTextBackend::getBackendName() const {
	return displayName.empty() ? "llama-server" : displayName;
}

ofxGgmlTextResult ofxGgmlLlamaServerTextBackend::generate(
	const ofxGgmlTextRequest & request,
	ofxGgmlTextChunkCallback onChunk) const {
	ofxGgmlTextResult result;
	result.backendName = getBackendName();

	const std::string prompt = composePrompt(request);
	if (prompt.empty()) {
		result.error = "prompt is empty";
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
		prompt,
		request.settings.serverModel);
	serverRequest.stream = request.settings.stream;
	ReasoningStreamFilter streamFilter;
	bool streamCallbackCancelled = false;
	if (onChunk && request.settings.stream) {
		serverRequest.onChunk = [&streamFilter, onChunk, &streamCallbackCancelled](
			const std::string & chunk) {
			if (chunk.empty()) {
				const bool keepGoing = onChunk(std::string());
				if (!keepGoing) {
					streamCallbackCancelled = true;
				}
				return keepGoing;
			}
			const std::string visible = streamFilter.push(chunk);
			if (visible.empty()) {
				return true;
			}
			const bool keepGoing = onChunk(visible);
			if (!keepGoing) {
				streamCallbackCancelled = true;
			}
			return keepGoing;
		};
	} else {
		serverRequest.onChunk = onChunk;
	}
	if (serverRequest.onChunk) {
		serverRequest.shouldCancel = [&serverRequest]() {
			return !serverRequest.onChunk(std::string());
		};
	}
	const ofxGgmlTextServerResponse response = requestRunner(serverRequest);
	if (onChunk && request.settings.stream && !streamCallbackCancelled) {
		const std::string tail = streamFilter.finish();
		if (!tail.empty() && !onChunk(tail)) {
			streamCallbackCancelled = true;
		}
	}
	result.elapsedMs = std::chrono::duration<float, std::milli>(
		std::chrono::steady_clock::now() - started).count();
	result.rawOutput = response.body;
	result.metadata.push_back({ "serverUrl", requestUrl });
	if (!request.settings.serverModel.empty()) {
		result.metadata.push_back({ "serverModel", request.settings.serverModel });
	}

	if (!response.started) {
		result.error = response.error.empty()
			? "llama-server request did not start"
			: response.error;
		result.error += " (" + requestUrl + ")";
		return result;
	}
	if (response.cancelled) {
		result.text = response.text;
		result.error = response.error.empty()
			? "llama-server request cancelled"
			: response.error;
		return result;
	}
	if (streamCallbackCancelled) {
		result.text = sanitizeModelVisibleText(response.text);
		result.error = "llama-server request cancelled";
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
		result.error = "llama-server request failed with HTTP " +
			std::to_string(response.status) + " at " + requestUrl;
		if (!response.error.empty()) {
			result.error += ": " + response.error;
		} else if (!response.body.empty()) {
			result.error += ": " + response.body;
		}
		return result;
	}

	result.text = request.settings.stream
		? response.text
		: extractTextFromResponse(response.body);
	result.text = sanitizeModelVisibleText(result.text);
	if (result.text.empty()) {
		result.error = "llama-server returned empty output";
		return result;
	}
	result.success = true;
	result.finishReason = "stop";
	if (onChunk && !request.settings.stream) {
		onChunk(result.text);
	}
	return result;
}

std::string ofxGgmlLlamaServerTextBackend::normalizeServerUrl(
	const std::string & serverUrl) {
	std::string normalized = trimCopy(serverUrl);
	if (normalized.empty()) {
		normalized = "http://127.0.0.1:8080";
	}
	if (endsWith(normalized, "/v1/chat/completions") ||
		endsWith(normalized, "/chat/completions")) {
		return normalized;
	}
	normalized = stripTrailingSlash(normalized);
	if (endsWith(normalized, "/v1")) {
		return normalized + "/chat/completions";
	}
	return normalized + "/v1/chat/completions";
}

std::string ofxGgmlLlamaServerTextBackend::composePrompt(
	const ofxGgmlTextRequest & request) {
	if (!request.prompt.empty()) {
		return request.prompt;
	}
	std::ostringstream prompt;
	if (!request.systemPrompt.empty()) {
		prompt << request.systemPrompt << "\n";
	}
	for (const auto & message : request.messages) {
		if (!message.content.empty()) {
			prompt << message.content << "\n";
		}
	}
	return trimCopy(prompt.str());
}

std::string ofxGgmlLlamaServerTextBackend::buildRequestBody(
	const ofxGgmlTextRequest & request,
	const std::string & prompt,
	const std::string & serverModel) {
	std::ostringstream body;
	body << "{";
	if (!serverModel.empty()) {
		body << "\"model\":\"" << escapeJson(serverModel) << "\",";
	}
	body << "\"messages\":[";
	bool needsComma = false;
	auto appendMessage = [&](const std::string & role, const std::string & content) {
		if (content.empty()) {
			return;
		}
		if (needsComma) {
			body << ",";
		}
		body << "{\"role\":\"" << role << "\",\"content\":\"" <<
			escapeJson(content) << "\"}";
		needsComma = true;
	};
	appendMessage("system", request.systemPrompt);
	if (!request.messages.empty()) {
		for (const auto & message : request.messages) {
			appendMessage(roleLabel(message.role), message.content);
		}
	} else {
		appendMessage("user", prompt);
	}
	body << "],";
	body << "\"max_tokens\":" << std::max(1, request.settings.maxTokens) << ",";
	body << "\"temperature\":" << std::max(0.0f, request.settings.temperature) << ",";
	body << "\"top_p\":" << std::clamp(request.settings.topP, 0.0f, 1.0f) << ",";
	body << "\"stream\":" << (request.settings.stream ? "true" : "false") << ",";
	body << "\"chat_template_kwargs\":{\"enable_thinking\":false}";
	if (request.settings.topK > 0) {
		body << ",\"top_k\":" << request.settings.topK;
	}
	if (request.settings.seed >= 0) {
		body << ",\"seed\":" << request.settings.seed;
	}
	if (!request.settings.stopSequences.empty()) {
		body << ",\"stop\":[";
		for (std::size_t i = 0; i < request.settings.stopSequences.size(); ++i) {
			if (i > 0) {
				body << ",";
			}
			body << "\"" << escapeJson(request.settings.stopSequences[i]) << "\"";
		}
		body << "]";
	}
	body << "}";
	return body.str();
}

std::string ofxGgmlLlamaServerTextBackend::extractTextFromResponse(
	const std::string & responseBody) {
	for (const std::string & key : { "content", "text", "response" }) {
		const std::string value = extractJsonStringField(responseBody, key);
		if (!trimCopy(value).empty()) {
			return value;
		}
	}
	return {};
}

ofxGgmlTextServerResponse ofxGgmlLlamaServerTextBackend::runRequest(
	const ofxGgmlTextServerRequest & request) {
	ofxGgmlTextServerResponse result;
	if (request.url.empty()) {
		result.error = "server URL is empty";
		return result;
	}
#if defined(OFXGGML_HAS_OF_HTTP_RUNTIME)
#if defined(OFXGGML_HAS_CURL_HTTP_RUNTIME)
	if (request.stream) {
		return runCurlRequest(request);
	}
#else
	if (request.stream) {
		result.error = "streaming llama-server requests require curl runtime";
		return result;
	}
#endif
	ofHttpRequest httpRequest(request.url, "llama-server-text");
	httpRequest.method = ofHttpRequest::POST;
	httpRequest.body = request.body;
	httpRequest.contentType = request.contentType;
	httpRequest.headers["Accept"] = "application/json";
	httpRequest.headers["Content-Type"] = request.contentType;
	httpRequest.timeoutSeconds = request.timeoutSeconds;

	ofURLFileLoader loader;
	const ofHttpResponse response = loader.handleRequest(httpRequest);
	result.started = true;
	result.status = response.status;
	result.body = response.data.getText();
	result.error = response.error;
	return result;
#else
	result.error = "llama-server requests require openFrameworks HTTP runtime";
	return result;
#endif
}
