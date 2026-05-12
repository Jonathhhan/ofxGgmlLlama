# Changelog

## Unreleased

- Renamed examples to Project Generator-safe folders: `example-text`,
  `example-chat`, and `example-emb`.
- Made addon source lists explicit so generated Visual Studio projects do not
  pull CMake build-cache sources from dependency folders.
- Reduced the public script surface to server/model/validation commands plus
  unified `build-example` and `run-example` entrypoints.

## v1.0.1 - 2026-05-12

- Added independent `ofxGgmlLlama` version metadata.
- Moved concrete llama.cpp adapters into `ofxGgmlLlama`.
- Added migration, release checklist, and release policy docs.
- Added validation coverage for launch helpers and release checklist script
  references.
- Added and exercised a release-candidate gate for pre-tag checks.

Use `docs/RELEASE_NOTES_TEMPLATE.md` when preparing a tagged release.
