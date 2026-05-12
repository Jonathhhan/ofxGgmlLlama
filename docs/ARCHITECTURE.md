# Architecture

`ofxGgmlLlama` owns llama.cpp-specific workflow code. It uses `ofxGgmlCore` for
the stable text and embedding request/result APIs and keeps process/server
tooling out of core.

During the first split, the transitional C++ adapter implementations still live
in `ofxGgmlCore`, but this companion includes those adapter headers explicitly
through `src/ofxGgmlLlama.h`. Generic Core headers must not be relied on to
re-export llama-specific adapters.

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
- the public companion umbrella that exposes transitional llama adapters

## Not Owned Here

- ggml runtime setup and backend selection
- generic tensor, graph, model metadata, and result types
- SAM, music, speech, diffusion, RAG, or agent workflows
