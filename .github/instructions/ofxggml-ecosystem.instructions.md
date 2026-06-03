---
applyTo: "**"
---

# ofxGgml Ecosystem Instructions

- Repository: ofxGgmlLlama.
- Lane: text, chat, embeddings.
- Scope: llama.cpp tooling, text/chat/embedding examples, and local model adapters.
- Treat this file as a focused Copilot cloud agent and code review guardrail for ecosystem work.
- For Codex, Copilot, or Hermes integration tasks, start with the Core readiness pass: ..\ofxGgmlCore\scripts\check-ecosystem-readiness.ps1.
- If the readiness pass is too broad for the task, generate a planning handoff first: ..\ofxGgmlCore\scripts\plan-ecosystem.ps1.
- Work in instruction, documentation, workflow, validation, or planning files before addon source when the task is about the ecosystem or coding agents.
- Do not edit addon runtime behavior unless the user explicitly asks for addon behavior.
- Keep companion changes inside this repository's lane and use ofxGgmlCore as the default shared ggml/runtime base.
- Preserve generated artifact hygiene: no binaries, build folders, IDE metadata, model weights, downloaded runtimes, caches, media dumps, or memory indexes.
- Use openFrameworks ofLogNotice, ofLogWarning, ofLogError, or module-scoped ofLog(...) for addon runtime/example logging; keep raw stdout/stderr only for tests and CLI tools with machine-readable output contracts.
- Validate before handoff with scripts\validate-local.ps1; for cross-repo planning also report the Core readiness or planning command used.
