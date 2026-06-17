cmake_minimum_required(VERSION 3.18)
project(ofxGgmlLlama_tests CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED OFX_GGML_CORE_ROOT)
	if(DEFINED ENV{OFX_GGML_CORE_ROOT})
		set(OFX_GGML_CORE_ROOT "$ENV{OFX_GGML_CORE_ROOT}")
	else()
		set(OFX_GGML_CORE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../ofxGgmlCore")
	endif()
endif()

if(NOT EXISTS "${OFX_GGML_CORE_ROOT}/src")
	message(FATAL_ERROR "ofxGgmlCore source directory was not found. Set OFX_GGML_CORE_ROOT to the ofxGgmlCore addon root.")
endif()

add_executable(ofxGgmlLlama_tests
	test_main.cpp
	test_umbrella.cpp
	test_llama_cli_text.cpp
	test_llama_server_text.cpp
	test_llama_server_embedding.cpp
	test_codex_local_config.cpp
	test_embedding_bridge.cpp
	test_ofxggml_string.cpp
	../src/inference/ofxGgmlLlamaCliTextBackend.cpp
	../src/inference/ofxGgmlLlamaServerTextBackend.cpp
	../src/inference/ofxGgmlLlamaServerEmbeddingBackend.cpp
	../src/codex/ofxGgmlLlamaCodexLocal.cpp
	../src/inference/ofxGgmlTextGeneration.cpp
	../src/inference/ofxGgmlEmbedding.cpp)

target_include_directories(ofxGgmlLlama_tests PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}/../src
	${OFX_GGML_CORE_ROOT}/src)

enable_testing()
add_test(NAME ofxGgmlLlama_tests COMMAND ofxGgmlLlama_tests)
