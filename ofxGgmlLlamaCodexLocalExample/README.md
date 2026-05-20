# ofxGgmlLlamaCodexLocalExample

Root-level openFrameworks example for running local LLMs with OpenAI Codex,
OpenCode, and other OpenAI-compatible coding clients through `llama.cpp` and
`llama-server`.

This example belongs in `ofxGgmlLlama` because this addon owns llama.cpp builds,
GGUF model discovery, and local server lifecycle. `ofxGgmlAgents` can consume
the resulting endpoint after it is running.

The setup follows the same contract as the Unsloth Codex guide:
https://unsloth.ai/docs/de/grundlagen/codex

OpenCode can reuse the same endpoint through a custom provider in
`opencode.json`; see `opencode.example.json` and
`..\docs\OPENCODE_LOCAL_SERVER.md`.

The Codex/OpenCode agent settings in this example are client resource and
permission knobs for a local `llama-server`. They are not internal
`ofxGgmlAgents` runtime behavior; reusable agent loops and tool orchestration
belong in `ofxGgmlAgents`.

## Build llama.cpp

From the `ofxGgmlLlama` addon root:

```powershell
scripts\build-llama-server.bat -Cuda
```

Use CPU-only inference when CUDA is not available:

```powershell
scripts\build-llama-server.bat -CpuOnly
```

On macOS, use the shell wrapper and let the llama.cpp Metal build path handle
GPU acceleration:

```sh
./scripts/build-llama-server.sh -Metal
```

## Download a GGUF model

Install Hugging Face helpers:

```sh
pip install huggingface_hub hf_transfer
```

Download a coding model into the shared addon model folder:

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

You can use another compatible GGUF model by changing the model path and server
alias.

## Run this example

Generate the project with openFrameworks projectGenerator using addons
`ofxGgmlLlama`, `ofxGgmlCore`, and `ofxImGui`, or use the helper:

```powershell
scripts\run-example.bat codex -Build `
    -CodexPreset quality `
    -Model ..\models\unsloth\GLM-4.7-Flash-GGUF\GLM-4.7-Flash-UD-Q4_K_XL.gguf `
    -ServerModel local/GLM-4.7-Flash-UD-Q4_K_XL `
    -GpuLayers all `
    -ContextSize 65536 `
    -Parallel 1 `
    -BatchSize 3072 `
    -UBatchSize 768 `
    -CacheReuse 256 `
    -Temperature 0.7 `
    -TopP 0.9 `
    -MinP 0.02
```

Preset choices:

| Preset | Use it for | Main settings |
| --- | --- | --- |
| `memory` | Smaller GPUs and first smoke tests. | `ctx=16384`, `batch=1024`, one agent slot. |
| `fast` | Lower-latency coding on large local models. | `ctx=32768`, `batch=4096`, `ubatch=1024`, cache reuse on. |
| `balanced` | Previous default local coding setup. | `ctx=40960`, `batch=2048`, one agent slot. |
| `quality` | Quality coding default. | `ctx=65536`, `batch=3072`, `temp=0.7`, larger tool output. |
| `fullctx` | Full model-metadata context with moderate KV compression. | `ctx=0`, `parallel=1`, `ctk=q8_0`, `ctv=q8_0`, `auto_compact=112000`, `tool_output=12000`. |
| `fullctx-q5` | Full model-metadata context with smaller KV cache. | `ctx=0`, `parallel=1`, `ctk=q5_0`, `ctv=q5_0`, `batch=2048`, `ubatch=512`. |
| `fullctx-q4` | Full model-metadata context with the smallest preset KV cache. | `ctx=0`, `parallel=1`, `ctk=q4_0`, `ctv=q4_0`, `batch=1536`, `ubatch=384`. |
| `long` | Large-context coding on high-VRAM systems. | `ctx=131072`, `batch=4096`, one agent slot. |
| `concurrent` | Two local Codex sessions or subagent work. | `ctx=65536`, `parallel=2`, max agents `2`. |

Use `OFXGGML_CODEX_PRESET` or `-CodexPreset` to pick one. Any explicit script
argument or `OFXGGML_CODEX_*` setting still overrides the preset value.

If an older local `llama-server` process is stuck on the Codex port and the
example stays at "not ready", use the GUI's `Force new` button or launch with
`-ForceNewServer` so the addon-owned stale server is stopped before restart.
The script planner also flags multiple `llama-server.exe` processes targeting
the Codex port because stale processes can leave Codex talking to a different
server than the one you just configured.

The example uses port `8001` by default for coding-agent sessions so the
text/chat/embedding examples can keep their default ports. It discovers the
built `llama-server`, discovers a local `.gguf` model, starts the server for
local endpoints, shows editable runtime fields in the ImGui panel, and can run
a short OpenAI-compatible endpoint smoke request before you point Codex at it.
The ImGui panel now shows a preflight line near the top and disables only the
actions that are missing required inputs: starting a local server requires a
valid `llama-server` executable and GGUF path, while launching Codex only needs
the endpoint/profile/model alias, Codex config path, and Codex executable. If a
button is disabled, the preflight line names the next field to fix.

For less common llama.cpp flags such as `--kv-unified` or speculative decoding,
run `llama-server` directly from the built runtime and keep the same
OpenAI-compatible endpoint:

```text
http://127.0.0.1:8001/v1
```

The Codex example defaults keep CUDA graphs enabled, keep GLM thinking disabled,
and match the local Codex runtime shape by launching `llama-server` with `--jinja`,
`--chat-template-kwargs '{"enable_thinking": false}'`, `--reasoning off`,
`--reasoning-budget 0`, `-ngl all`, `--ctx-size 65536`, `--parallel 1`,
`--flash-attn on`, `--batch-size 3072`,
and `--ubatch-size 768`. `--skip-chat-parsing` is off by default so the model
chat template remains active.
Set the GUI's **Spec type** dropdown to `ngram-cache` when llama.cpp asks for a
speculative decoding implementation but you are not using a separate draft
model.
The ImGui panel exposes a `GPU layers all` toggle for literal `-ngl all` mode;
turn it off only when you need a fixed numeric layer count.

Use `-CodexPreset fullctx` when Codex should be allowed to occupy the model's
full metadata context. It passes `--ctx-size 0`, keeps `--parallel 1`, enables
Flash Attention, uses `-ngl all`, and sets both `-ctk` and `-ctv` to `q8_0`.
Use `fullctx-q5` or `fullctx-q4` when the full context needs a smaller KV cache
to fit in VRAM. The Codex config window still has to be numeric; when the
example can read GGUF metadata, it copies the model's `context_length` into
`model_context_window` and sets auto-compact to about 85% of that window.
If metadata is unavailable, these presets fall back to `model_context_window=131072`.
The GUI exposes **KV cache K type** and **KV cache V type** dropdowns for the
same cache type values supported by the bundled `llama-server`.

Keep `--parallel 1` for a single Codex session when you want the full token
window available to one request. Raise it only when you expect concurrent
clients; more slots can improve throughput for simultaneous requests, but it
increases memory pressure and may reduce the practical context available per
slot depending on the llama.cpp build and model.

## Configure Codex

Create or edit your local Codex config. This example now defaults to Codex's
standard config locations and writes:

```text
%CODEX_HOME%\config.toml
%USERPROFILE%\.codex\config.toml
%APPDATA%\OpenAI\Codex\config.toml (legacy fallback)
```

Use this provider/profile shape:

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

`profiles.ofxggml_local.model` must match the llama-server alias used by the
example's `ServerModel` field. The alias is not proof of which GGUF is loaded:
`llama-server` can serve a Qwen file while advertising a GLM alias if you pass
the wrong `--alias`. If you do not pass `-ServerModel` and do not set
`OFXGGML_CODEX_MODEL`, the launcher derives a truthful alias from the GGUF
filename, such as `local/GLM-4.7-Flash-UD-Q4_K_XL` or
`local/qwen2.5-coder-1.5b-instruct-q4_k_m`. If you launch a smaller local Qwen
model with `-ServerModel local/qwen2.5-coder-1.5b`, use this profile instead:

```toml
[profiles.ofxggml_local]
model = "local/qwen2.5-coder-1.5b"
model_provider = "llama_cpp"
```

This folder includes `codex-config.example.toml` with the same starting point.
It also includes `codex-agents/explorer.toml` and `codex-agents/worker.toml`.
The example's auto-config writer refreshes matching built-in role override
files under your Codex home at `agents/`. The main config does not reference
those files with `config_file`; Codex loads `agents/explorer.toml` and
`agents/worker.toml` as overrides for its built-in agent names.
The example's **Launch Codex** button uses the same custom-provider contract:

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

The agent defaults are intentionally conservative for local GGUF models. `agents.max_threads` caps local worker fanout and `agents.max_depth` caps nested delegation. Keep the thread cap aligned with server `--parallel`. The helper scripts accept `-AgentMaxThreads`, `-MaxAgentThreads`, `-MaxAgents`, or `-AgentMaxAgents` for the same cap.

The Codex executable path is detected automatically from `OFXGGML_CODEX_EXE`,
Codex Desktop's `%LOCALAPPDATA%\OpenAI\Codex\bin\codex.exe`, or `where codex`.
The file picker is only needed for unusual installs.

Do not add `--oss` for this llama.cpp path. Codex's built-in OSS shortcut is
for built-in local providers such as Ollama or LM Studio; this example uses the
explicit `llama_cpp` OpenAI-compatible provider configured above.
The disable flags keep Codex from sending non-function Responses tools such as
app namespaces, image generation, browser, or web-search tools; llama.cpp
accepts the function-tool shape used by shell and patch tools.

## Configure OpenCode

OpenCode uses JSON config instead of Codex TOML. The local provider shape is:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL",
  "small_model": "llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL",
  "default_agent": "build",
  "provider": {
    "llama_cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama.cpp local",
      "options": {
        "baseURL": "http://127.0.0.1:8001/v1",
        "apiKey": "local"
      },
      "models": {
        "local/GLM-4.7-Flash-UD-Q4_K_XL": {
          "name": "GLM-4.7 Flash local"
        }
      }
    }
  },
  "disabled_providers": ["openai", "anthropic", "gemini"]
}
```

This folder includes `opencode.example.json` with provider, model limit, and
conservative OpenCode `build`, `plan`, and `explore` agent settings. It makes
`build` the default primary agent, allows read/search tools, asks before edits,
shell commands, or primary-agent task delegation, and keeps web access disabled
for local coding sessions. The full model id is
`llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL`: provider key first, then the
llama-server model alias.

Plan the config from the addon root without mutating OpenCode files:

```powershell
scripts\plan-local-opencode.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -SummaryOnly
```

## Claude Code Hybrid Option

Claude Code cannot use this `llama-server` endpoint directly because it expects
an Anthropic-compatible Messages API, not an OpenAI-compatible server. Use a
local proxy or router when you want Claude Code plus local cost-saving tasks:

```powershell
$env:ANTHROPIC_BASE_URL = "http://127.0.0.1:8080"
claude
```

Keep Claude on complex code generation and planning. Route cheap, constrained
work to local addon endpoints: embeddings/RAG indexing, intent classification,
short context summaries, and audio transcription. The router should validate
local outputs and fall back to Claude when confidence is low. LiteLLM or a
small custom FastAPI service can provide that proxy layer; this addon supplies
the local llama.cpp endpoint and validation helpers.

Optional environment overrides:

```powershell
$env:OFXGGML_CODEX_BASE_URL = "http://127.0.0.1:8001/v1"
$env:OFXGGML_CODEX_MODEL = "local/GLM-4.7-Flash-UD-Q4_K_XL"
$env:OFXGGML_CODEX_PRESET = "quality"
$env:OFXGGML_TEXT_MODEL = "C:\path\to\model.gguf"
$env:OFXGGML_CODEX_EXE = "C:\Users\you\AppData\Local\OpenAI\Codex\bin\codex.exe"
$env:OFXGGML_CODEX_GPU_LAYERS = "all"
$env:OFXGGML_CODEX_CONTEXT_SIZE = "65536"
$env:OFXGGML_CODEX_PARALLEL = "1"
$env:OFXGGML_CODEX_FLASH_ATTN = "1"
$env:OFXGGML_CODEX_BATCH_SIZE = "3072"
$env:OFXGGML_CODEX_UBATCH_SIZE = "768"
$env:OFXGGML_CODEX_KV_CACHE_KEY_TYPE = "q8_0"
$env:OFXGGML_CODEX_KV_CACHE_VALUE_TYPE = "q8_0"
$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW = "65536"
$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT = "50000"
$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT = "8000"
$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS = "1"
$env:OFXGGML_CODEX_AGENT_MAX_DEPTH = "1"
$env:OFXGGML_CODEX_AGENT_MIN_WAIT_MS = "2500"
$env:OFXGGML_CODEX_AGENT_MAX_WAIT_MS = "180000"
$env:OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS = "30000"
$env:OFXGGML_CODEX_TEMP = "0.7"
$env:OFXGGML_CODEX_TOP_P = "0.9"
$env:OFXGGML_CODEX_MIN_P = "0.02"
$env:OFXGGML_CODEX_CHAT_TEMPLATE_KWARGS = '{"enable_thinking": false}'
$env:OFXGGML_CODEX_REASONING = "off"
$env:OFXGGML_CODEX_REASONING_BUDGET = "0"
$env:OFXGGML_CODEX_AUTO_SERVER = "1"
$env:OFXGGML_CODEX_AUTO_CONFIG = "1"
$env:OFXGGML_CODEX_NO_CUDA_GRAPHS = "0"
$env:OFXGGML_CODEX_SKIP_CHAT_PARSING = "0"
$env:OFXGGML_CODEX_CONFIG_PATH = "%USERPROFILE%\.codex\config.toml"
$env:OFXGGML_CODEX_STARTUP_TIMEOUT = "300"
```

The example displays the exact endpoint, model alias, server status, endpoint
smoke result, server-advertised `/v1/models` aliases, local Codex provider
snippet, and editable startup options. The **Use served alias** button copies
the model id advertised by an already-running `llama-server` into the Codex
profile before writing config, which avoids stale aliases when you started the
server manually. It starts the local server when possible and can automatically
write the needed provider/profile sections into the local Codex config if
`OFXGGML_CODEX_AUTO_CONFIG` is set to `1` (default).
Use the UI button **Write Codex config** if you prefer a manual write.

## Validate

Before giving the endpoint to Codex:

```powershell
scripts\doctor-llama.bat
scripts\list-models.bat
scripts\run-llama-runtime-smoke.bat -Backend cuda -Json -SummaryOnly
scripts\test-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -Json -SummaryOnly
```

Use `-Backend cpu` for CPU-only validation.

From `ofxGgmlLlama`, the local Codex readiness planner checks config and
endpoint visibility without mutating files:

```powershell
scripts\plan-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Json -SummaryOnly
```

If `/v1/models` advertises exactly one model and your requested alias is stale,
add `-UseServedModel` to the planner or smoke command to use the live server id:

```powershell
scripts\test-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -UseServedModel -Json -SummaryOnly
```

The `test-local-codex` smoke is the stronger check: it runs `codex exec` and
expects `LOCAL_CODEX_OK` from the local model.
Both planner and smoke output include the advertised `/v1/models` ids and, on
local Windows runs, the actual `llama-server.exe -m` model path so misleading
aliases are visible before Codex work starts.

Keep model weights, downloaded runtimes, generated project files, logs, local
Codex config, and caches out of git.

## ProjectGenerator Compatibility

This example follows the standard openFrameworks addon structure:
- `addons.make` lists required addons: ofxGgmlCore, ofxGgmlLlama, ofxImGui
- Source files in src/ directory (not in code.files or custom vcxproj)
- No hardcoded paths or custom build files
- Generated projects will work with standard openFrameworks toolchain
