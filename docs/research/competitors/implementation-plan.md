# Existing Mac app feature work

Target confirmed by Felix on 2026-10-27: the VoiceInk-based macOS app. The Rust rewrite is comparison evidence only.

## Checklist

- [x] Read Poteto mode's Principles section in full.
- [x] Phase A: Frame.
- [x] Phase B: Design the workflow.
- [ ] Phase C: Run the loop. Implementation committed; remote verification is in progress.
- [x] Phase D: Keep the audit trail.
- [ ] Phase E: Verify and hand back.

## First verifiable unit

Deliver three ordinary desktop workflows before adding hosted services.

1. Translate a recording into an explicitly chosen target language without changing the recognition language.
2. Select editable text, record a rewrite instruction, and replace exactly that selection. Drafting uses an explicit action too. Changing the target, text, or selection prevents replacement and keeps the result recoverable.
3. Add, edit, disable, import, and export spoken snippets. Saved content, including line breaks, remains literal when inserted.

Done means the real Mac artifact exposes these controls, persists preferences, uses the existing transcription and AI providers, delivers the expected result, and passes failure, cancellation, and target-drift cases. Unit checks and compilation alone do not prove this predicate.

## Data and ownership

- A writing action identifies translation, selection rewriting, or drafting. Each recording captures an immutable action request and destination before asynchronous work starts.
- The Accessibility target owns field identity, original value, selection, validation, and replacement. Provider requests receive selected text only when the action needs it.
- A snippet has an identifier, trigger, literal content, and enabled state. Its library owns validation, matching, CSV import, and persistence.
- Existing dictation keeps its current pipeline. Explicit writing actions bypass dictation cleanup, trigger prompts, snippets, and auto-send.
- UI changes belong to Claude Opus 5.5. GPT-6.1 Sol reviews the result. Backend workers have exclusive file ownership. The parent integrates, verifies, and commits.

## Verification sequence

1. Check the pure snippet and writing-request contracts through VoiceInkCoreChecks.
2. Run the app unit gate, full Mac build, and existing relevant checks on remote macOS CI.
3. Exercise ordinary dictation, multiline snippets, translation, and selected-text rewriting on a fresh remote Mac.
4. Reject replacement after focus, text, or selection drift. Reject failed AI output and cancellation without pasting the instruction.
5. Inspect the real UI, keyboard access, persistence, and error recovery. Record unproven boundaries explicitly.

## Throughput checkpoint

Three backend owners work on separate files while Claude owns Views. The shared CI build starts after integration rather than once per worker. Remote execution avoids model downloads and Xcode caches on the user's laptop. Read-only reviewers can run while the remote build runs.

## Remaining scope

The [52-capability ledger](rjt-parity.md) remains the full inventory. This first unit does not establish complete competitor parity. Later units include correction learning, richer cleanup and style controls, transform review and undo, local notes, and context and developer workflows. Mobile, meetings, account sync, and team administration retain separate acceptance contracts. Hosted features require concrete service and operating decisions before their dependent implementation.

The decision trail is [implementation-decisions.tsv](implementation-decisions.tsv). Record results as VERIFIED, NOT VERIFIED, or INCONCLUSIVE.

## Current evidence

- `ec7bc1bc` contains the snippet library and 17 behavior checks. All 17 passed against the compiled production module.
- `827845a1` contains Mac workflows and their settings, backup, and boundary tests. GPT-6.1 Sol source review found no remaining blockers after startup ownership, inline snippet delivery, and UI conflict fixes.
- `61bced16` adds the hosted Mac verification workflow. [Run 40465969195](https://github.com/negentropi/roma-just-talk/actions/runs/40465969195) passed shared core checks, Release packaging, Debug compilation, and CI permission provisioning. The unit run then failed on malformed emoji selection boundaries and crashed in all three pipeline fixtures during SwiftData save. Native, matched regression, and UI steps did not run.
- `b8d3c263` fixes UTF-16 endpoint validation. The same production-class probe failed four cases on the pinned bad source and passed all twelve on the candidate. `57f0cb85` explicitly isolates the pipeline test store without changing its output assertions. The store change remains a hypothesis until rerun.
- [Run 40470346259](https://github.com/negentropi/roma-just-talk/actions/runs/40470346259) tested candidate `98df5fa5`. Core and Release gates passed. The new provider fixture validator failed Swift Testing macro compilation, so no app tests executed. This run does not verify the UTF-16 or store corrections.
- `e774c745` computes provider fixture verdicts before expectation expansion. [Run 40475185945](https://github.com/negentropi/roma-just-talk/actions/runs/40475185945) tested candidate `7459b97b`. Shared core and full Mac units passed. The [native result receipt](evidence/mac-40475185945/debug-unit-summary.json) records 150 successes, zero failures and six gated skips. The corrected UTF-16 case, three pipeline fixtures and two recording ownership cases passed. Native editor, matched regression and UI proof remain open.
- That run's live-editor step selected zero tests. Artifact metadata showed that environment forwarding worked but selectors omitted the discovered method parentheses. The strict verifier rejected the result. `6fe5f75e` corrects selectors and requires exact enabled-test enumeration before execution; `2c5058fe` collects each sequential proof gate after unit success even if another fails. Release still requires all gates to pass. [Run 40479529231](https://github.com/negentropi/roma-just-talk/actions/runs/40479529231) tests that candidate. The superseded `6fe5f75e` run was canceled during core checks.
- [Run 40479472510](https://github.com/negentropi/roma-just-talk/actions/runs/40479472510) separately compares actual snippet and target edits during an active Power Mode on pinned bad `98df5fa5` and candidate `c2772580`. The UI-only test schemes, oracle, packages, app identity and fresh permissions are checked. This comparison has not yet produced a runtime verdict.
- [Five prompt/CLI smoke observations](evidence/writing-cli-smoke/summary.md) passed against source `d5a90a27`, using the existing authenticated CLI default reported as Claude Opus 5.5. GPT-6.1 Sol reviewed their preserved facts and language. The offline verifier reconstructs source-bound requests and checks retained output hashes. This is not app-service, Groq, ASR or native delivery proof; lexical checks do not establish general semantic robustness.
- [Run 40479529231](https://github.com/negentropi/roma-just-talk/actions/runs/40479529231) executed the corrected selection driver. Its [receipt](evidence/mac-40479529231/debug-and-native-summary.json) records 150 unit successes, six gated skips, two native TextEdit successes, one Safari fixture failure and three UI launch failures. TextEdit proved exact selection replacement and refusal after range, text or focus drift. Safari failed before capture; UI controls were not reached. The matched regression stopped before tests because ordinary Xcode resolution had repaired the stale lock differently from the historical checkout.
- Xcode resolution [40482229518](https://github.com/negentropi/roma-just-talk/actions/runs/40482229518) produced 17 missing pins while preserving all 24 original pins and every dependency declaration. `dc69ae9d` applies those exact generated bytes. [Run 40483532747](https://github.com/negentropi/roma-just-talk/actions/runs/40483532747) then passed with the complete lock unchanged. Historical comparison scripts verify declaration equality, transfer only that reviewed metadata, and require strict resolution before building.
- The UI launch fixture supplied `IsMenuBarOnly` as a string, while the production preference reader requires a Boolean. `baff6a70` seeds a typed value. The subsequent Power Mode UI run reached actual recording, but its first control lookup expected a StaticText where the native tree exposes a Button. Error reporting queried that missing element and bypassed Swift cleanup, leaving the next cases invalid. `a0e38f36` uses observed roles and independent XCTest teardown with owned-process/session checks. These fixture corrections still need runtime proof.
- [Safari probe 40487793001](https://github.com/negentropi/roma-just-talk/actions/runs/40487793001), source `479fa176`, reached the captured field and passed selection/drift checks. Its [read-only receipt](evidence/safari-40487793001/replacement-failure.json) shows that the original text and selection remained unchanged after the accepted AXSelectedText write throughout the observation period. Increasing the readback wait is not justified by that result. The reviewed fix chooses a strict captured-target Paste-menu route for web editors before attempting any mutation; native selected-text writes remain separate.
- `a952ff67` fixes a reproduced dictionary defect by escaping literal replacement text before the regex-template API. The same production-engine fixture failed two dollar/backslash cases on the bad source and passed all five focused methods on the candidate. [Receipt](evidence/literal-replacement/receipt.json). Shared core checks also passed on `f901c372`; native application verification remains pending.
- `f901c372` chooses the browser delivery route at capture, revalidates the exact target and clipboard before one menu-paste attempt, and checks the resulting UTF-16 value. Native selected-text writes retain their separate route. Seventeen named-pasteboard boundary tests were added. Independent source review passed; [full application run 40492556627](https://github.com/negentropi/roma-just-talk/actions/runs/40492556627) has passed canonical package resolution and shared core checks. App compilation, boundary tests and native delivery remain pending.
- `3f245ff7` separates owned document startup from the existing five-second exact-field predicate. It records monotonic milestones and adds one activation of the exact returned application. This changes the fixture readiness boundary, not production delivery. [Matched native run 40493989405](https://github.com/negentropi/roma-just-talk/actions/runs/40493989405), driver `99ff7bdb`, builds real native files and Core/NVIDIA dependencies from both revisions with the same helper. Acceptance requires the precise original-text Safari no-op on `479fa176` and exact replacement on the candidate. Setup failures do not satisfy regression proof.
- That matched native run passed. The [retained receipt](evidence/safari-40493989405/receipt.json) binds the sources, shared oracle, exact package pins and unchanged executable identities. The baseline reproduced `replacementUnconfirmed` with readable, unchanged original text; the candidate replaced exactly the selected passage, preserving the emoji prefix/suffix and line break. Both refused selection drift. This proves that native Safari boundary on the tested artifact, not the full recording/provider workflow or rich-text behavior.
- [Power Mode run 40491279663](https://github.com/negentropi/roma-just-talk/actions/runs/40491279663), driver `f4ffbf39`, reproduced the snapshot defect through actual snippet edits but remained invalid. XCTest separated Escape events by over ten seconds, outside the 1.5-second gesture interval. Later launches had no main scene. `e49ebe4f` opens Settings through the actual menu and uses one configured Cancel Recording action, retaining all mutation/restoration assertions.
- The resulting [Power Mode comparison 40494936415](https://github.com/negentropi/roma-just-talk/actions/runs/40494936415) passed. Both pinned bad cases failed the snapshot/restoration contract and both candidate cases passed after actual snippet save/toggle or translation-target add/reorder, followed by recording cancellation. The [receipt](evidence/power-mode-40494936415/receipt.json) identifies driver `e49ebe4f`, bad product `98df5fa5` and candidate product `8d256816`. This deliberately excludes later production changes and proves neither physical keyboard input nor Double Escape timing.
- [Run 40492556627](https://github.com/negentropi/roma-just-talk/actions/runs/40492556627), source `f901c372`, passed shared core, full app units and matched snippet/permission regressions. The old source changed both literal snippet cases and allowed duplicate permission waits; the candidate passed those cases and the ordinary-dictation control. TextEdit passed again. Safari failed before capture with the old startup helper. The UI exposed an actual `PathTextField` where the fixture queried a ComboBox, then later launches had no main scene. Updated fixture source retains the feature assertions. The run is red and Release did not execute.
- [Actual Local CLI service proof](evidence/local-cli-service-40496074931/summary.md) passed four remote deterministic cases and three authenticated language cases using the same signed artifact. GPT-6.1 Sol reviewed the actual output meanings. This establishes provider routing and command execution for the tested source, separately from the original prompt-only smoke. Recording, ASR and editor delivery remain outside that service probe.
- [Run 40496608276](https://github.com/negentropi/roma-just-talk/actions/runs/40496608276), source `c1a0f967`, passed its full unit step and all four native checks. The [native receipt](evidence/live-40496608276/receipt.json) includes actual TextEdit/Safari transactions and a real pipeline/Local CLI child-process case with fixed synthetic recognition and command output. The success case replaced exactly the owned selection despite live command preferences changing after capture. The failure case left the original document untouched and a fresh context read the saved failed record and raw instruction. This is in-memory save visibility, not crash/relaunch durability. Remaining gates are still running; the next queued head also includes the observed CSV picker selector and Unicode dictionary fix.
- The original [full Mac run 40464283678](https://github.com/negentropi/roma-just-talk/actions/runs/40464283678) was canceled after waiting without a Namespace runner. Hosted Mac checks provide the active execution route.

TextEdit's tested target boundary is established on `2c5058fe`; the separate matched Safari native comparison passed on `99ff7bdb`. Actual app native checks, pinned Power Mode UI mutation/restoration and actual Local CLI service execution are established within their stated scopes. Complete settings workflows, Release packaging on the final candidate, physical keyboard behavior, microphone-to-provider delivery and general provider quality remain open. Source or fixture corrections do not establish those runtime outcomes.

## Following Mac units

1. Add cleanup strength and style presets around the existing cleanup and Power Mode owners. The [reviewed design](cleanup-profile-design.md) preserves Custom as the migration default and defines literal None, deterministic Light and bounded Clarity with visible raw fallback.
2. Add correction provenance and review. The [approved-correction design](correction-learning-design.md) reuses the replacement library and records discovered literal-template and Unicode boundary defects. Automatic learning additionally needs reliable attribution to a delivered range; ordinary typing must not become training input.
3. Add transform transactions with stored originals, results, review, retry from the original, and undo of the latest owned edit. A single `enhancedText` value cannot represent that history.
4. Add a local scratchpad with durable drafts and versions. Sync, image storage, meetings, and organization features keep their separate contracts.

These are queued work units, not completed parity claims. Start the next implementation after the current unit passes its relevant gates.
