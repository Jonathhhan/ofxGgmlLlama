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
    -Model ..\models\unsloth\GLM-4.7-Flash-GGUF\GLM-4.7-Flash-UD-Q4_K_XL.gguf `
    -ServerModel unsloth/GLM-4.7-Flash `
    -GpuLayers 999 `
    -ContextSize 131072 `
    -Temperature 1.0 `
    -TopP 0.95 `
    -MinP 0.01 `
    -NoCudaGraphs
```

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
model = "unsloth/GLM-4.7-Flash"
model_provider = "llama_cpp"
web_search = "disabled"

[model_providers.llama_cpp]
name = "llama.cpp local"
base_url = "http://127.0.0.1:8001/v1"
wire_api = "responses"
stream_idle_timeout_ms = 10000000

[profiles.ofxggml_local]
model = "unsloth/GLM-4.7-Flash"
model_provider = "llama_cpp"
web_search = "disabled"
```

`profiles.ofxggml_local.model` must match the llama-server alias used by the
example's `ServerModel` field. The alias is not proof of which GGUF is loaded:
`llama-server` can serve a Qwen file while advertising a GLM alias if you pass
the wrong `--alias`. If you do not pass `-ServerModel` and do not set
`OFXGGML_CODEX_MODEL`, the launcher now derives a truthful alias from the GGUF
filename, such as `local/qwen2.5-coder-1.5b-instruct-q4_k_m`. If you launch a
smaller local Qwen model with `-ServerModel local/qwen2.5-coder-1.5b`, use this
profile instead:

```toml
[profiles.ofxggml_local]
model = "local/qwen2.5-coder-1.5b"
model_provider = "llama_cpp"
web_search = "disabled"
```

This folder includes `codex-config.example.toml` with the same starting point.
The example's **Launch Codex** button uses the same custom-provider contract:

```powershell
codex --no-alt-screen -p ofxggml_local `
    --disable apps --disable image_generation --disable browser_use --disable computer_use --disable tool_search `
    -c web_search='"disabled"' `
    -c model_provider=llama_cpp `
    --model unsloth/GLM-4.7-Flash
```

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
$env:OFXGGML_CODEX_MODEL = "unsloth/GLM-4.7-Flash"
$env:OFXGGML_TEXT_MODEL = "C:\path\to\model.gguf"
$env:OFXGGML_CODEX_EXE = "C:\Users\you\AppData\Local\OpenAI\Codex\bin\codex.exe"
$env:OFXGGML_CODEX_GPU_LAYERS = "999"
$env:OFXGGML_CODEX_CONTEXT_SIZE = "131072"
$env:OFXGGML_CODEX_TEMP = "1.0"
$env:OFXGGML_CODEX_TOP_P = "0.95"
$env:OFXGGML_CODEX_MIN_P = "0.01"
$env:OFXGGML_CODEX_AUTO_SERVER = "1"
$env:OFXGGML_CODEX_AUTO_CONFIG = "1"
$env:OFXGGML_CODEX_NO_CUDA_GRAPHS = "0"
$env:OFXGGML_CODEX_SKIP_CHAT_PARSING = "1"
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
scripts\test-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Model unsloth/GLM-4.7-Flash -Json -SummaryOnly
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
