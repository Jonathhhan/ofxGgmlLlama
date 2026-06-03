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
    -CodexPreset qwen27b-3090 `
    -Model ..\models\unsloth\GLM-4.7-Flash-GGUF\GLM-4.7-Flash-UD-Q4_K_XL.gguf `
    -ServerModel local/GLM-4.7-Flash-UD-Q4_K_XL `
    -GpuLayers all `
    -ContextSize 262144 `
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
| `qwen27b-3090` | `Qwen3.6-27B-Q4_0` on RTX 3090 24 GB. | `ctx=65536`, `parallel=1`, `batch=1024`, `ubatch=256`, `ctk=q4_0`, `ctv=q4_0`, max agents `1`, `temp=0.2`, `top_p=0.85`. |
| `rtx4090` | Qwen3.6-27B on RTX 4090 24 GB with higher batch. | `ctx=65536`, `parallel=1`, `batch=2048`, `ubatch=512`, `ctk=q4_0`, `ctv=q4_0`, max agents `1`, `temp=0.2`, `top_p=0.85`. |
| `fast` | Lower-latency coding on large local models. | `ctx=32768`, `batch=4096`, `ubatch=1024`, cache reuse on. |
| `balanced` | Previous default local coding setup (replaced by qwen27b-3090). | `ctx=40960`, `batch=2048`, one agent slot. |
| `quality` | Full-context coding for high-VRAM systems (not default for 24 GB GPUs). | `ctx=262144`, `batch=3072`, `temp=0.15`, larger tool output. |
| `fullctx` | Full model-metadata context with moderate KV compression. | `ctx=0`, `parallel=1`, `ctk=q8_0`, `ctv=q8_0`, `auto_compact=220000`, `tool_output=12000`. |
| `fullctx-q5` | Full model-metadata context with smaller KV cache. | `ctx=0`, `parallel=1`, `ctk=q5_0`, `ctv=q5_0`, `batch=2048`, `ubatch=512`. |
| `fullctx-q4` | Full model-metadata context with the smallest preset KV cache. | `ctx=0`, `parallel=1`, `ctk=q4_0`, `ctv=q4_0`, `batch=1536`, `ubatch=384`. |
| `long` | Large-context coding on high-VRAM systems. | `ctx=262144`, `batch=4096`, one agent slot. |
| `concurrent` | Two local Codex sessions or subagent work. | `ctx=65536`, `parallel=2`, max agents `2`. |

Use `OFXGGML_CODEX_PRESET` or `-CodexPreset` to pick one. The default preset is now `qwen27b-3090` for 24 GB GPUs. Any explicit script
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
`--reasoning-budget 0`, `-ngl all`, `--ctx-size 262144`, `--parallel 1`,
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
If metadata is unavailable, these presets fall back to `model_context_window=262144`,
matching the Qwen3.6-35B-A3B model card's native context length.
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
model = "local/Qwen3.6-35B-A3B-UD-Q4_K_M"
model_provider = "llama_cpp"
web_search = "live"
model_context_window = 262144
model_auto_compact_token_limit = 220000
tool_output_token_limit = 12000
model_reasoning_effort = "medium"
model_reasoning_summary = "none"
hide_agent_reasoning = true

[model_providers.llama_cpp]
name = "llama.cpp local"
base_url = "http://127.0.0.1:8001/v1"
wire_api = "responses"
stream_idle_timeout_ms = 10000000

[profiles.ofxggml_local]
model = "local/Qwen3.6-35B-A3B-UD-Q4_K_M"
model_provider = "llama_cpp"
web_search = "live"
model_reasoning_effort = "medium"
model_reasoning_summary = "none"
```

`profiles.ofxggml_local.model` must match the llama-server alias used by the
example's `ServerModel` field. The alias is not proof of which GGUF is loaded:
`llama-server` can serve one GGUF while advertising a different alias if you pass
the wrong `--alias`. If you do not pass `-ServerModel`, the launcher prefers the
resolved local GGUF path from `-Model`, `OFXGGML_TEXT_MODEL`, or local model
discovery and derives a truthful alias from that filename, such as
`local/GLM-4.7-Flash-UD-Q4_K_XL` or
`local/qwen2.5-coder-1.5b-instruct-q4_k_m`. If no local GGUF is resolved, it
falls back to `OFXGGML_CODEX_MODEL` or the example default
`local/Qwen3.6-35B-A3B-UD-Q4_K_M`. If you launch a smaller local Qwen model with
`-ServerModel local/qwen2.5-coder-1.5b`, use this profile instead:

```toml
[profiles.ofxggml_local]
model = "local/qwen2.5-coder-1.5b"
model_provider = "llama_cpp"
```

This folder includes `codex-config.example.toml` with the same starting point.
It also includes `codex-config.ollama.example.toml` for the Hermes/Ollama
provider shape.
It also includes `codex-agents/explorer.toml` and `codex-agents/worker.toml`.
The example's auto-config writer refreshes matching built-in role override
files under your Codex home at `agents/`. The main config does not reference
those files with `config_file`; Codex loads `agents/explorer.toml` and
`agents/worker.toml` as overrides for its built-in agent names.
The example's **Launch Codex** button uses the same custom-provider contract:

```powershell
codex --no-alt-screen -p ofxggml_local `
    --disable apps --disable image_generation --disable browser_use --disable computer_use --disable tool_search `
    -c web_search='"live"' `
    -c model_provider=llama_cpp `
    -c model_providers.llama_cpp.base_url='"http://127.0.0.1:8001/v1"' `
    -c model_providers.llama_cpp.wire_api='"responses"' `
    -c model_context_window=262144 `
    -c model_auto_compact_token_limit=220000 `
    -c tool_output_token_limit=12000 `
    -c model_reasoning_effort=medium `
    -c model_reasoning_summary=none `
    -c hide_agent_reasoning=true `
    --model local/GLM-4.7-Flash-UD-Q4_K_XL
```

The agent thread cap and depth default to auto, so `agents.max_threads` and `agents.max_depth` are omitted unless you set positive overrides. The helper scripts accept `-AgentMaxThreads`, `-MaxAgentThreads`, `-MaxAgents`, or `-AgentMaxAgents` for an explicit thread cap, and `-AgentMaxDepth` for an explicit depth cap.

The Codex executable path is detected automatically from `OFXGGML_CODEX_EXE`,
Codex Desktop's `%LOCALAPPDATA%\OpenAI\Codex\bin\codex.exe`, or `where codex`.
The file picker is only needed for unusual installs.

Use the **Codex provider** selector to switch between local and cloud-backed
Codex runs. `Local llama.cpp` keeps the self-contained `llama_cpp` provider
overrides, local role files, and server startup flow described above. `OpenAI
profile` launches Codex with the selected profile and optional model alias from
your normal Codex config, skips the local provider overrides, skips local
agent-role file writes, and does not start `llama-server`.
`Hybrid: local agents` keeps the local `llama_cpp` provider and explorer/worker
agent role files for cheap agent work, while the main Codex launch uses the
OpenAI model field for expensive reasoning.
`Ollama Hermes` uses Ollama's OpenAI-compatible endpoint for the main local
Codex launch, defaulting to `http://127.0.0.1:11434/v1` and
`hermes3:latest`. `Hybrid: Ollama agents` keeps Hermes/Ollama for cheap
explorer/worker agents while the main launch uses the OpenAI model field.

Sandbox defaults are part of the provider-mode contract. `Local llama.cpp` and
`Ollama Hermes` default the main Codex launch to `workspace-write`. `OpenAI
profile` and the hybrid modes leave the main launch sandbox unset unless you
provide `OFXGGML_CODEX_SANDBOX` or edit **Codex sandbox** in the UI. The
generated `explorer` role stays `read-only`, while the generated `worker` role
uses `workspace-write`.

From the helper script:

```powershell
scripts\run-example.bat codex -CodexProvider openai -ServerModel gpt-5
scripts\run-example.bat codex -CodexProvider hybrid -OpenAiModel gpt-5
scripts\run-example.bat codex -CodexProvider ollama -ServerModel hermes3:latest
scripts\run-example.bat codex -CodexProvider hybrid-ollama -OpenAiModel gpt-5
```

The environment equivalent is:

```powershell
$env:OFXGGML_CODEX_PROVIDER = "openai"
$env:OFXGGML_CODEX_PROVIDER = "hybrid"
$env:OFXGGML_CODEX_OPENAI_MODEL = "gpt-5"
$env:OFXGGML_CODEX_PROVIDER = "hybrid-ollama"
$env:OFXGGML_CODEX_MODEL = "hermes3:latest"
$env:OFXGGML_CODEX_BASE_URL = "http://127.0.0.1:11434/v1"
```

Do not add `--oss` for this llama.cpp path. Codex's built-in OSS shortcut is
for built-in local providers such as Ollama or LM Studio; this example uses the
explicit `llama_cpp` OpenAI-compatible provider configured above.
The disable flags keep Codex from sending non-function Responses tools such as
app namespaces, image generation, browser, or web-search tools; llama.cpp
accepts the function-tool shape used by shell and patch tools.
The provider `base_url` and `wire_api` are also passed as one-shot overrides so
the launch path stays tied to the visible example endpoint instead of silently
depending on a stale global Codex provider config.

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
shell commands, or primary-agent task delegation, and keeps web access allowed
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
$env:OFXGGML_CODEX_MODEL = "local/Qwen3.6-35B-A3B-UD-Q4_K_M"
$env:OFXGGML_CODEX_PRESET = "qwen27b-3090"
$env:OFXGGML_TEXT_MODEL = "C:\path\to\model.gguf"
$env:OFXGGML_CODEX_EXE = "C:\Users\you\AppData\Local\OpenAI\Codex\bin\codex.exe"
$env:OFXGGML_CODEX_GPU_LAYERS = "all"
$env:OFXGGML_CODEX_CONTEXT_SIZE = "262144"
$env:OFXGGML_CODEX_PARALLEL = "1"
$env:OFXGGML_CODEX_FLASH_ATTN = "1"
$env:OFXGGML_CODEX_BATCH_SIZE = "3072"
$env:OFXGGML_CODEX_UBATCH_SIZE = "768"
$env:OFXGGML_CODEX_KV_CACHE_KEY_TYPE = "q8_0"
$env:OFXGGML_CODEX_KV_CACHE_VALUE_TYPE = "q8_0"
$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW = "262144"
$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT = "220000"
$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT = "12000"
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
$env:OFXGGML_CODEX_SANDBOX = "workspace-write"
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
If Codex reports that the Windows admin sandbox could not be initialized, set
`OFXGGML_CODEX_SANDBOX` or the example's **Codex sandbox** field to a mode your
installed Codex build supports. Prefer `workspace-write` for local model runs;
use broader modes only when you deliberately need them.

## Validate

Before giving the endpoint to Codex:

```powershell
scripts\doctor-llama.bat
scripts\list-models.bat
scripts\run-llama-runtime-smoke.bat -Backend cuda -Json -SummaryOnly
scripts\test-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/Qwen3.6-35B-A3B-UD-Q4_K_M -Json -SummaryOnly
```

Use `-Backend cpu` for CPU-only validation.

From `ofxGgmlLlama`, the local Codex readiness planner checks config and
endpoint visibility without mutating files:

```powershell
scripts\plan-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Json -SummaryOnly
```

When the endpoint is down, the planner includes `StartServerCommand`,
`ManualServerCommand`, `DetachedNoHealthCheckCommand`, `StatusCommand`, and
`WaitCommand` fields. Those commands use the Codex port, a discovered local
text GGUF model when available, and a truthful `local/<gguf-file-stem>` alias
unless you pass an explicit `-Model`.

If automatic startup times out, run `ManualServerCommand` in a terminal. It
keeps `llama-server` in the foreground so you can see slow model loading,
VRAM/context failures, or template warnings directly. The example UI also shows
a manual server command below the preflight line for the currently selected
settings. Run `WaitCommand` from a second terminal to poll the Codex endpoint
until it is ready.

The status helper also reports the dedicated Codex endpoint:

```powershell
scripts\status-llama-server.bat -CodexServerUrl http://127.0.0.1:8001 -Json -SummaryOnly
```

```powershell
scripts\status-llama-server.bat -CodexServerUrl http://127.0.0.1:8001 -WaitReady -WaitLabel codex -WaitTimeoutSeconds 600 -Json -SummaryOnly
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
