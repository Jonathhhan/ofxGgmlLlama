#pragma once

#include <functional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

struct ofxGgmlTestCase {
	std::string name;
	std::function<void()> run;
};

inline std::vector<ofxGgmlTestCase> & ofxGgmlTests() {
	static std::vector<ofxGgmlTestCase> tests;
	return tests;
}

struct ofxGgmlRegisterTest {
	ofxGgmlRegisterTest(std::string name, std::function<void()> run) {
		ofxGgmlTests().push_back({ std::move(name), std::move(run) });
	}
};

#define OFXGGML_TEST(name) static void name(); static ofxGgmlRegisterTest register_##name(#name, name); static void name()
#define OFXGGML_REQUIRE(expr) do { if (!(expr)) throw std::runtime_error("require failed: " #expr); } while(false)
