#pragma once

#include "ofMain.h"
#include "ofxGgmlLlama.h"

#include <cstddef>
#include <string>
#include <vector>

class ofApp : public ofBaseApp {
public:
	void setup() override;
	void draw() override;
	void keyPressed(int key) override;

private:
	std::string getEnvOrDefault(const std::string & name, const std::string & fallback) const;
	void appendWrapped(const std::string & text, std::size_t maxChars);
	void rebuildLines();

	std::string baseUrl;
	std::string modelAlias;
	std::vector<std::string> lines;
};
