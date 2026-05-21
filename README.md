# ofxGgmlLlama

`ofxGgmlLlama` is the companion addon for llama.cpp workflows on top of
`ofxGgmlCore`: local text generation, chat, embeddings, `llama-server`
lifecycle scripts, concrete llama adapters, and focused openFrameworks examples.

`ofxGgmlCore` stays the dependency. This addon owns llama.cpp-specific adapters,
tooling, and examples so core can stay small and boring.

Current addon API version: `1.0.1`.

Family map: https://jonathhhan.github.io/ofxGgmlCore/

## Features

- local chat and text generation
- embedding extraction
- llama.cpp CLI and server integration
- Codex local model handoff workflow
- model-backed runtime smoke evidence

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
For Codex, OpenCode, GitHub Copilot, Hermes Agent, or other local coding
assistants using `llama-server`, see
[`docs/CODEX_COPILOT_LOCAL_SERVER.md`](docs/CODEX_COPILOT_LOCAL_SERVER.md).
For OpenCode's native custom-provider path, see
[`docs/OPENCODE_LOCAL_SERVER.md`](docs/OPENCODE_LOCAL_SERVER.md).
For hybrid routing across Codex, OpenCode, Claude Code, Copilot, and local helper tasks,
see [`docs/LOCAL_AGENT_ROUTING.md`](docs/LOCAL_AGENT_ROUTING.md).

This addon only plans client-facing Codex/OpenCode configuration for the local
`llama-server` endpoint. Internal agent loops, tool registries, memory handoff,
and addon-to-addon orchestration belong in `ofxGgmlAgents`.

## First Run

From the openFrameworks `addons` folder:

```powershell
git clone https://github.com/Jonathhhan/ofxGgmlCore.git
git clone https://github.com/Jonathhhan/ofxGgmlLlama.git
cd ofxGgmlLlama
scripts\build-llama-server.bat
scripts\list-models.bat -Json -SummaryOnly
scripts\run-llama-runtime-smoke.bat -DryRun
scripts\plan-local-codex.bat -SummaryOnly
scripts\plan-local-opencode.bat -SummaryOnly
scripts\test-local-codex.bat -DryRun -Json -SummaryOnly
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

The Codex-local planner checks the installed Codex CLI, config path, selected
profile/provider, server endpoint health, and launch command without starting an
interactive Codex session:

```powershell
scripts\plan-local-codex.bat -SummaryOnly
scripts\plan-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -Json -SummaryOnly
scripts\test-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -Json -SummaryOnly
```

When the endpoint is down, JSON output includes copyable `StartServerCommand`,
`ManualServerCommand`, `DetachedNoHealthCheckCommand`, `StatusCommand`, and
`WaitCommand` fields. Use `ManualServerCommand` when background startup times
out and you want to watch `llama-server` load the model in the console, then run
`WaitCommand` in another terminal until the Codex endpoint is ready.
`status-llama-server` also reports the dedicated Codex endpoint with
`-CodexServerUrl` and supports `-WaitReady`.

The OpenCode planner uses the same local endpoint and emits a compatible
`opencode.json` provider/agent snippet without editing your OpenCode config:

```powershell
scripts\plan-local-opencode.bat -SummaryOnly
scripts\plan-local-opencode.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -Json -SummaryOnly
scripts\plan-local-opencode.bat -UseServedModel -Json -SummaryOnly
```

Codex executable discovery is automatic: `OFXGGML_CODEX_EXE` override, Codex
Desktop's `%LOCALAPPDATA%\OpenAI\Codex\bin\codex.exe`, then `where codex`.
The planner is read-only preflight. The Codex smoke runs `codex exec` against
the local `llama-server` endpoint and expects `LOCAL_CODEX_OK`, so use it only
after the server is running.
For Codex launches, pass `-ServerModel` only when you intentionally want a
specific server alias. Otherwise the launcher derives a `local/<model-file>`
alias from the actual GGUF path so Codex config cannot silently label Qwen as
GLM.
The planner also reports `/v1/models` ids and, on local Windows runs, the
actual `llama-server.exe -m` model path so alias/model mismatches are visible.
If a manually started server advertises exactly one model id, add
`-UseServedModel` to the planner or smoke command to use that live id instead
of a stale requested alias.
It also flags multiple local `llama-server.exe` processes targeting the Codex
port so stale servers do not quietly steal the session.
Use `-CodexPreset fast` for lower-latency local coding: it keeps one agent slot,
uses a smaller `32768` Codex context, larger prompt batches, cache reuse, Flash
Attention, and CUDA graphs.

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
scripts/plan-local-codex.*
scripts/plan-local-opencode.*
scripts/test-local-codex.*
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
