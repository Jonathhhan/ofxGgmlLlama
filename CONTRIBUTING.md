# Contributing

`ofxGgmlLlama` is a companion addon. Keep llama.cpp-specific workflow code here
and keep generic ggml/runtime primitives in `ofxGgmlCore`.

Before changing public API or scripts:

- keep `ofxGgmlLlama` depending on `ofxGgmlCore`, never the reverse
- keep examples focused and copyable
- keep generated llama.cpp sources, builds, runtime binaries, models, and IDE
  projects out of git
- update docs when command behavior changes

Run local validation before pushing:

```powershell
scripts\validate-local.bat
```
