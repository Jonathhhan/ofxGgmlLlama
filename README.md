# ofxGgmlLlama

`ofxGgmlLlama` is the companion addon for llama.cpp workflows on top of
`ofxGgmlCore`: local text generation, chat, embeddings, `llama-server`
lifecycle scripts, concrete llama adapters, and focused openFrameworks examples.

`ofxGgmlCore` stays the dependency. This addon owns llama.cpp-specific adapters,
tooling, and examples so core can stay small and boring.

Current addon API version: `1.0.1`.

Family map: https://jonathhhan.github.io/ofxGgmlCore/

## Examples

| Example | Use it for | Server |
| --- | --- | --- |
| `ofxGgmlTextExample` | One editable prompt and one streamed response. | `8080` |
| `ofxGgmlChatExample` | Interactive chat with history and sampling controls. | `8080` |
| `ofxGgmlEmbeddingExample` | Compare two texts with cosine similarity. | `8081` |
| `ofxGgmlLlamaCodexLocalExample` | Local OpenAI Codex provider/profile setup using `llama-server`. | `8001` |

The examples use conventional openFrameworks addon example names. The helper
scripts repair generated Visual Studio metadata when Project Generator includes
stale build-cache paths.

For llama-lane planning and backend boundaries, see
[`docs/LLAMA_WORKFLOWS.md`](docs/LLAMA_WORKFLOWS.md).
For Codex, GitHub Copilot, Hermes Agent, or other local coding assistants using
`llama-server`, see
[`docs/CODEX_COPILOT_LOCAL_SERVER.md`](docs/CODEX_COPILOT_LOCAL_SERVER.md).

## First Run

From the openFrameworks `addons` folder:

```powershell
git clone https://github.com/Jonathhhan/ofxGgmlCore.git
git clone https://github.com/Jonathhhan/ofxGgmlLlama.git
cd ofxGgmlLlama
scripts\build-llama-server.bat
scripts\list-models.bat -Json -SummaryOnly
scripts\run-llama-runtime-smoke.bat -DryRun
scripts\run-example.bat text -Build -Model C:\path\to\model.gguf
scripts\run-example.bat chat -Build -Model C:\path\to\model.gguf
scripts\run-example.bat embedding -Build -Model C:\path\to\embedding-model.gguf
scripts\run-example.bat codex -Build
```

Put GGUF models in `addons\models`, `ofxGgmlLlama\models`, or pass `-Model`.
Text and chat use `llama-server` on `8080` by default. Embeddings use a separate
embedding server on `8081`. The Codex local example documents a dedicated
OpenAI-compatible server on `8001`; it can also auto-write Codex-compatible
provider/profile config sections to `%USERPROFILE%\.codex\config.toml` when
`OFXGGML_CODEX_AUTO_CONFIG=1` (default). `run-example`
starts the bundled server when needed for text, chat, and embedding examples and
waits until it is ready before opening the example.

The lane-owned runtime smoke uses the bundled `llama-cli` directly. The dry-run
is model-free and reports discovery state. With a GGUF model available, the real
smoke runs a tiny deterministic prompt and emits timing/text metadata without
writing generated artifacts:

```powershell
scripts\run-llama-runtime-smoke.bat -DryRun
scripts\run-llama-runtime-smoke.bat -Backend cpu -Json -SummaryOnly
scripts\run-llama-runtime-smoke.bat -Backend cuda -Json -SummaryOnly
scripts\run-llama-runtime-smoke.bat -Backend cpu -Json -SummaryOnly -OutputPath .llama-runtime-smoke.json
```

`scripts\list-models.bat -Json -SummaryOnly` reports the compact model
discovery contract used by Core planning, including text, embedding, and tiny
text-model candidate counts. A successful model-backed smoke can write local
ignored evidence to `.llama-runtime-smoke.json` for Core release-readiness
planning.

## Dependencies

- openFrameworks
- `ofxGgmlCore`
- `ofxImGui` for the GUI examples
- Git, CMake, and a C++ compiler for building llama.cpp tools

## Validate

```powershell
scripts\doctor-llama.bat
scripts\run-llama-runtime-smoke.bat -DryRun
scripts\validate-local.bat
```

On macOS/Linux:

```sh
./scripts/doctor-llama.sh
./scripts/validate-local.sh
```

Release smoke checks are listed in
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md).
Tagging and compatibility policy is in
[`docs/RELEASE_POLICY.md`](docs/RELEASE_POLICY.md).
Release history is tracked in [`CHANGELOG.md`](CHANGELOG.md).
Prepared release notes are in [`docs/releases/v1.0.1.md`](docs/releases/v1.0.1.md).

## Scripts

The public script surface is intentionally small:

```text
scripts/build-example.*
scripts/run-example.*
scripts/build-llama-server.*
scripts/doctor-llama.*
scripts/start-llama-server.*
scripts/stop-llama-server.*
scripts/status-llama-server.*
scripts/list-models.*
scripts/validate-local.*
```

Maintainer-only checks and compatibility wrappers live under `scripts/dev`.

## Boundary

Keep llama.cpp process management, server launch, prompt/chat/embedding
examples, and llama-specific user workflow here. Move code down into
`ofxGgmlCore` only when it becomes a stable, domain-neutral primitive with
focused tests.

Projects migrating from the earlier Core-hosted llama adapters should follow
[`docs/MIGRATION.md`](docs/MIGRATION.md).
