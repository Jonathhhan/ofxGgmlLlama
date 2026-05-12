# Release Checklist

Use this before tagging or announcing an `ofxGgmlLlama` release. The goal is to
prove the new-user path without relying on local generated state.

## Fresh Clone Layout

From the openFrameworks `addons` folder:

```powershell
git clone https://github.com/Jonathhhan/ofxGgmlCore.git
git clone https://github.com/Jonathhhan/ofxGgmlLlama.git
cd ofxGgmlLlama
```

Expected layout:

```text
addons/
  ofxGgmlCore/
  ofxGgmlLlama/
  ofxImGui/
```

## Build Runtime Tools

Windows:

```powershell
scripts\build-llama-server.bat
```

macOS/Linux:

```sh
./scripts/build-llama-server.sh
```

Expected result:

```text
libs/llama/bin/llama-server
libs/llama/bin/llama-cli
libs/llama/bin/llama-embedding
```

On Windows the files use `.exe`.

## Model Placement

Put GGUF files in one of these locations:

```text
addons/models/
addons/ofxGgmlLlama/models/
```

Then verify discovery:

```powershell
scripts\list-models.bat
```

macOS/Linux:

```sh
./scripts/list-models.sh
```

## Run Examples

Text:

```powershell
scripts\run-text-example.bat -Build -Model C:\path\to\model.gguf
```

Chat:

```powershell
scripts\run-chat-example.bat -Build -Model C:\path\to\model.gguf
```

Embeddings:

```powershell
scripts\run-embedding-example.bat -Build -Model C:\path\to\embedding-model.gguf
```

For macOS/Linux, use the matching `.sh` scripts.

Expected behavior:

- text and chat start or connect to `llama-server` on `http://127.0.0.1:8080`
- embeddings start or connect to embedding mode on `http://127.0.0.1:8081`
- examples open with an editable UI and no missing-addon errors
- cancel/streaming controls work for server-backed text and chat

## Local Validation

Run the full local validation suite:

```powershell
scripts\validate-local.bat
```

macOS/Linux:

```sh
./scripts/validate-local.sh
```

This checks addon layout, generated artifact hygiene, launch helper behavior,
launch dry-runs, and headless C++ tests.

For a pre-tag release candidate gate, run:

```powershell
scripts\release-candidate.bat
```

macOS/Linux:

```sh
./scripts/release-candidate.sh
```

## Before Tagging

- `git status --short --ignored` shows only expected ignored build outputs
- no GGUF models, llama.cpp source/build trees, binaries, or generated OF
  project files are staged
- `docs/MIGRATION.md` matches the current Core/Llama boundary
- `docs/RELEASE_POLICY.md` matches the intended tag and compatibility policy
- `docs/RELEASE_NOTES_TEMPLATE.md` has been copied into the release notes
- `CHANGELOG.md` has an entry for the release
- `README.md` first-run commands still match the scripts
