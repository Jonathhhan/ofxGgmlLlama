# Codex, OpenCode, and Copilot Local Llama Server

This guide belongs in `ofxGgmlLlama` because it is llama.cpp setup, GGUF model
download, and `llama-server` lifecycle guidance. `ofxGgmlAgents` should consume
the resulting OpenAI-compatible endpoint, not own the model runtime setup.

Use this path when Codex, OpenCode, GitHub Copilot, Hermes Agent, or another
coding assistant needs a local llama.cpp server.

For OpenCode's native custom-provider path, see
`docs/OPENCODE_LOCAL_SERVER.md`. For a broader router view across Codex,
OpenCode, Claude Code, Copilot, and local helper tasks, see
`docs/LOCAL_AGENT_ROUTING.md`.

Boundary note: the Codex/OpenCode "agent" settings in this guide are external
client fanout and permission controls for a local `llama-server` endpoint. They
are not the internal `ofxGgmlAgents` runtime. Agent planning loops, tool
registries, memory handoff, and addon orchestration remain in `ofxGgmlAgents`.

For an openFrameworks-facing walkthrough, generate
`ofxGgmlLlamaCodexLocalExample` or run:

```powershell
scripts\run-example.bat codex -Build
```

The example displays the endpoint, model alias, Codex provider/profile snippet,
and validation commands without editing local Codex config.

## Recommended addon path

From the `ofxGgmlLlama` addon root, build the lane-owned llama.cpp runtime:

```powershell
scripts\build-llama-server.bat -Cuda
```

Use CPU-only inference when CUDA is not available:

```powershell
scripts\build-llama-server.bat -CpuOnly
```

On macOS, use the shell wrapper and let Metal be selected by the platform build:

```sh
./scripts/build-llama-server.sh -Metal
```

The installed runtime lives under `libs/llama/bin`. Do not commit downloaded
runtime sources, build products, model weights, logs, or caches.

## Direct upstream build

Use the upstream llama.cpp build when you want to follow the official project
layout exactly or test a runtime outside the addon-managed install path.

Linux CUDA example:

```sh
apt-get update
apt-get install pciutils build-essential cmake curl libcurl4-openssl-dev git-all -y
git clone https://github.com/ggml-org/llama.cpp
cmake -S llama.cpp -B llama.cpp/build \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_CUDA=ON \
    -DLLAMA_BUILD_SERVER=ON \
    -DLLAMA_BUILD_EXAMPLES=ON
cmake --build llama.cpp/build --config Release -j --clean-first --target llama-cli llama-server llama-gguf-split
cp llama.cpp/build/bin/llama-* llama.cpp
```

Set `-DGGML_CUDA=OFF` for CPU-only builds. On Apple Silicon, keep CUDA off;
llama.cpp's Metal path is enabled by the macOS build when the required platform
toolchain is available.

## Download a GGUF model

Install the Hugging Face helpers:

```sh
pip install huggingface_hub hf_transfer
```

Download a coding-assistant model into the shared addon model area. From the
`ofxGgmlLlama` root:

```python
import os
from huggingface_hub import snapshot_download

os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"

snapshot_download(
    repo_id="unsloth/GLM-4.7-Flash-GGUF",
    local_dir="../models/unsloth/GLM-4.7-Flash-GGUF",
    allow_patterns=["*UD-Q4_K_XL*"],
)
```

Other viable coding models can use the same layout, for example
`unsloth/Qwen3-Coder-Next-GGUF`. Keep model weights under `addons/models`,
`ofxGgmlLlama/models`, or pass an explicit model path to the scripts.

Check discovery:

```powershell
scripts\list-models.bat
```

## Start the server for coding agents

For the large GLM-4.7 Flash quant, use a dedicated coding-agent port such as
`8001`. This mirrors the Unsloth-style llama.cpp serving setup while keeping the
normal addon examples on their default ports.

```sh
./llama.cpp/llama-server \
    --model unsloth/GLM-4.7-Flash-GGUF/GLM-4.7-Flash-UD-Q4_K_XL.gguf \
    --alias "local/GLM-4.7-Flash-UD-Q4_K_XL" \
    --jinja \
    --chat-template-kwargs '{"enable_thinking": false}' \
    --reasoning off \
    --reasoning-budget 0 \
    --temp 1.0 \
    --top-p 0.95 \
    --min-p 0.01 \
    --port 8001 \
    --kv-unified \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --flash-attn on \
    --batch-size 4096 --ubatch-size 1024 \
    --ctx-size 131072
```

On a 24 GB GPU this configuration is near the practical memory limit. If
performance is poor or the model does not fit, reduce `--ctx-size`, reduce
batch sizes, or switch to a smaller quant/model.

For addon-managed binaries, use the installed server path and the same model
file:

```powershell
scripts\start-llama-server.bat `
    -ModelPath ..\models\unsloth\GLM-4.7-Flash-GGUF\GLM-4.7-Flash-UD-Q4_K_XL.gguf `
    -Port 8001 `
    -Alias local/GLM-4.7-Flash-UD-Q4_K_XL `
    -GpuLayers all `
    -ContextSize 131072 `
    -ChatTemplateKwargs '{"enable_thinking": false}' `
    -Reasoning off `
    -ReasoningBudget 0 `
    -CacheReuse 256 `
    -Jinja
```

The Codex example and `scripts\run-example.bat codex` also expose presets:
`memory`, `fast`, `balanced`, `quality`, `long`, and `concurrent`. The default
`quality` preset uses `ctx=65536`, `batch=3072`, `temp=0.7`, larger tool output,
and one agent slot. `fast` lowers the Codex context to `32768`, raises prompt
batching to `4096/1024`, and keeps cache reuse enabled for lower-latency local
coding. `long` raises context to `131072` for high-VRAM systems. `concurrent`
uses `parallel=2` and two agent slots, so use it only when the model and GPU
have enough headroom.
The default GPU setting is `-GpuLayers all`, matching llama.cpp's literal
`-ngl all`; switch to a numeric layer count only for explicit VRAM limiting.
CUDA graphs stay enabled by default; use `-NoCudaGraphs` only to work around
runtime-specific graph issues.

The addon wrapper intentionally exposes a conservative common subset of
`llama-server` flags. Use the direct upstream command when you need advanced
flags such as KV cache quantization, `--kv-unified`, speculative decoding, or
unusual sampling defaults for a coding-agent session.

## Wire Codex, OpenCode, or Copilot

Point any client that supports an OpenAI-compatible local endpoint at:

```text
http://127.0.0.1:8001/v1
```

Use the model alias configured on the server, for example:

```text
local/GLM-4.7-Flash-UD-Q4_K_XL
```

For Codex, this alias is not just display text. The profile `model` value must
match the llama-server alias. In `ofxGgmlLlamaCodexLocalExample`, that alias is
the editable `ServerModel` field. If you start the server with
`-ServerModel local/qwen2.5-coder-1.5b`, the Codex profile must use
`model = "local/qwen2.5-coder-1.5b"`.

The alias is also not proof of which model file is loaded. A server can load a
Qwen GGUF while advertising `local/GLM-4.7-Flash-UD-Q4_K_XL` if it was started with the
wrong `--alias`. When no explicit `-ServerModel` or `OFXGGML_CODEX_MODEL` is
provided, the addon launcher derives a local alias from the GGUF filename
instead of pretending every discovered model is GLM.

For Codex, the local config shape is (and is typically resolved from
`%USERPROFILE%\.codex\config.toml` on Windows):

```toml
model = "local/GLM-4.7-Flash-UD-Q4_K_XL"
model_provider = "llama_cpp"
web_search = "disabled"
model_context_window = 65536
model_auto_compact_token_limit = 50000
tool_output_token_limit = 8000
model_reasoning_effort = "medium"
model_reasoning_summary = "none"
hide_agent_reasoning = true

[model_providers.llama_cpp]
name = "llama.cpp local"
base_url = "http://127.0.0.1:8001/v1"
wire_api = "responses"
stream_idle_timeout_ms = 10000000

[profiles.ofxggml_local]
model = "local/GLM-4.7-Flash-UD-Q4_K_XL"
model_provider = "llama_cpp"
web_search = "disabled"
model_reasoning_effort = "medium"
model_reasoning_summary = "none"

[agents]
max_threads = 1
max_depth = 1
```

The example auto-config writer also refreshes `%CODEX_HOME%\agents\explorer.toml`
and `%CODEX_HOME%\agents\worker.toml` (or the matching `%USERPROFILE%\.codex`
path). These files override Codex's built-in explorer and worker roles so
spawned agents stay on the local llama.cpp provider. The main config does not
reference them with `config_file`.
The launch and smoke helpers also pass `model_providers.llama_cpp.base_url`,
`model_providers.llama_cpp.wire_api`, and the stream idle timeout with `codex -c`
overrides. That keeps one-shot local Codex runs bound to the visible
`llama-server` endpoint even when the active global config is missing or stale.

For OpenCode, the same local server is configured in `opencode.json` with
`@ai-sdk/openai-compatible`. The full model id is `provider_id/model_id`, so the
default addon config uses:

```text
llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL
```

Generate the OpenCode snippet without editing local files:

```powershell
scripts\plan-local-opencode.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -SummaryOnly
```

The example config lives at
`ofxGgmlLlamaCodexLocalExample\opencode.example.json`.

Use the custom provider explicitly when launching Codex:

```powershell
codex --no-alt-screen -p ofxggml_local `
    --disable apps --disable image_generation --disable browser_use --disable computer_use --disable tool_search `
    -c web_search='"disabled"' `
    -c model_provider=llama_cpp `
    -c model_context_window=65536 `
    -c model_auto_compact_token_limit=50000 `
    -c tool_output_token_limit=8000 `
    -c model_reasoning_effort=medium `
    -c model_reasoning_summary=none `
    -c hide_agent_reasoning=true `
    -c agents.max_threads=1 `
    -c agents.max_depth=1 `
    --model local/GLM-4.7-Flash-UD-Q4_K_XL
```

The agent defaults are intentionally narrow for one local `llama-server`. `agents.max_threads` caps local worker fanout and `agents.max_depth` caps nested delegation. Increase them only when your model, VRAM, and server `--parallel` setting can absorb concurrent Codex work. Helper scripts expose the thread cap as `-AgentMaxThreads`, `-MaxAgentThreads`, `-MaxAgents`, or `-AgentMaxAgents`.

Do not use `--oss` for this llama.cpp lane. `--oss` selects Codex's built-in
open-source provider flow; this ecosystem lane is a named OpenAI-compatible
provider served by `llama-server`.

The disable flags are intentional for direct `llama-server` use. Codex can load
Responses tools whose type is not `function` such as web search, image
generation, browser, and app namespace tools; llama.cpp rejects those tool
definitions. Shell and patch tools remain available as function tools.

### Claude Code hybrid routing

Claude Code is a different integration shape. Do not point Claude Code directly
at `llama-server`: Claude Code speaks Anthropic's Messages API, while
`llama-server` exposes an OpenAI-compatible endpoint. The useful pattern is a
hybrid router or proxy:

```powershell
$env:ANTHROPIC_BASE_URL = "http://127.0.0.1:8080"
claude
```

That proxy can forward complex planning, code generation, and high-risk
decisions to Anthropic, while routing cheap local tasks to addon-owned local
models:

| Task | Local lane |
| --- | --- |
| Embeddings and RAG indexing | `ofxGgmlLlama` embedding server or `ofxGgmlRag` |
| Simple classification and intent detection | `ofxGgmlLlama` text/chat server |
| Audio transcription | `ofxGgmlAudio` / Whisper lane |
| Summarizing local context before a Claude call | `ofxGgmlLlama` text/chat server |

The proxy must decide which requests are safe to answer locally, validate
structured local outputs, and fall back to Anthropic when the local model is
uncertain. Tools such as LiteLLM or a small custom FastAPI service can provide
that Anthropic-compatible front door. This addon should provide the local
endpoints and validation helpers; it should not impersonate Claude Code's API
directly.

Before launching an interactive Codex session, run the local planner:

```powershell
scripts\plan-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -SummaryOnly
```

The planner does not edit Codex config or start Codex. It reports the resolved
Codex executable, config file, endpoint health, provider/profile readiness, and
the exact launch command that should be used. When the endpoint is down, JSON
output also includes `StartServerCommand`, `ManualServerCommand`,
`DetachedNoHealthCheckCommand`, `StatusCommand`, and `RecommendedActions` so the
next step is copyable from the same preflight result. If background startup
times out while a large GGUF is still loading, run `ManualServerCommand` in a
terminal and use the status command from another terminal once the server logs
show it is listening. If you omit `-Model`, the planner suggests a discovered
local text GGUF and derives the server alias from that file name.

Check the dedicated Codex port alongside the normal text and embedding ports:

```powershell
scripts\status-llama-server.bat -CodexServerUrl http://127.0.0.1:8001 -Json -SummaryOnly
```

Codex executable discovery is automatic. The scripts use `OFXGGML_CODEX_EXE`
when set, then Codex Desktop's `%LOCALAPPDATA%\OpenAI\Codex\bin\codex.exe`,
then `where codex`.

After the planner reports ready, run the non-interactive smoke to prove Codex
itself can use the local endpoint:

```powershell
scripts\test-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -Json -SummaryOnly
```

This runs `codex exec` with the llama.cpp-compatible tool disables and checks
for the marker response `LOCAL_CODEX_OK`.

The planner and smoke also include alias sanity evidence: model ids advertised
by `/v1/models` and, on local Windows runs, the `llama-server.exe -m` model file
from the process command line. If `model = "local/GLM-4.7-Flash-UD-Q4_K_XL"` but the
process path points at a Qwen GGUF, the server was started with a misleading
alias and should be restarted with the intended model file or a truthful alias.
When a manually started server advertises exactly one model id, add
`-UseServedModel` to `plan-local-codex` or `test-local-codex` to use that live
server id instead of a stale requested alias.
The planner also blocks when more than one local `llama-server.exe` process is
targeting the Codex port; stop stale servers or restart from the example with
`Force new` so Codex talks to the intended process.

Keep the client integration outside this addon unless it is just documentation
or a smoke check. Runtime setup, model selection, and llama.cpp server lifecycle
stay in `ofxGgmlLlama`; agent orchestration and tool-loop behavior stay in
`ofxGgmlAgents`.

## Validation

Before handing this setup to an agent, verify the lane locally:

```powershell
scripts\doctor-llama.bat
scripts\list-models.bat
scripts\run-llama-runtime-smoke.bat -DryRun
scripts\plan-local-codex.bat -SummaryOnly
scripts\plan-local-opencode.bat -SummaryOnly
scripts\test-local-codex.bat -DryRun -Json -SummaryOnly
```

With a compatible model available, run a real smoke:

```powershell
scripts\run-llama-runtime-smoke.bat -Backend cuda -Json -SummaryOnly
scripts\test-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -Json -SummaryOnly
```

If the endpoint is already running and `/v1/models` advertises a different
single model id, run:

```powershell
scripts\test-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -UseServedModel -Json -SummaryOnly
```

Use `-Backend cpu` when validating a CPU-only install.
