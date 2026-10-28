# Current English language selection probe

Question: with English supplied only by registered defaults, does choosing the already displayed **English** item in the real Models language picker persist an explicit English choice? Light cleanup requires that persistent choice. The same-value handler writes it when called; source inspection does not establish SwiftUI Picker dispatch.

## Observed result

The [actual hosted check](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/language-selection-40617652407/README.md) passed: after mounting with persistent language absent, selecting the already checked English item saved `en`. Japanese → English controls and fresh Light captures also passed. No production UI change is indicated by this component result. The first setup run was canceled after cache saving; it provides no picker result.

## Frozen boundary

A separate test-only app entry hosts the unchanged `LanguageSelectionView(displayMode: .full)`. It constructs the real Whisper, FluidAudio and transcription model managers, selects the real registry `ggml-tiny` metadata through `setDefaultTranscriptionModel`, and retains them. No engine, provider request, model refresh, model weights, inference or download. Only the production app entry point is excluded from the disposable compile tree; product sources stay unchanged.

Claude Opus 5.5 authors the new host view; GPT-6.1 Sol reviews it. New oracle/driver/workflow files leave the existing Undo control check untouched. One cached hosted Mac build uses the existing canonical package locks and static Whisper linkage. Compilation of dependencies is not speech execution.

## Observation and controls

1. Fresh isolated preferences; register `AppDefaults.registeredDefaults`, remove only persistent `SelectedLanguage`, mount the actual full view. After mounting, require registered/effective English, persistent key absent, no argument override, real multilingual Whisper model, and actual picker facts containing English and Japanese. Mounting that creates a persistent choice invalidates the starting condition.
2. Open the actual picker by Accessibility. Retain its role, label, value, actions, bounds, complete bounded hierarchy and screenshot. Require exactly one current checked English menu item; press it once. Wait for the menu to dismiss and read the typed persistent app domain. No oracle language writes after the baseline.
3. Through the same picker, choose Japanese and then English. Require persistent `ja`, then `en`, so an inert or misidentified control cannot establish a product failure.
4. At each stage, freshly capture the real Light plan using an empty memory-only dictionary, empty snippets and no enhancement service. Process `Um, send it tomorrow.` without ASR. Registration-only English and Japanese must preserve it; explicit English must yield `send it tomorrow.`. Do not reuse a plan frozen before the choice or inject a language into it.

A present persistent `en` after the first action, with passing controls, establishes this component's behavior on the tested macOS/SwiftUI version. A still-absent value with passing controls reproduces the issue (native exit 1). A successful primary and controls exit 0. Unsupported/ambiguous Accessibility elements, missing checked state, changed initial preferences, failed controls or source/identity drift invalidate the probe (exit 2); a truncated Accessibility census cannot establish uniqueness. No production change follows until the actual result is reviewed.

## Evidence

Bind exact Git head, original and disposable source hashes, actual compiler input lists, both fixture hashes, package checkout revisions/trees, static framework bytes, signed executable and fresh Accessibility/Screen Recording grants. Retain the observed process identity, strict typed preferences, actual AX actions and dismissal, screenshots, raw output, exit status and confirmed process closure. No direct handler counter is injected; a persistent transition through this unchanged control is behavioral evidence, not instrumentation of the private setter.

The workflow uses only a task-created `ci/rjt-language-selection-probe-*` transport ref. Raw artifacts go once to remote `/data`; retain compact receipts. No user desktop interaction. Scope excludes physical mouse/keyboard, complete Models page composition, model usability, dictation accuracy, general SwiftUI behavior or release proof.
