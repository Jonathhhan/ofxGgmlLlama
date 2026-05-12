# Migration Notes

## Core/Llama Split

`ofxGgmlCore` no longer ships llama.cpp-specific adapters. Projects that use
`ofxGgmlLlamaCliTextBackend`, `ofxGgmlLlamaServerTextBackend`, or
`ofxGgmlLlamaServerEmbeddingBackend` should depend on `ofxGgmlLlama`.

In `addons.make`:

```text
ofxGgmlCore
ofxGgmlLlama
```

In app code, prefer the companion umbrella:

```cpp
#include "ofxGgmlLlama.h"
```

Direct adapter includes are still available from this addon when needed:

```cpp
#include "inference/ofxGgmlLlamaCliTextBackend.h"
#include "inference/ofxGgmlLlamaServerTextBackend.h"
#include "inference/ofxGgmlLlamaServerEmbeddingBackend.h"
```

Generic request/result types remain in `ofxGgmlCore`, so code that only uses
`ofxGgmlTextRequest`, `ofxGgmlTextResult`, `ofxGgmlEmbeddingRequest`, or
`ofxGgmlEmbeddingResult` can continue to include Core headers only.

## Example Folders

The examples keep conventional openFrameworks names:

```text
ofxGgmlTextExample
ofxGgmlChatExample
ofxGgmlEmbeddingExample
```

Generated Visual Studio files can be recreated with the Project Generator or the
addon build scripts. If Project Generator includes stale build-cache paths, rerun
the matching build script so it repairs the generated metadata.
