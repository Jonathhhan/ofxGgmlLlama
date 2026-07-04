#pragma once

#include <string>

// Centralized default constants for ofxGgmlLlama backends and examples.
// Shared values live here so they can be updated in one place.

namespace ofxGgmlLlamaDefaults {

// ---- Server endpoint defaults ----

constexpr const char * kDefaultTextServerUrl = "http://127.0.0.1:8080";
constexpr const char * kDefaultEmbeddingServerUrl = "http://127.0.0.1:8081";
constexpr const char * kDefaultCodexServerUrl = "http://127.0.0.1:8001";

inline std::string defaultTextServerUrl() { return kDefaultTextServerUrl; }
inline std::string defaultEmbeddingServerUrl() { return kDefaultEmbeddingServerUrl; }
inline std::string defaultCodexServerUrl() { return kDefaultCodexServerUrl; }

// ---- HTTP request defaults ----

constexpr int kDefaultTimeoutSeconds = 180;

// ---- Generation defaults ----

constexpr int kDefaultMaxTokens = 256;
constexpr float kDefaultTemperature = 0.8f;
constexpr float kDefaultTopP = 0.95f;
constexpr int kDefaultTopK = 40;
constexpr float kDefaultRepeatPenalty = 1.05f;
constexpr int kDefaultContextSize = 2048;
constexpr int kDefaultBatchSize = 512;
constexpr int kDefaultGpuLayers = -1;
constexpr int kDefaultThreads = 0;
constexpr int kDefaultSeed = -1;

// ---- Codex local server defaults ----

constexpr int kDefaultCodexGpuLayers = 999;
constexpr int kDefaultCodexContextSize = 65536;
constexpr int kDefaultCodexPort = 8001;
constexpr int kDefaultCodexThreads = 0;
constexpr int kDefaultCodexBatchSize = 1024;
constexpr int kDefaultCodexUbatchSize = 256;
constexpr int kDefaultCodexCacheReuse = 256;
constexpr float kDefaultCodexTemperature = 0.2f;
constexpr float kDefaultCodexTopP = 0.85f;
constexpr float kDefaultCodexMinP = 0.03f;

// ---- Embedding defaults ----

constexpr int kDefaultEmbeddingTimeoutSeconds = 180;

// ---- Utility ----

inline std::string resolveDefaultServerUrl(bool embedding) {
    return embedding ? defaultEmbeddingServerUrl() : defaultTextServerUrl();
}

} // namespace ofxGgmlLlamaDefaults