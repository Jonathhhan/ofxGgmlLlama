# AGENTS.md

This repository is `ofxGgmlLlama`, the text/chat/embedding companion addon for the ofxGgml family.

Codex should treat `ofxGgmlCore` as the shared backend-neutral foundation. This repo owns llama.cpp server/CLI integration, text generation, chat, embeddings, and Llama-specific examples.

## Addon contract

Do:

- keep Llama-specific workflows in this addon
- depend on shared primitives from `ofxGgmlCore` where practical
- preserve openFrameworks addon layout and `addon_config.mk`
- keep examples projectGenerator-friendly
- document model paths clearly
- update scripts/docs/examples together with behavior changes

Do not:

- move backend-neutral Core primitives into this repo
- commit models, generated builds, binaries, or downloaded caches
- hardcode local absolute paths
- silently break Windows/macOS/Linux script parity

## Codex workflow

1. Inspect README, docs, scripts, `addon_config.mk`, examples, and relevant `src/` files first.
2. Propose the smallest implementation plan before editing.
3. Keep diffs focused.
4. Preserve Core vs companion-addon boundaries.
5. Update examples/docs/scripts with code changes.
6. Summarize validation honestly.
