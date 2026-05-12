#include "test_harness.h"
#include "ofxGgmlLlama.h"

#include <string>

OFXGGML_TEST(llama_umbrella_exposes_version_metadata) {
	OFXGGML_REQUIRE(OFXGGML_LLAMA_VERSION_MAJOR == 1);
	OFXGGML_REQUIRE(OFXGGML_LLAMA_VERSION_MINOR == 0);
	OFXGGML_REQUIRE(OFXGGML_LLAMA_VERSION_PATCH == 1);
	OFXGGML_REQUIRE(std::string(OFXGGML_LLAMA_VERSION_STRING) == "1.0.1");
	OFXGGML_REQUIRE(std::string(ofxGgmlLlamaGetVersionString()) == "1.0.1");
}

OFXGGML_TEST(llama_umbrella_exposes_core_request_types) {
	ofxGgmlTextRequest request;
	request.prompt = "hello";
	OFXGGML_REQUIRE(request.prompt == "hello");

	ofxGgmlEmbeddingRequest embedding;
	embedding.input = "openFrameworks";
	OFXGGML_REQUIRE(!embedding.input.empty());
}

OFXGGML_TEST(llama_umbrella_exposes_adapter_types) {
	OFXGGML_REQUIRE(sizeof(ofxGgmlLlamaCliTextBackend) > 0);
	OFXGGML_REQUIRE(sizeof(ofxGgmlLlamaServerTextBackend) > 0);
	OFXGGML_REQUIRE(sizeof(ofxGgmlLlamaServerEmbeddingBackend) > 0);
}
