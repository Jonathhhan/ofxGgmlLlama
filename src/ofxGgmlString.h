#pragma once

#include <cctype>
#include <string>
#include <vector>

namespace ofxGgmlString {

inline std::string trimCopy(const std::string & value) {
  std::size_t first = 0;
  while (first < value.size() &&
    std::isspace(static_cast<unsigned char>(value[first]))) {
    ++first;
  }
  std::size_t last = value.size();
  while (last > first &&
    std::isspace(static_cast<unsigned char>(value[last - 1]))) {
    --last;
  }
  return value.substr(first, last - first);
}

inline bool endsWith(const std::string & value, const std::string & suffix) {
  return value.size() >= suffix.size() &&
    value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0;
}

inline bool startsWith(const std::string & value, const std::string & prefix) {
  return value.size() >= prefix.size() &&
    value.compare(0, prefix.size(), prefix) == 0;
}

inline std::string stripTrailingSlash(std::string value) {
  while (!value.empty() && value.back() == '/') {
    value.pop_back();
  }
  return value;
}

inline std::string escapeJson(const std::string & value) {
  std::string escaped;
  escaped.reserve(value.size());
  for (const unsigned char c : value) {
    switch (c) {
    case '\\': escaped += "\\\\"; break;
    case '"': escaped += "\\\""; break;
    case '\b': escaped += "\\b"; break;
    case '\f': escaped += "\\f"; break;
    case '\n': escaped += "\\n"; break;
    case '\r': escaped += "\\r"; break;
    case '\t': escaped += "\\t"; break;
    default:
      if (c < 0x20) {
        const char * hex = "0123456789abcdef";
        escaped += "\\u00";
        escaped.push_back(hex[(c >> 4) & 0x0f]);
        escaped.push_back(hex[c & 0x0f]);
      } else {
        escaped.push_back(static_cast<char>(c));
      }
      break;
    }
  }
  return escaped;
}


inline std::string eraseDelimitedBlock(
  std::string value,
  const std::string & beginMarker,
  const std::string & endMarker) {
  std::size_t begin = value.find(beginMarker);
  while (begin != std::string::npos) {
    const std::size_t end = value.find(endMarker, begin + beginMarker.size());
    const std::size_t eraseEnd = end == std::string::npos
      ? value.size()
      : end + endMarker.size();
    value.erase(begin, eraseEnd - begin);
    begin = value.find(beginMarker, begin);
  }
  return value;
}

inline std::string stripReasoningBlocks(std::string value) {
  value = eraseDelimitedBlock(value, "<think>", "</think>");
  value = eraseDelimitedBlock(value, "<thinking>", "</thinking>");
  value = eraseDelimitedBlock(value, "[Start thinking]", "[End thinking]");
  value = eraseDelimitedBlock(value, "[Start thinking]", "[Stop thinking]");
  value = eraseDelimitedBlock(value, "[Thinking]", "[/Thinking]");
  return trimCopy(value);
}

} // namespace ofxGgmlString
