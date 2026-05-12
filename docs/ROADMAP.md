# Roadmap

## Current Milestone

- Seed companion addon from the working core llama workflow.
- Keep text, chat, and embedding examples root-level.
- Keep `ofxGgmlCore` as the only required addon dependency.
- Preserve Windows `.bat`, PowerShell, and macOS/Linux shell wrappers.
- Move llama.cpp-specific C++ adapter implementations out of `ofxGgmlCore`.

## Next Milestones

- Add focused tests for script path resolution and model discovery.
- Add a small release checklist for `clone -> build-llama-server -> run chat`.
- Add migration notes for projects that previously included Core llama adapter
  headers directly.
