# Llama Workflow Boundaries

`ofxGgmlLlama` owns llama.cpp-backed text, chat, embedding, and server
lifecycle workflows for the ofxGgml ecosystem. This document is for Codex,
GitHub Copilot, Hermes Agent, and human contributors planning llama-lane work
before changing runtime behavior.

This guide follows the split rule from the legacy/reference `ofxGgml` docs:
workflow-specific process management, model discovery, example UX, and heavy
optional runtime setup belong in companion addons. Shared code should move down
only when it is stable, domain-neutral, dependency-light, and covered by
focused tests.

## Owned workflow surface

This addon may define:

- llama.cpp build, setup, and server lifecycle scripts
- CLI fallback text generation adapters
- `llama-server` text generation and chat workflows
- `llama-server` embedding workflows
- model discovery helpers for GGUF files used by llama.cpp
- focused text, chat, and embedding examples
- migration docs for projects moving from Core-hosted llama adapters

## Not owned here

Keep these responsibilities out of `ofxGgmlLlama`:

- ggml setup, backend selection, and runtime discovery owned by `ofxGgmlCore`
- audio, vision, video, diffusion, segmentation, music, RAG, or agent UX
- committed GGUF model files, generated server binaries, logs, caches, or
  generated openFrameworks project files
- reusable GitHub Actions policy owned by `ofxGgmlWorkflows`
- generic text or embedding request/result types that belong in `ofxGgmlCore`

## Planning handoff

Before changing llama behavior, write down:

```text
Workflow:
Backend path:
Model file:
Server port:
Generated local artifacts:
User-visible output:
Out of scope:
Validation:
```

Runtime changes should name whether the path uses CLI fallback, server text,
server chat, or server embeddings, and should identify which local server,
model, and generated artifacts are required.

## Validation ladder

Use the smallest command that proves the changed layer:

| Change type | Suggested validation |
| --- | --- |
| Docs or planning only | `scripts\validate-local.bat` |
| Model discovery helpers | `scripts\list-models.bat` |
| Server lifecycle scripts | `scripts\doctor-llama.bat` |
| Example launch path | `scripts\dev\test-launch-dry-run.bat` |
| Generated project repair | `scripts\dev\test-example-project-repair.ps1` |
| Adapter behavior | `scripts\dev\test-addon.bat` |

## Safe first tasks

Good early llama-lane tasks are:

- documenting CLI versus server behavior
- improving dry-run coverage for model and server discovery
- clarifying which examples expect which server port
- keeping migration notes current with Core and companion boundaries
- adding focused tests around adapter error handling

Avoid broadening runtime behavior until the backend path, model file, server
port, generated artifacts, and validation command are explicit.
