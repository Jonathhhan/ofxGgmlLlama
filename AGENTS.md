# Codex Repository Instructions

This repository is part of the ofxGgml openFrameworks addon ecosystem.

## Addon Scope

- Addon: ofxGgmlLlama
- Lane: text, chat, embeddings
- Role: llama.cpp tooling, text/chat/embedding examples, and local model adapters

## Working Rules

- Read the existing code and docs before changing behavior.
- Keep edits scoped to this addon's lane and preserve the companion-addon split.
- Start with an ecosystem plan when a task asks for cross-repo improvement or planning.
- Use ofxGgmlCore as the default shared ggml/runtime base for companion addons; do not add reverse dependencies from Core to companion addons.
- Do not commit generated project files, binaries, model weights, downloaded runtimes, sample media dumps, memory indexes, or caches.
- Prefer focused tests and local validation over broad refactors.
- Use openFrameworks ofLogNotice, ofLogWarning, ofLogError, or module-scoped ofLog(...) for addon runtime/example logging; keep raw stdout/stderr only for tests and CLI tools with machine-readable output contracts.
- Preserve openFrameworks-style public names and document intentional breaking changes.

## Validation

Validation before handoff: scripts\validate-local.ps1.

For ecosystem planning work, run scripts\plan-ecosystem.ps1 from ofxGgmlCore
before proposing addon-code changes.

## Ecosystem Notes

Model-specific UX belongs in companion addons. Shared code should move down into
ofxGgmlCore only after it is stable, domain-neutral, dependency-light, and
covered by focused tests.
## Local Codex and Subagents

- Use normal git branches for Codex work in this checkout; do not introduce or rely on additional git worktrees for addon tasks.
- Local Codex provider wiring is llama.cpp-only. Do not add alternate local-provider routes, legacy local-provider scripts/docs, or `--oss` launch paths.
- Keep local Codex configs aligned on `model_provider = "llama_cpp"`, the local OpenAI-compatible llama-server `/v1` endpoint, and the served model alias used by the example.
- MCP-spawned Codex threads must keep their cwd inside this addon checkout or an explicitly allowed addon subpath.
- Use subagents for explicit sidecar work, especially read-heavy exploration. Give worker agents narrow, disjoint file ownership before allowing writes.
- Gate spawned-agent results with the local run contract when they modify files: scripts\check-local-agent-run.ps1.
- Keep generated Codex role/config writes reviewable and opt-in; avoid silently overwriting user-edited global Codex settings.
