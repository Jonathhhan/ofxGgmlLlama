# Roadmap

## Done

- Seed companion addon from the working core llama workflow.
- Keep text, chat, and embedding examples root-level.
- Keep `ofxGgmlCore` as the only required addon dependency.
- Preserve Windows `.bat`, PowerShell, and macOS/Linux shell wrappers.
- Move llama.cpp-specific C++ adapter implementations out of `ofxGgmlCore`.
- Add focused tests for script path resolution and model discovery.
- Add migration notes for projects that previously included Core llama adapter
  headers directly.
- Add a small release checklist for `clone -> build-llama-server -> run chat`.
- Add focused tests for release checklist command examples.
- Decide whether release tags should be mirrored across Core and companion
  addons or remain per-addon.
- Add version constants for public releases.
- Add changelog/release-note template.
- Exercise one full release candidate pass before tagging.
- Run the committed release candidate gate on a clean tracked working tree.
- Prepare v1.0.1 release notes from `docs/RELEASE_NOTES_TEMPLATE.md`.

## Next Milestones

- Tag v1.0.1 after the release notes are reviewed.
