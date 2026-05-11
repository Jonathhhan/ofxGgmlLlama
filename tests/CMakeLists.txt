cmake_minimum_required(VERSION 3.18)
project(ofxGgmlLlama_tests CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(OFX_GGML_CORE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../ofxGgmlCore")

add_executable(ofxGgmlLlama_tests
	test_main.cpp)

target_include_directories(ofxGgmlLlama_tests PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}/../src
	${OFX_GGML_CORE_ROOT}/src)

enable_testing()
add_test(NAME ofxGgmlLlama_tests COMMAND ofxGgmlLlama_tests)
