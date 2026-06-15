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

## Start llama-server for Codex

Use port `8001` for coding-agent sessions so the text/chat/embedding examples
can keep their default ports.

```powershell
scripts\start-llama-server.bat `
    -ModelPath ..\models\unsloth\GLM-4.7-Flash-GGUF\GLM-4.7-Flash-UD-Q4_K_XL.gguf `
    -Port 8001 `
    -GpuLayers 999 `
    -ContextSize 131072
```

For advanced llama.cpp flags such as KV-cache quantization, batch sizing,
`--kv-unified`, or explicit sampling defaults, run `llama-server` directly from
the built runtime and keep the same OpenAI-compatible endpoint:

```text
http://127.0.0.1:8001/v1
```

## Configure Codex

Create or edit your local Codex config:

```text
%USERPROFILE%\.codex\config.toml
```

Use this provider/profile shape:

```toml
[model_providers.llama_cpp]
name = "llama.cpp local"
base_url = "http://127.0.0.1:8001/v1"
wire_api = "responses"
stream_idle_timeout_ms = 10000000

[profiles.ofxggml_local]
model = "unsloth/GLM-4.7-Flash"
model_provider = "llama_cpp"
```

This folder includes `codex-config.example.toml` with the same starting point.
Check the exact profile invocation against your installed Codex version.

## Run this example

Generate the project with openFrameworks projectGenerator using addons
`ofxGgmlLlama`, `ofxGgmlCore`, and `ofxImGui`, or use the helper:

```powershell
scripts\run-example.bat codex -Build
```

Optional environment overrides:

```powershell
$env:OFXGGML_CODEX_BASE_URL = "http://127.0.0.1:8001/v1"
$env:OFXGGML_CODEX_MODEL = "unsloth/GLM-4.7-Flash"
```

The example displays the exact endpoint, model alias, local Codex provider
snippet, and validation commands. It does not edit Codex config or start an
agent automatically.

## Validate

Before giving the endpoint to Codex:

```powershell
scripts\doctor-llama.bat
scripts\list-models.bat
scripts\run-llama-runtime-smoke.bat -Backend cuda -Json -SummaryOnly
```

Use `-Backend cpu` for CPU-only validation.

From `ofxGgmlCore`, the local Codex readiness planner checks config and endpoint
visibility without mutating files:

```powershell
cd ..\ofxGgmlCore
scripts\plan-local-codex.bat -Endpoint http://127.0.0.1:8001/v1 -Json -SummaryOnly
```

Keep model weights, downloaded runtimes, generated project files, logs, local
Codex config, and caches out of git.
