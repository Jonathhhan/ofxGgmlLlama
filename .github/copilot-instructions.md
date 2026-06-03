# GitHub Copilot Repository Instructions

ofxGgmlLlama is part of the ofxGgml openFrameworks addon ecosystem.

- Scope: llama.cpp tooling, text/chat/embedding examples, and local model adapters
- Keep changes inside this addon's lane unless a task explicitly asks for a cross-addon update.
- For ecosystem planning tasks, prefer instruction, documentation, workflow, and validation changes before addon source changes.
- Use ofxGgmlCore as the default shared ggml/runtime base for companion addons and keep companion workflows out of Core.
- Avoid committing generated outputs, local models, build directories, IDE metadata, downloaded runtimes, caches, or media dumps.
- Use openFrameworks ofLogNotice, ofLogWarning, ofLogError, or module-scoped ofLog(...) for addon runtime/example logging; keep raw stdout/stderr only for tests and CLI tools with machine-readable output contracts.
- Add or update headless tests for public helper behavior.
- Validation before handoff: scripts\validate-local.ps1.
- Keep explanations concise and include the files and checks that matter.
