# OpenCode Local Llama Server

This guide connects OpenCode to the same local `llama-server` endpoint used by
`ofxGgmlLlamaCodexLocalExample`.

OpenCode supports custom OpenAI-compatible providers through
`@ai-sdk/openai-compatible`. Keep that integration in this addon as config,
documentation, and validation only: llama.cpp runtime setup stays here, while
OpenCode owns its own tool loop, agents, permissions, and project session state.

## Start the local endpoint

Use the Codex local example or the addon server script:

```powershell
scripts\run-example.bat codex -Build -CodexPreset quality
```

or:

```powershell
scripts\start-llama-server.bat `
    -ModelPath ..\models\unsloth\GLM-4.7-Flash-GGUF\GLM-4.7-Flash-UD-Q4_K_XL.gguf `
    -Port 8001 `
    -Alias local/GLM-4.7-Flash-UD-Q4_K_XL `
    -GpuLayers all `
    -ContextSize 65536 `
    -ChatTemplateKwargs '{"enable_thinking": false}' `
    -Reasoning off `
    -ReasoningBudget 0 `
    -CacheReuse 256 `
    -Jinja
```

The important OpenCode values are:

```text
baseURL: http://127.0.0.1:8001/v1
provider id: llama_cpp
model id: local/GLM-4.7-Flash-UD-Q4_K_XL
full OpenCode model: llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL
```

If `/v1/models` advertises exactly one model and it differs from your requested
alias, use the advertised id in the OpenCode config. A truthful model alias is
more useful than a pretty one when you are debugging local coding sessions.

## Plan the OpenCode config

The planner is read-only. It checks the endpoint, the advertised model ids, the
OpenCode executable if installed, and the config path that OpenCode will likely
use:

```powershell
scripts\plan-local-opencode.bat -SummaryOnly
scripts\plan-local-opencode.bat -Endpoint http://127.0.0.1:8001/v1 -Model local/GLM-4.7-Flash-UD-Q4_K_XL -Json -SummaryOnly
scripts\plan-local-opencode.bat -UseServedModel -Json -SummaryOnly
```

It prints a complete `opencode.json` snippet. On Windows, the default global
config path is still the OpenCode path `~\.config\opencode\opencode.json`;
project-local `opencode.json` files override global provider settings.

## Configure OpenCode

This folder includes:

```text
ofxGgmlLlamaCodexLocalExample\opencode.example.json
```

Use that file as a starting point for either:

```text
~\.config\opencode\opencode.json
```

or a project-local:

```text
opencode.json
```

Minimal provider shape:

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
        "apiKey": "local",
        "timeout": 600000,
        "chunkTimeout": 60000
      },
      "models": {
        "local/GLM-4.7-Flash-UD-Q4_K_XL": {
          "name": "GLM-4.7 Flash local",
          "limit": {
            "context": 65536,
            "output": 8000
          }
        }
      }
    }
  },
  "disabled_providers": ["openai", "anthropic", "gemini"]
}
```

The full model string is `provider_id/model_id`. For this addon default, that
means `llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL`.

## Agent settings

OpenCode has primary agents such as `build` and `plan`, plus subagents such as
`explore`. The example config pins those agents to the local model, uses
`build` as the default primary agent, allows read/search tools, asks before
edits, shell commands, or primary-agent task delegation, and denies web access
for a predictable local loop:

```json
{
  "agent": {
    "build": {
      "mode": "primary",
      "model": "llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL",
      "permission": {
        "read": "allow",
        "glob": "allow",
        "grep": "allow",
        "list": "allow",
        "edit": "ask",
        "bash": "ask",
        "task": "ask",
        "external_directory": "ask",
        "webfetch": "deny",
        "websearch": "deny"
      }
    },
    "plan": {
      "mode": "primary",
      "model": "llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL",
      "permission": {
        "read": "allow",
        "glob": "allow",
        "grep": "allow",
        "list": "allow",
        "edit": "deny",
        "bash": "ask",
        "task": "ask",
        "external_directory": "ask",
        "webfetch": "deny",
        "websearch": "deny"
      }
    },
    "explore": {
      "mode": "subagent",
      "model": "llama_cpp/local/GLM-4.7-Flash-UD-Q4_K_XL",
      "permission": {
        "read": "allow",
        "glob": "allow",
        "grep": "allow",
        "list": "allow",
        "edit": "deny",
        "bash": "ask",
        "task": "deny",
        "external_directory": "ask",
        "webfetch": "deny",
        "websearch": "deny"
      }
    }
  }
}
```

Unlike Codex, this addon does not write OpenCode agent files automatically.
OpenCode supports `.opencode/agents/` and `~/.config/opencode/agents/`, but JSON
agent config is enough for the local llama.cpp route.

## Performance notes

For one local coding session, keep the server at `--parallel 1` and match
OpenCode's `limit.context` to the server `--ctx-size`. Raise `--parallel` only
when you expect concurrent OpenCode sessions or subagent work and your GPU has
headroom.

Use `-GpuLayers all` on CUDA/Metal systems when the model fits. Reduce context,
batch, or GPU layers only when the server fails to load or the machine starts
swapping.

Keep `--reasoning off` and `--chat-template-kwargs '{"enable_thinking": false}'`
for GLM-style local coding sessions unless you intentionally want model-side
thinking tokens in the response stream.

## Validate

Before launching OpenCode:

```powershell
scripts\doctor-llama.bat
scripts\list-models.bat -Json -SummaryOnly
scripts\plan-local-opencode.bat -SummaryOnly
```

Then inside OpenCode, run `/models` and select the `llama.cpp local` provider.

## References

- OpenCode provider docs: https://opencode.ai/docs/providers
- OpenCode config docs: https://opencode.ai/docs/config
- OpenCode agents docs: https://opencode.ai/docs/agents
