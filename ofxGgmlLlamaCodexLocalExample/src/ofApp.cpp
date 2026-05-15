#include "ofApp.h"

#include <cstdlib>
#include <sstream>

namespace {
constexpr const char * LogModule = "ofxGgmlLlamaCodexLocalExample";
}

std::string ofApp::getEnvOrDefault(const std::string & name, const std::string & fallback) const {
	const char * value = std::getenv(name.c_str());
	if (value == nullptr || std::string(value).empty()) {
		return fallback;
	}
	return value;
}

void ofApp::appendWrapped(const std::string & text, std::size_t maxChars) {
	if (text.size() <= maxChars) {
		lines.push_back(text);
		return;
	}

	std::istringstream words(text);
	std::string word;
	std::string line;
	while (words >> word) {
		if (!line.empty() && line.size() + word.size() + 1 > maxChars) {
			lines.push_back(line);
			line.clear();
		}
		if (!line.empty()) {
			line += " ";
		}
		line += word;
	}
	if (!line.empty()) {
		lines.push_back(line);
	}
}

void ofApp::setup() {
	ofSetWindowTitle("ofxGgmlLlama Codex Local Example");
	ofBackground(16);

	baseUrl = getEnvOrDefault("OFXGGML_CODEX_BASE_URL", "http://127.0.0.1:8001/v1");
	modelAlias = getEnvOrDefault("OFXGGML_CODEX_MODEL", "unsloth/GLM-4.7-Flash");
	rebuildLines();

	for (const auto & line : lines) {
		ofLogNotice(LogModule) << line;
	}
}

void ofApp::draw() {
	ofBackground(16);
	ofSetColor(238);
	const int left = 32;
	int y = 44;
	for (const auto & line : lines) {
		ofDrawBitmapString(line, left, y);
		y += 22;
	}
}

void ofApp::keyPressed(int key) {
	if (key == 'r' || key == 'R') {
		baseUrl = getEnvOrDefault("OFXGGML_CODEX_BASE_URL", "http://127.0.0.1:8001/v1");
		modelAlias = getEnvOrDefault("OFXGGML_CODEX_MODEL", "unsloth/GLM-4.7-Flash");
		rebuildLines();
		ofLogNotice(LogModule) << "refreshed local Codex endpoint display";
	}
}

void ofApp::rebuildLines() {
	lines.clear();
	lines.push_back("ofxGgmlLlama Codex Local Example");
	lines.push_back("");
	lines.push_back("Run local LLMs with OpenAI Codex through llama.cpp llama-server.");
	lines.push_back("Runtime owner: ofxGgmlLlama");
	lines.push_back("Endpoint consumer: Codex or another OpenAI-compatible client");
	lines.push_back("");
	lines.push_back("Endpoint");
	lines.push_back("  base_url: " + baseUrl);
	lines.push_back("  model:    " + modelAlias);
	lines.push_back("");
	lines.push_back("Codex config.toml sketch");
	lines.push_back("[model_providers.llama_cpp]");
	lines.push_back("name = \"llama.cpp local\"");
	lines.push_back("base_url = \"" + baseUrl + "\"");
	lines.push_back("wire_api = \"responses\"");
	lines.push_back("stream_idle_timeout_ms = 10000000");
	lines.push_back("");
	lines.push_back("[profiles.ofxggml_local]");
	lines.push_back("model = \"" + modelAlias + "\"");
	lines.push_back("model_provider = \"llama_cpp\"");
	lines.push_back("");
	lines.push_back("Llama lane setup");
	appendWrapped("1. Build the runtime: scripts\\build-llama-server.bat -Cuda", 96);
	appendWrapped("2. Download or place a GGUF model under addons\\models or ofxGgmlLlama\\models.", 96);
	appendWrapped("3. Start llama-server: scripts\\start-llama-server.bat -ModelPath C:\\path\\to\\model.gguf -Port 8001 -GpuLayers 999 -ContextSize 131072", 96);
	appendWrapped("4. Verify with scripts\\doctor-llama.bat and scripts\\run-llama-runtime-smoke.bat -Backend cuda -Json -SummaryOnly.", 96);
	lines.push_back("");
	lines.push_back("Codex readiness");
	appendWrapped("Copy the provider/profile shape into %USERPROFILE%\\.codex\\config.toml after checking it against your installed Codex version.", 96);
	appendWrapped("From ofxGgmlCore, run scripts\\plan-local-codex.bat -Endpoint " + baseUrl + " -Json -SummaryOnly.", 96);
	lines.push_back("");
	lines.push_back("Environment overrides");
	lines.push_back("  OFXGGML_CODEX_BASE_URL");
	lines.push_back("  OFXGGML_CODEX_MODEL");
	lines.push_back("");
	lines.push_back("Press R to reload environment values.");
}
