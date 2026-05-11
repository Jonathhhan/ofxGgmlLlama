# ofxGgmlLlama

`ofxGgmlLlama` is the companion addon for llama.cpp workflows on top of
`ofxGgmlCore`: local text generation, chat, embeddings, `llama-server`
lifecycle scripts, and focused openFrameworks examples.

`ofxGgmlCore` stays the dependency. This addon owns llama.cpp-specific tooling
and examples so core can stay small and boring.

## Examples

| Example | Use it for | Server |
| --- | --- | --- |
| `ofxGgmlTextExample` | One editable prompt and one streamed response. | `8080` |
| `ofxGgmlChatExample` | Interactive chat with history and sampling controls. | `8080` |
| `ofxGgmlEmbeddingExample` | Compare two texts with cosine similarity. | `8081` |

## First Run

From the openFrameworks `addons` folder:

```powershell
git clone https://github.com/Jonathhhan/ofxGgmlCore.git
git clone https://github.com/Jonathhhan/ofxGgmlLlama.git
cd ofxGgmlLlama
scripts\build-llama-server.bat
scripts\list-models.bat
scripts\run-text-example.bat -Build -Model C:\path\to\model.gguf
scripts\run-chat-example.bat -Build -Model C:\path\to\model.gguf
scripts\run-embedding-example.bat -Build -Model C:\path\to\embedding-model.gguf
```

Put GGUF models in `addons\models`, `ofxGgmlLlama\models`, or pass `-Model`.
Text and chat use `llama-server` on `8080` by default. Embeddings use a separate
embedding server on `8081`.

## Dependencies

- openFrameworks
- `ofxGgmlCore`
- `ofxImGui` for the GUI examples
- Git, CMake, and a C++ compiler for building llama.cpp tools

## Validate

```powershell
scripts\validate-local.bat
```

On macOS/Linux:

```sh
./scripts/validate-local.sh
```

## Boundary

Keep llama.cpp process management, server launch, prompt/chat/embedding
examples, and llama-specific user workflow here. Move code down into
`ofxGgmlCore` only when it becomes a stable, domain-neutral primitive with
focused tests.
