# Roadmap

## Current Milestone

- Seed companion addon from the working core llama workflow.
- Keep text, chat, and embedding examples root-level.
- Keep `ofxGgmlCore` as the only required addon dependency.
- Preserve Windows `.bat`, PowerShell, and macOS/Linux shell wrappers.

## Next Milestones

- Move llama.cpp-specific C++ adapter implementations out of `ofxGgmlCore` once
  downstream examples build cleanly through this companion.
- Add focused tests for script path resolution and model discovery.
- Add a small release checklist for `clone -> build-llama-server -> run chat`.
- After the split settles, simplify `ofxGgmlCore` docs so llama is referenced
  only as this companion addon.
