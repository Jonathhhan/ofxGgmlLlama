#include "ofxGgmlLlama.h"

#include <iostream>
#include <string>

int main() {
	ofxGgmlTextRequest request;
	request.prompt = "hello";
	if (request.prompt != "hello") {
		std::cerr << "text request was not writable\n";
		return 1;
	}

	ofxGgmlEmbeddingRequest embedding;
	embedding.input = "openFrameworks";
	if (embedding.input.empty()) {
		std::cerr << "embedding request was not writable\n";
		return 1;
	}

	return 0;
}
