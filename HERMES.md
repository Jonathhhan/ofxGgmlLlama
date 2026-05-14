# Hermes Project Context

This repository is part of the ofxGgml openFrameworks addon ecosystem.

## Repository

- Addon: ofxGgmlLlama
- Lane: text, chat, embeddings
- Scope: llama.cpp tooling, text/chat/embedding examples, and local model adapters

## Hermes Agent Rules

- Treat this file as project context for Hermes Agent.
- Read README.md, addon_config.mk, docs, scripts, and tests before changing behavior.
- Keep changes inside this repository's lane unless the task explicitly requires cross-repo coordination.
- For ecosystem improvement work, create or update a plan before touching addon source.
- Keep ofxGgmlCore as the shared base; companion addons may depend on Core, but Core must not depend on companions.
- Do not commit generated binaries, model files, downloaded runtimes, build folders, IDE metadata, memory indexes, caches, or media dumps.
- Use openFrameworks ofLogNotice, ofLogWarning, ofLogError, or module-scoped ofLog(...) for addon runtime/example logging; keep raw stdout/stderr only for tests and CLI tools with machine-readable output contracts.
- Prefer small, validated changes over broad refactors.
- Validation before handoff: scripts\validate-local.ps1.

## Planning Workflow

- Use scripts\status-family.ps1 and scripts\plan-ecosystem.ps1 from ofxGgmlCore for cross-repo planning.
- Classify each task as documentation, automation, validation, or addon-code work.
- Work in the agent layer first when the goal is better Codex, Copilot, or Hermes planning.
- Touch addon source only when the user explicitly asks for addon behavior.

## Ecosystem Split

Model-specific workflows belong in companion addons. Shared helpers should move
to ofxGgmlCore only when they are stable, domain-neutral, dependency-light, and
covered by focused tests.
