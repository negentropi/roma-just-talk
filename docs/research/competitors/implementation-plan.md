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
- The original [full Mac run 40464283678](https://github.com/negentropi/roma-just-talk/actions/runs/40464283678) was canceled after waiting without a Namespace runner. Hosted Mac checks provide the active execution route.

No live-editor, visual-layout, physical-keyboard or general provider-quality claim is established by these results.

## Following Mac units

1. Add cleanup strength and style presets around the existing cleanup and Power Mode owners. The [reviewed design](cleanup-profile-design.md) preserves Custom as the migration default and defines literal None, deterministic Light and bounded Clarity with visible raw fallback.
2. Add correction provenance and review. The [approved-correction design](correction-learning-design.md) reuses the replacement library and records discovered literal-template and Unicode boundary defects. Automatic learning additionally needs reliable attribution to a delivered range; ordinary typing must not become training input.
3. Add transform transactions with stored originals, results, review, retry from the original, and undo of the latest owned edit. A single `enhancedText` value cannot represent that history.
4. Add a local scratchpad with durable drafts and versions. Sync, image storage, meetings, and organization features keep their separate contracts.

These are queued work units, not completed parity claims. Start the next implementation after the current unit passes its relevant gates.
