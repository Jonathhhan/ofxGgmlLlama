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
			<< "[mcp_servers.ofxggml_codex_threads]\n"
			<< "command = \"old-node\"\n"
			<< "args = [\"old.js\"]\n\n"
			<< "[mcp_servers.ofxggml_codex_threads.env]\n"
			<< "OFXGGML_CODEX_MODEL = \"local/old-model\"\n\n"
			<< "[profiles.keep_me]\n"
			<< "model = \"remote/model\"\n";
	}

	ofxGgmlLlamaCodexProviderConfig config;
	config.modelAlias = "local/new-model";
	config.threadMcpServerCwd = "C:/of/addons/ofxGgmlLlama";
	config.writeAgentSettings = false;
	config.writeAgentRoleFiles = false;
	const auto result = ofxGgmlLlamaCodexLocal::writeCodexConfig(configPath.string(), config);

	const auto updated = readFile(configPath);
	OFXGGML_REQUIRE(result.ok);
	OFXGGML_REQUIRE(updated.find("model = \"local/new-model\"") != std::string::npos);
	OFXGGML_REQUIRE(updated.find("[profiles.ofxggml_local]") != std::string::npos);
	OFXGGML_REQUIRE(updated.find("[mcp_servers.ofxggml_codex_threads]") != std::string::npos);
	OFXGGML_REQUIRE(updated.find("[mcp_servers.ofxggml_codex_threads.env]") != std::string::npos);
	OFXGGML_REQUIRE(updated.find("old-node") == std::string::npos);
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
	config.agentMaxConcurrentThreadsPerSession = 0;
	config.agentMaxDepth = 0;
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

OFXGGML_TEST(codex_config_omits_agent_max_threads_for_auto) {
	ofxGgmlLlamaCodexProviderConfig config;
	config.modelAlias = "local/new-selected-model";
	config.agentMaxConcurrentThreadsPerSession = 0;
	config.agentMaxDepth = 0;

	const auto snippet = ofxGgmlLlamaCodexLocal::buildCodexConfigSnippet(config);

	OFXGGML_REQUIRE(snippet.find("[agents]") == std::string::npos);
	OFXGGML_REQUIRE(snippet.find("max_threads") == std::string::npos);
	OFXGGML_REQUIRE(snippet.find("max_depth") == std::string::npos);
}

OFXGGML_TEST(codex_config_writes_positive_agent_overrides) {
	ofxGgmlLlamaCodexProviderConfig config;
	config.modelAlias = "local/new-selected-model";
	config.agentMaxConcurrentThreadsPerSession = 2;
	config.agentMaxDepth = 3;

	const auto snippet = ofxGgmlLlamaCodexLocal::buildCodexConfigSnippet(config);

	OFXGGML_REQUIRE(snippet.find("[agents]") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("max_threads = 2") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("max_depth = 3") != std::string::npos);
}

OFXGGML_TEST(codex_config_writes_thread_mcp_server_when_root_is_set) {
	ofxGgmlLlamaCodexProviderConfig config;
	config.modelAlias = "local/new-selected-model";
	config.webSearch = "live";
	config.threadMcpServerCwd = "C:/of/addons/ofxGgmlLlama";

	const auto snippet = ofxGgmlLlamaCodexLocal::buildCodexConfigSnippet(config);

	OFXGGML_REQUIRE(snippet.find("web_search = \"live\"") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("[mcp_servers.ofxggml_codex_threads]") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("command = \"node\"") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("args = [\"scripts/mcp/codex-thread-server.js\"]") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("cwd = \"C:/of/addons/ofxGgmlLlama\"") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("enabled_tools = [\"spawn_codex_thread\"]") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("default_tools_approval_mode = \"prompt\"") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("[mcp_servers.ofxggml_codex_threads.env]") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("OFXGGML_CODEX_MODEL = \"local/new-selected-model\"") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("OFXGGML_CODEX_MODEL_PROVIDER = \"llama_cpp\"") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("OFXGGML_CODEX_THREAD_SPAWN_TIMEOUT_MS = \"300000\"") != std::string::npos);
}

OFXGGML_TEST(codex_config_snippet_includes_self_contained_provider) {
	ofxGgmlLlamaCodexProviderConfig config;
	config.modelAlias = "local/new-selected-model";
	config.baseUrl = "http://127.0.0.1:9001/v1";
	config.writeAgentSettings = false;
	config.writeAgentRoleFiles = false;

	const auto snippet = ofxGgmlLlamaCodexLocal::buildCodexConfigSnippet(config);

	OFXGGML_REQUIRE(snippet.find("[model_providers.llama_cpp]") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("base_url = \"http://127.0.0.1:9001/v1\"") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("wire_api = \"responses\"") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("stream_idle_timeout_ms = 10000000") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("[profiles.ofxggml_local]") != std::string::npos);
	OFXGGML_REQUIRE(snippet.find("model = \"local/new-selected-model\"") != std::string::npos);
}

OFXGGML_TEST(codex_launch_command_includes_local_provider_overrides) {
	ofxGgmlLlamaCodexProviderConfig config;
	config.providerId = "llama_cpp";
	config.providerName = "llama.cpp local";
	config.baseUrl = "http://127.0.0.1:9001/v1";
	config.modelContextWindow = 40960;
	config.modelAutoCompactTokenLimit = 30000;
	config.toolOutputTokenLimit = 5000;
	config.webSearch = "live";
	config.agentMaxConcurrentThreadsPerSession = 2;
	config.agentMaxDepth = 3;

	ofxGgmlLlamaCodexLaunchCommandSettings settings;
	settings.executable = "C:\\Program Files\\Codex\\codex.exe";
	settings.profile = "ofxggml_local";
	settings.model = "local/new-selected-model";
	settings.sandbox = "workspace-write";
	settings.provider = config;
	settings.includeLocalProviderToolGuards = true;
	settings.includeLocalProviderOverrides = true;

	const auto command = ofxGgmlLlamaCodexLocal::buildLaunchCommand(settings);

	OFXGGML_REQUIRE(command.find("'C:\\Program Files\\Codex\\codex.exe'") != std::string::npos);
	OFXGGML_REQUIRE(command.find("--disable apps") != std::string::npos);
	OFXGGML_REQUIRE(command.find("'web_search=\"live\"'") != std::string::npos);
	OFXGGML_REQUIRE(command.find("-c model_provider=llama_cpp") != std::string::npos);
	OFXGGML_REQUIRE(command.find("'model_providers.llama_cpp.name=\"llama.cpp local\"'") != std::string::npos);
	OFXGGML_REQUIRE(command.find("'model_providers.llama_cpp.base_url=\"http://127.0.0.1:9001/v1\"'") != std::string::npos);
	OFXGGML_REQUIRE(command.find("-c agents.max_threads=2") != std::string::npos);
	OFXGGML_REQUIRE(command.find("-c agents.max_depth=3") != std::string::npos);
	OFXGGML_REQUIRE(command.find("--sandbox workspace-write") != std::string::npos);
	OFXGGML_REQUIRE(command.find("--model local/new-selected-model") != std::string::npos);
}

OFXGGML_TEST(codex_launch_command_keeps_hybrid_main_model_remote) {
	ofxGgmlLlamaCodexProviderConfig config;
	config.providerId = "llama_cpp";
	config.providerName = "llama.cpp local";
	config.modelAlias = "local/local-agent-model";
	config.agentMaxConcurrentThreadsPerSession = 1;

	ofxGgmlLlamaCodexLaunchCommandSettings settings;
	settings.profile = "ofxggml_local";
	settings.model = "gpt-5";
	settings.provider = config;
	settings.includeLocalProviderToolGuards = true;
	settings.includeLocalProviderOverrides = false;

	const auto command = ofxGgmlLlamaCodexLocal::buildLaunchCommand(settings);

	OFXGGML_REQUIRE(command.find("codex --no-alt-screen -p ofxggml_local") == 0);
	OFXGGML_REQUIRE(command.find("--disable apps") != std::string::npos);
	OFXGGML_REQUIRE(command.find("-c model_provider=llama_cpp") == std::string::npos);
	OFXGGML_REQUIRE(command.find("model_providers.llama_cpp.base_url") == std::string::npos);
	OFXGGML_REQUIRE(command.find("-c agents.max_threads=1") != std::string::npos);
	OFXGGML_REQUIRE(command.find("--model gpt-5") != std::string::npos);
	OFXGGML_REQUIRE(command.find("--model local/local-agent-model") == std::string::npos);
}

OFXGGML_TEST(codex_launch_command_quotes_powershell_single_quotes) {
	const auto quoted = ofxGgmlLlamaCodexLocal::quotePowerShellArgument(
		"model_providers.llama_cpp.name=\"Jon's llama\"");

	OFXGGML_REQUIRE(quoted == "'model_providers.llama_cpp.name=\"Jon''s llama\"'");
}
