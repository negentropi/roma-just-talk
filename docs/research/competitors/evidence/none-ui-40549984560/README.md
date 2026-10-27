# UI retry blocked before execution

[Run 40549984560](https://github.com/negentropi/roma-just-talk/actions/runs/40549984560), exact head `5bf8e4df18d3e38756a431122b5fa98208daeb2c`, failed at the matched driver prebuild check: `Baseline dependency declarations differ`. Zero baseline or candidate XCTest cases ran. No foreground, pointer, profile persistence or shared-sheet verdict exists for this retry.

The census treated every tracked `*/Package.swift` as a build declaration. Two newly retained Ollama probe manifests under `docs/research/competitors/evidence/ollama-identity-40545355522/native/{baseline,candidate}/package/Package.swift` exist only in the candidate. Actual app/product declarations and `project.pbxproj` are unchanged. The owning driver needs a census of real build-input roots that still rejects actual declaration drift.

Reproduce the exact source distinction from the repository root: `python3 docs/research/competitors/evidence/none-ui-40549984560/analyze-declarations.py`. It reads immutable baseline and candidate Git objects without checking out or editing either revision. `declaration-census.json` retains its output.

`source-bindings.json` pins the UI oracle (`9bbf692…`), driver, workflow and canonical lock; the nine production UI files are byte-identical to the previous candidate `830d452…`. `ci-failed-log.txt` is the failed step log fetched once. The small artifact was listed but not downloaded because this failure preceded builds, permission grants and application launches.
