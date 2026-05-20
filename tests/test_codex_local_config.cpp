#include "test_harness.h"
#include "../src/codex/ofxGgmlLlamaCodexLocal.h"

#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace {
std::string readFile(const std::filesystem::path & path) {
	std::ifstream input(path, std::ios::binary);
	std::ostringstream output;
	output << input.rdbuf();
	return output.str();
}
}

OFXGGML_TEST(codex_config_replaces_stale_model_aliases) {
	const auto root = std::filesystem::temp_directory_path() /
		"ofxGgmlLlama-codex-config-test";
	std::filesystem::remove_all(root);
	std::filesystem::create_directories(root);
	const auto configPath = root / "config.toml";
	{
		std::ofstream output(configPath, std::ios::binary);
		output
			<< "model = \"local/old-model\"\n"
			<< "model_provider = \"llama_cpp\"\n\n"
			<< "[model_providers.llama_cpp]\n"
			<< "name = \"old provider\"\n"
			<< "base_url = \"http://127.0.0.1:8001/v1\"\n\n"
			<< "[profiles.ofxggml_local]\n"
			<< "model = \"local/old-model\"\n"
			<< "model_provider = \"llama_cpp\"\n\n"
			<< "[profiles.keep_me]\n"
			<< "model = \"remote/model\"\n";
	}

	ofxGgmlLlamaCodexProviderConfig config;
	config.modelAlias = "local/new-model";
	config.writeAgentSettings = false;
	config.writeAgentRoleFiles = false;
	const auto result = ofxGgmlLlamaCodexLocal::writeCodexConfig(configPath.string(), config);

	const auto updated = readFile(configPath);
	OFXGGML_REQUIRE(result.ok);
	OFXGGML_REQUIRE(updated.find("model = \"local/new-model\"") != std::string::npos);
	OFXGGML_REQUIRE(updated.find("[profiles.ofxggml_local]") != std::string::npos);
	OFXGGML_REQUIRE(updated.find("[profiles.keep_me]") != std::string::npos);
	OFXGGML_REQUIRE(updated.find("model = \"remote/model\"") != std::string::npos);
	OFXGGML_REQUIRE(updated.find("local/old-model") == std::string::npos);
	std::filesystem::remove_all(root);
}

OFXGGML_TEST(codex_config_writes_self_contained_local_agent_roles) {
	const auto root = std::filesystem::temp_directory_path() /
		"ofxGgmlLlama-codex-agent-config-test";
	std::filesystem::remove_all(root);
	std::filesystem::create_directories(root);
	const auto configPath = root / "config.toml";

	ofxGgmlLlamaCodexProviderConfig config;
	config.modelAlias = "local/new-selected-model";
	config.modelContextWindow = 40960;
	config.modelAutoCompactTokenLimit = 30000;
	config.toolOutputTokenLimit = 5000;
	config.agentMaxConcurrentThreadsPerSession = 1;
	config.agentMaxDepth = 1;
	config.writeAgentSettings = true;
	config.writeAgentRoleFiles = true;
	const auto result = ofxGgmlLlamaCodexLocal::writeCodexConfig(configPath.string(), config);

	const auto workerPath = root / "agents" / "worker.toml";
	const auto explorerPath = root / "agents" / "explorer.toml";
	const auto worker = readFile(workerPath);
	const auto explorer = readFile(explorerPath);
	OFXGGML_REQUIRE(result.ok);
	OFXGGML_REQUIRE(worker.find("name = \"worker\"") != std::string::npos);
	OFXGGML_REQUIRE(worker.find("model = \"local/new-selected-model\"") != std::string::npos);
	OFXGGML_REQUIRE(worker.find("model_provider = \"llama_cpp\"") != std::string::npos);
	OFXGGML_REQUIRE(worker.find("[agents]") == std::string::npos);
	OFXGGML_REQUIRE(worker.find("agent_max_threads") == std::string::npos);
	OFXGGML_REQUIRE(explorer.find("name = \"explorer\"") != std::string::npos);
	OFXGGML_REQUIRE(explorer.find("model = \"local/new-selected-model\"") != std::string::npos);
	OFXGGML_REQUIRE(explorer.find("model_provider = \"llama_cpp\"") != std::string::npos);
	OFXGGML_REQUIRE(explorer.find("sandbox_mode = \"read-only\"") != std::string::npos);
	OFXGGML_REQUIRE(explorer.find("[agents]") == std::string::npos);
	OFXGGML_REQUIRE(explorer.find("agent_max_threads") == std::string::npos);
	std::filesystem::remove_all(root);
}
