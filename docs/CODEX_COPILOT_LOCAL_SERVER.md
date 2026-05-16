# Codex and Copilot Local Llama Server

This guide belongs in `ofxGgmlLlama` because it is llama.cpp setup, GGUF model
download, and `llama-server` lifecycle guidance. `ofxGgmlAgents` should consume
the resulting OpenAI-compatible endpoint, not own the model runtime setup.

Use this path when Codex, GitHub Copilot, Hermes Agent, or another coding
assistant needs a local llama.cpp server.

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
    --alias "unsloth/GLM-4.7-Flash" \
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
    -GpuLayers 999 `
    -ContextSize 131072
```

The addon wrapper intentionally exposes a conservative common subset of
`llama-server` flags. Use the direct upstream command when you need advanced
flags such as KV cache quantization, `--kv-unified`, custom batch sizes, or
explicit sampling defaults for a coding-agent session.

## Wire Codex or Copilot

Point any client that supports an OpenAI-compatible local endpoint at:

```text
http://127.0.0.1:8001/v1
```

Use the model alias configured on the server, for example:

```text
unsloth/GLM-4.7-Flash
```

For Codex, this alias is not just display text. The profile `model` value must
match the llama-server alias. In `ofxGgmlLlamaCodexLocalExample`, that alias is
the editable `ServerModel` field. If you start the server with
`-ServerModel local/qwen2.5-coder-1.5b`, the Codex profile must use
`model = "local/qwen2.5-coder-1.5b"`.

For Codex, the local config shape is:

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

Check the exact profile invocation against your installed Codex version.

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
```

With a compatible model available, run a real smoke:

```powershell
scripts\run-llama-runtime-smoke.bat -Backend cuda -Json -SummaryOnly
```

Use `-Backend cpu` when validating a CPU-only install.
