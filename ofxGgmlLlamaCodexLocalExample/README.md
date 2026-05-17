# ofxGgmlLlamaCodexLocalExample

Root-level openFrameworks example for running local LLMs with OpenAI Codex
through `llama.cpp` and `llama-server`.

This example belongs in `ofxGgmlLlama` because this addon owns llama.cpp builds,
GGUF model discovery, and local server lifecycle. `ofxGgmlAgents` can consume
the resulting endpoint after it is running.

The setup follows the same contract as the Unsloth Codex guide:
https://unsloth.ai/docs/de/grundlagen/codex

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
    -CodexPreset balanced `
    -Model ..\models\unsloth\GLM-4.7-Flash-GGUF\GLM-4.7-Flash-UD-Q4_K_XL.gguf `
    -ServerModel local/GLM-4.7-Flash-UD-Q4_K_XL `
    -GpuLayers all `
    -ContextSize 40960 `
    -Parallel 1 `
    -BatchSize 2048 `
    -UBatchSize 512 `
    -Temperature 1.0 `
    -TopP 0.95 `
    -MinP 0.01
```

Preset choices:

| Preset | Use it for | Main settings |
| --- | --- | --- |
| `memory` | Smaller GPUs and first smoke tests. | `ctx=16384`, `batch=1024`, one agent slot. |
| `balanced` | Default local coding setup. | `ctx=40960`, `batch=2048`, one agent slot. |
| `long` | Large-context coding on high-VRAM systems. | `ctx=131072`, `batch=4096`, one agent slot. |
| `concurrent` | Two local Codex sessions or subagent work. | `ctx=65536`, `parallel=2`, max agents `2`. |

Use `OFXGGML_CODEX_PRESET` or `-CodexPreset` to pick one. Any explicit script
argument or `OFXGGML_CODEX_*` setting still overrides the preset value.

If an older local `llama-server` process is stuck on the Codex port and the
example stays at "not ready", use the GUI's `Force new` button or launch with
`-ForceNewServer` so the addon-owned stale server is stopped before restart.

The example uses port `8001` by default for coding-agent sessions so the
text/chat/embedding examples can keep their default ports. It discovers the
built `llama-server`, discovers a local `.gguf` model, starts the server for
local endpoints, shows editable runtime fields in the ImGui panel, and can run
a short OpenAI-compatible endpoint smoke request before you point Codex at it.

For advanced llama.cpp flags such as KV-cache quantization, batch sizing, or
`--kv-unified`, run `llama-server` directly from the built runtime and keep the
same OpenAI-compatible endpoint:

```text
http://127.0.0.1:8001/v1
```

The Codex example defaults keep GLM thinking disabled and match the local Codex
runtime shape by launching `llama-server` with `--jinja`,
`--chat-template-kwargs '{"enable_thinking": false}'`, `--reasoning off`,
`--reasoning-budget 0`, `-ngl all`, `--ctx-size 40960`, `--parallel 1`,
`--flash-attn on`, `--batch-size 2048`,
and `--ubatch-size 512`. `--skip-chat-parsing` is off by default so the model
chat template remains active.
The ImGui panel exposes a `GPU layers all` toggle for literal `-ngl all` mode;
turn it off only when you need a fixed numeric layer count.

Keep `--parallel 1` for a single Codex session when you want the full 40960
token window available to one request. Raise it only when you expect concurrent
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
model_context_window = 40960
model_auto_compact_token_limit = 30000
tool_output_token_limit = 5000

[model_providers.llama_cpp]
name = "llama.cpp local"
base_url = "http://127.0.0.1:8001/v1"
wire_api = "responses"
stream_idle_timeout_ms = 10000000

[profiles.ofxggml_local]
model = "local/GLM-4.7-Flash-UD-Q4_K_XL"
model_provider = "llama_cpp"

[features.multi_agent_v2]
enabled = true
max_concurrent_threads_per_session = 1
min_wait_timeout_ms = 2500
max_wait_timeout_ms = 120000
default_wait_timeout_ms = 30000
usage_hint_enabled = false
hide_spawn_agent_metadata = true
non_code_mode_only = true

[agents]
max_depth = 1

[agents.explorer]
description = "Fast read-only codebase questions for local llama.cpp sessions."
config_file = "ofxggml/agents/local-explorer.toml"
nickname_candidates = ["Scout", "Trace"]

[agents.worker]
description = "Bounded code edits with focused validation for local llama.cpp sessions."
config_file = "ofxggml/agents/local-worker.toml"
nickname_candidates = ["Patch", "Build"]
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
It also includes `codex-agents/local-explorer.toml` and
`codex-agents/local-worker.toml`. The example's auto-config writer creates
matching files under your Codex home at `ofxggml/agents/` before it references
them from `[agents.explorer]` and `[agents.worker]`. Those role files repeat
the same max-agent cap so spawned explorer/worker sessions stay inside the
local server budget.
The example's **Launch Codex** button uses the same custom-provider contract:

```powershell
codex --no-alt-screen -p ofxggml_local `
    --disable apps --disable image_generation --disable browser_use --disable computer_use --disable tool_search `
    -c model_provider=llama_cpp `
    -c model_context_window=40960 `
    -c model_auto_compact_token_limit=30000 `
    -c tool_output_token_limit=5000 `
    -c features.multi_agent_v2.enabled=true `
    -c features.multi_agent_v2.max_concurrent_threads_per_session=1 `
    -c features.multi_agent_v2.min_wait_timeout_ms=2500 `
    -c features.multi_agent_v2.max_wait_timeout_ms=120000 `
    -c features.multi_agent_v2.default_wait_timeout_ms=30000 `
    -c agents.max_depth=1 `
    --model local/GLM-4.7-Flash-UD-Q4_K_XL
```

The agent defaults are intentionally conservative for local GGUF models:
`max_concurrent_threads_per_session = 1` keeps Codex from spawning extra
subagent work against a single local `llama-server`, and `agents.max_depth = 1`
keeps delegation shallow. Raise the session thread count only when the model,
VRAM, and server `--parallel` value can handle concurrent requests. If you turn
off `multi_agent_v2`, use `agents.max_threads = 1` for the same legacy fanout
cap. The helper scripts also accept `-MaxAgents` or `-AgentMaxAgents` as aliases
for the upstream max-concurrent setting.

The Codex executable path is detected automatically from `OFXGGML_CODEX_EXE`,
Codex Desktop's `%LOCALAPPDATA%\OpenAI\Codex\bin\codex.exe`, or `where codex`.
The file picker is only needed for unusual installs.

Do not add `--oss` for this llama.cpp path. Codex's built-in OSS shortcut is
for built-in local providers such as Ollama or LM Studio; this example uses the
explicit `llama_cpp` OpenAI-compatible provider configured above.
The disable flags keep Codex from sending non-function Responses tools such as
app namespaces, image generation, browser, or web-search tools; llama.cpp
accepts the function-tool shape used by shell and patch tools.

Optional environment overrides:

```powershell
$env:OFXGGML_CODEX_BASE_URL = "http://127.0.0.1:8001/v1"
$env:OFXGGML_CODEX_MODEL = "local/GLM-4.7-Flash-UD-Q4_K_XL"
$env:OFXGGML_CODEX_PRESET = "balanced"
$env:OFXGGML_TEXT_MODEL = "C:\path\to\model.gguf"
$env:OFXGGML_CODEX_EXE = "C:\Users\you\AppData\Local\OpenAI\Codex\bin\codex.exe"
$env:OFXGGML_CODEX_GPU_LAYERS = "all"
$env:OFXGGML_CODEX_CONTEXT_SIZE = "40960"
$env:OFXGGML_CODEX_PARALLEL = "1"
$env:OFXGGML_CODEX_FLASH_ATTN = "1"
$env:OFXGGML_CODEX_BATCH_SIZE = "2048"
$env:OFXGGML_CODEX_UBATCH_SIZE = "512"
$env:OFXGGML_CODEX_MODEL_CONTEXT_WINDOW = "40960"
$env:OFXGGML_CODEX_AUTO_COMPACT_TOKEN_LIMIT = "30000"
$env:OFXGGML_CODEX_TOOL_OUTPUT_TOKEN_LIMIT = "5000"
$env:OFXGGML_CODEX_MULTI_AGENT_V2 = "1"
$env:OFXGGML_CODEX_AGENT_MAX_CONCURRENT_THREADS = "1"
$env:OFXGGML_CODEX_AGENT_MAX_DEPTH = "1"
$env:OFXGGML_CODEX_AGENT_MIN_WAIT_MS = "2500"
$env:OFXGGML_CODEX_AGENT_MAX_WAIT_MS = "120000"
$env:OFXGGML_CODEX_AGENT_DEFAULT_WAIT_MS = "30000"
$env:OFXGGML_CODEX_TEMP = "1.0"
$env:OFXGGML_CODEX_TOP_P = "0.95"
$env:OFXGGML_CODEX_MIN_P = "0.01"
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
smoke result, local Codex provider snippet, and editable startup options. It
starts the local server when possible and can automatically write the needed
provider/profile sections into the local Codex config if
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
