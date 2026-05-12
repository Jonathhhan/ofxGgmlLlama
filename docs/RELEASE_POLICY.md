# Release Policy

`ofxGgmlLlama` releases are tagged independently from `ofxGgmlCore` and the
other companion addons.

## Tagging

Use per-addon semantic version tags:

```text
v1.0.0
v1.0.1
v1.1.0
```

Do not mirror tags across the whole addon family unless that addon changed and
passed its own release checklist. The family can move at different speeds.

## Compatibility

Document the minimum compatible `ofxGgmlCore` version in the release notes when
publishing a Llama release.

For normal development:

- patch releases should not require Core API changes
- minor releases may require a newer Core minor version
- breaking API changes should use a major version bump

## Release Notes

Each release note should include:

- tested openFrameworks version
- minimum `ofxGgmlCore` version or commit
- llama.cpp revision used by `scripts/build-llama-server.*`
- supported local backends tested for the runtime tools
- validation command result

## Pre-Release Gate

Before tagging:

1. Run `scripts\validate-local.bat` on Windows.
2. Run `./scripts/validate-local.sh` on macOS or Linux when available.
3. Complete `docs/RELEASE_CHECKLIST.md`.
4. Confirm no generated artifacts or models are staged.
