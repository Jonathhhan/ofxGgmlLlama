#include "test_harness.h"
#include "../src/inference/ofxGgmlEmbedding.h"

#include <cmath>
#include <string>
#include <vector>

OFXGGML_TEST(embedding_bridge_unconfigured_error) {
	ofxGgmlEmbeddingBridgeBackend backend({});

	ofxGgmlEmbeddingRequest request;
	request.input = "hello";

	const auto result = backend.embed(request);

	OFXGGML_REQUIRE(!result);
	OFXGGML_REQUIRE(result.error.find("not configured") != std::string::npos);
	OFXGGML_REQUIRE(result.backendName == "EmbeddingBridge");
}

OFXGGML_TEST(embedding_bridge_configured_callback) {
	ofxGgmlEmbeddingBridgeBackend backend([](const ofxGgmlEmbeddingRequest & request) {
		ofxGgmlEmbeddingResult result;
		result.success = true;
		result.embedding = { 0.1f, 0.2f, 0.3f };
		result.elapsedMs = 5.0f;
		return result;
	});

	ofxGgmlEmbeddingRequest request;
	request.input = "hello";

	const auto result = backend.embed(request);

	OFXGGML_REQUIRE(result);
	OFXGGML_REQUIRE(result.backendName == "EmbeddingBridge");
	OFXGGML_REQUIRE(result.embedding.size() == 3);
	OFXGGML_REQUIRE(result.embedding[0] == 0.1f);
	OFXGGML_REQUIRE(result.embedding[1] == 0.2f);
	OFXGGML_REQUIRE(result.embedding[2] == 0.3f);
	OFXGGML_REQUIRE(result.elapsedMs > 0.0f);
}

OFXGGML_TEST(embedding_bridge_timing) {
	ofxGgmlEmbeddingBridgeBackend backend([](const ofxGgmlEmbeddingRequest & request) {
		ofxGgmlEmbeddingResult result;
		result.success = true;
		result.embedding = { 1.0f };
		result.elapsedMs = 0.0f;
		return result;
	});

	ofxGgmlEmbeddingRequest request;
	request.input = "timing test";

	const auto result = backend.embed(request);

	OFXGGML_REQUIRE(result);
	OFXGGML_REQUIRE(result.elapsedMs > 0.0f);
}

OFXGGML_TEST(embedding_bridge_name_override) {
	ofxGgmlEmbeddingBridgeBackend backend(
		[](const ofxGgmlEmbeddingRequest & request) {
			ofxGgmlEmbeddingResult result;
			result.success = true;
			result.embedding = { 1.0f };
			return result;
		},
		"MyCustomBackend");

	const auto result = backend.embed(ofxGgmlEmbeddingRequest{});

	OFXGGML_REQUIRE(result.backendName == "MyCustomBackend");
}

OFXGGML_TEST(embedding_bridge_set_embed_function) {
	ofxGgmlEmbeddingBridgeBackend backend({});

	OFXGGML_REQUIRE(!backend.isConfigured());

	backend.setEmbedFunction([](const ofxGgmlEmbeddingRequest & request) {
		ofxGgmlEmbeddingResult result;
		result.success = true;
		result.embedding = { 0.5f, 0.5f };
		result.elapsedMs = 1.0f;
		return result;
	});

	OFXGGML_REQUIRE(backend.isConfigured());

	ofxGgmlEmbeddingRequest request;
	request.input = "swapped";

	const auto result = backend.embed(request);

	OFXGGML_REQUIRE(result);
	OFXGGML_REQUIRE(result.embedding.size() == 2);
	OFXGGML_REQUIRE(result.embedding[0] == 0.5f);
}

OFXGGML_TEST(embedding_bridge_callback_returns_error) {
	ofxGgmlEmbeddingBridgeBackend backend([](const ofxGgmlEmbeddingRequest & request) {
		ofxGgmlEmbeddingResult result;
		result.success = false;
		result.error = "callback error";
		return result;
	});

	ofxGgmlEmbeddingRequest request;
	request.input = "error test";

	const auto result = backend.embed(request);

	OFXGGML_REQUIRE(!result);
	OFXGGML_REQUIRE(result.error == "callback error");
}

OFXGGML_TEST(embedding_generator_default_bridge) {
	ofxGgmlEmbeddingGenerator generator;

	ofxGgmlEmbeddingRequest request;
	request.input = "hello";

	const auto result = generator.embed(request);

	OFXGGML_REQUIRE(!result);
	OFXGGML_REQUIRE(result.error.find("not configured") != std::string::npos);
}

OFXGGML_TEST(embedding_generator_with_bridge_backend) {
	ofxGgmlEmbeddingGenerator generator;
	generator.setBackend(
		ofxGgmlEmbeddingGenerator::createEmbeddingBridgeBackend(
			[](const ofxGgmlEmbeddingRequest & request) {
				ofxGgmlEmbeddingResult result;
				result.success = true;
				result.embedding = { 0.9f };
				result.elapsedMs = 2.0f;
				return result;
			},
			"TestBridge"));

	const auto result = generator.embed("test input");

	OFXGGML_REQUIRE(result);
	OFXGGML_REQUIRE(result.backendName == "TestBridge");
	OFXGGML_REQUIRE(result.embedding[0] == 0.9f);
}

OFXGGML_TEST(embedding_utils_dot_product) {
	const std::vector<float> a = { 1.0f, 2.0f, 3.0f };
	const std::vector<float> b = { 4.0f, 5.0f, 6.0f };
	const float dot = ofxGgmlEmbeddingUtils::dotProduct(a, b);
	OFXGGML_REQUIRE(std::abs(dot - 32.0f) < 0.001f);
}

OFXGGML_TEST(embedding_utils_l2_norm) {
	const std::vector<float> v = { 3.0f, 4.0f };
	const float norm = ofxGgmlEmbeddingUtils::l2Norm(v);
	OFXGGML_REQUIRE(std::abs(norm - 5.0f) < 0.001f);
}

OFXGGML_TEST(embedding_utils_cosine_similarity) {
	const std::vector<float> a = { 1.0f, 0.0f };
	const std::vector<float> b = { 1.0f, 0.0f };
	const float sim = ofxGgmlEmbeddingUtils::cosineSimilarity(a, b);
	OFXGGML_REQUIRE(std::abs(sim - 1.0f) < 0.001f);

	const std::vector<float> c = { 0.0f, 1.0f };
	const float ortho = ofxGgmlEmbeddingUtils::cosineSimilarity(a, c);
	OFXGGML_REQUIRE(std::abs(ortho) < 0.001f);
}
