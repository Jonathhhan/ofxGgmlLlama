#pragma once

#include "ofxGgmlText.h"
#include "ofxGgmlEmbedding.h"
#include "inference/ofxGgmlLlamaCliTextBackend.h"
#include "inference/ofxGgmlLlamaServerEmbeddingBackend.h"
#include "inference/ofxGgmlLlamaServerTextBackend.h"

// Companion umbrella for llama.cpp text, chat, and embedding workflows.
// Stable request/result APIs currently live in ofxGgmlCore; transitional
// llama adapter headers are included explicitly until they move here.
