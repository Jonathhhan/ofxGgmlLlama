meta:
	ADDON_NAME = ofxGgmlLlama
	ADDON_DESCRIPTION = Companion addon for llama.cpp text, chat, embedding, and server workflows on top of ofxGgmlCore
	ADDON_AUTHOR = Jonathan Frank
	ADDON_TAGS = "ggml,llama,chat,embedding,local-ai"
	ADDON_URL = https://github.com/Jonathhhan/ofxGgmlLlama

common:
	ADDON_DEPENDENCIES += ofxGgmlCore
	ADDON_INCLUDES = src
	ADDON_INCLUDES += ../ofxGgmlCore/src
	ADDON_SOURCES = src/inference/ofxGgmlLlamaCliTextBackend.cpp
	ADDON_SOURCES += src/inference/ofxGgmlLlamaServerEmbeddingBackend.cpp
	ADDON_SOURCES += src/inference/ofxGgmlLlamaServerTextBackend.cpp
	ADDON_SOURCES_EXCLUDE = build/%
	ADDON_SOURCES_EXCLUDE += libs/llama.cpp/.source/%
	ADDON_SOURCES_EXCLUDE += libs/llama.cpp/build/%
	ADDON_SOURCES_EXCLUDE += libs/llama.cpp/build-cuda/%
	ADDON_SOURCES_EXCLUDE += libs/llama.cpp/build-native/%
	ADDON_INCLUDES_EXCLUDE = build/%
	ADDON_INCLUDES_EXCLUDE += libs/llama.cpp/.source/%
	ADDON_INCLUDES_EXCLUDE += libs/llama.cpp/build/%
	ADDON_INCLUDES_EXCLUDE += libs/llama.cpp/build-cuda/%
	ADDON_INCLUDES_EXCLUDE += libs/llama.cpp/build-native/%
