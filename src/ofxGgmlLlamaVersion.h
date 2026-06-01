#pragma once

#define OFXGGML_LLAMA_VERSION_MAJOR 1
#define OFXGGML_LLAMA_VERSION_MINOR 0
#define OFXGGML_LLAMA_VERSION_PATCH 2
#define OFXGGML_LLAMA_VERSION_STRING "1.0.2"

inline const char * ofxGgmlLlamaGetVersionString() {
	return OFXGGML_LLAMA_VERSION_STRING;
}
