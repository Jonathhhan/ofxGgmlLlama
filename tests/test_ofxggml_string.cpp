#include "test_harness.h"
#include "../src/ofxGgmlString.h"

#include <string>

OFXGGML_TEST(string_trim_copy) {
    OFXGGML_REQUIRE(ofxGgmlString::trimCopy("") == "");
    OFXGGML_REQUIRE(ofxGgmlString::trimCopy("hello") == "hello");
    OFXGGML_REQUIRE(ofxGgmlString::trimCopy("  hello  ") == "hello");
    OFXGGML_REQUIRE(ofxGgmlString::trimCopy("\t\nhello\t\n") == "hello");
    OFXGGML_REQUIRE(ofxGgmlString::trimCopy("  hello world  ") == "hello world");
}

OFXGGML_TEST(string_ends_with) {
    OFXGGML_REQUIRE(ofxGgmlString::endsWith("hello.txt", ".txt"));
    OFXGGML_REQUIRE(!ofxGgmlString::endsWith("hello.txt", ".pdf"));
    OFXGGML_REQUIRE(!ofxGgmlString::endsWith("hi", "hello.txt"));
    OFXGGML_REQUIRE(ofxGgmlString::endsWith("", ""));
}

OFXGGML_TEST(string_starts_with) {
    OFXGGML_REQUIRE(ofxGgmlString::startsWith("http://localhost", "http://"));
    OFXGGML_REQUIRE(!ofxGgmlString::startsWith("http://localhost", "https://"));
    OFXGGML_REQUIRE(!ofxGgmlString::startsWith("hi", "hello"));
    OFXGGML_REQUIRE(ofxGgmlString::startsWith("", ""));
}

OFXGGML_TEST(string_strip_trailing_slash) {
    OFXGGML_REQUIRE(ofxGgmlString::stripTrailingSlash("http://localhost/") == "http://localhost");
    OFXGGML_REQUIRE(ofxGgmlString::stripTrailingSlash("http://localhost//") == "http://localhost");
    OFXGGML_REQUIRE(ofxGgmlString::stripTrailingSlash("http://localhost") == "http://localhost");
    OFXGGML_REQUIRE(ofxGgmlString::stripTrailingSlash("") == "");
}

OFXGGML_TEST(string_escape_json) {
    OFXGGML_REQUIRE(ofxGgmlString::escapeJson("hello") == "hello");
    OFXGGML_REQUIRE(
        ofxGgmlString::escapeJson("hello\"world") == "hello\\\"world");
    OFXGGML_REQUIRE(
        ofxGgmlString::escapeJson("hello\\world") == "hello\\\\world");
    OFXGGML_REQUIRE(
        ofxGgmlString::escapeJson("line1\nline2") == "line1\\nline2");
    OFXGGML_REQUIRE(
        ofxGgmlString::escapeJson("tab\there") == "tab\\there");
}

OFXGGML_TEST(string_erase_delimited_block) {
    OFXGGML_REQUIRE(
        ofxGgmlString::eraseDelimitedBlock(
            "hello<tag>world</tag>bye", "<tag>", "</tag>") == "hellobye");
    OFXGGML_REQUIRE(
        ofxGgmlString::eraseDelimitedBlock(
            "no markers here", "<tag>", "</tag>") == "no markers here");
    OFXGGML_REQUIRE(
        ofxGgmlString::eraseDelimitedBlock(
            "a<x>b<x>c</x>end", "<x>", "</x>") == "aend");
}

OFXGGML_TEST(string_strip_reasoning_blocks) {
    OFXGGML_REQUIRE(
        ofxGgmlString::stripReasoningBlocks("<think>think</think>hello") == "hello");
    OFXGGML_REQUIRE(
        ofxGgmlString::stripReasoningBlocks("<thinking>think</thinking>hello") == "hello");
    OFXGGML_REQUIRE(
        ofxGgmlString::stripReasoningBlocks("[Start thinking]think[End thinking]hello") == "hello");
    OFXGGML_REQUIRE(
        ofxGgmlString::stripReasoningBlocks("[Thinking]think[/Thinking]hello") == "hello");
    OFXGGML_REQUIRE(
        ofxGgmlString::stripReasoningBlocks("hello") == "hello");
}
