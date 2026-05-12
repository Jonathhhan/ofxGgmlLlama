# Architecture

`ofxGgmlLlama` owns llama.cpp-specific workflow code and concrete adapter
implementations. It uses `ofxGgmlCore` for the stable text and embedding
request/result APIs and keeps process/server tooling out of core.

Apps that need llama.cpp backends should include `ofxGgmlLlama.h` and depend on
both `ofxGgmlCore` and `ofxGgmlLlama`. Generic Core headers do not re-export
llama-specific adapters.

## Dependency Direction

```text
openFrameworks app
  -> ofxGgmlLlama
      -> ofxGgmlCore
```

No dependency should point from `ofxGgmlCore` back to `ofxGgmlLlama`.

## Owned Here

- llama.cpp build/install scripts
- `llama-server` start/status/stop scripts
- text, chat, and embedding example apps
- model discovery helpers for llama workflows
- CLI fallback and server launch workflow documentation
- llama CLI, server text, and server embedding adapters
- the public companion umbrella that exposes llama adapters

## Not Owned Here

- ggml runtime setup and backend selection
- generic tensor, graph, model metadata, and result types
- SAM, music, speech, diffusion, RAG, or agent workflows
