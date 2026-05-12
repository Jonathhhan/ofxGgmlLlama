#pragma once

#include "ofxGgmlLlamaVersion.h"
#include "ofxGgmlText.h"
#include "ofxGgmlEmbedding.h"
#include "inference/ofxGgmlLlamaCliTextBackend.h"
#include "inference/ofxGgmlLlamaServerEmbeddingBackend.h"
#include "inference/ofxGgmlLlamaServerTextBackend.h"

// Companion umbrella for llama.cpp text, chat, and embedding workflows.
// Stable request/result APIs live in ofxGgmlCore; llama.cpp adapters live here.
