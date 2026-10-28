# Undo the latest confirmed writing edit

Implementation contract for the existing Mac app. The current candidate contains the live-target receipt, memory-only controller, pipeline/engine integration, optional shortcut/backup support and menu/settings controls. These changes form the Undo unit. Claude Opus 5.5 authored the user-facing controls and label; GPT-6.1 Sol reviewed them.

The candidate implements shared clipboard-restoration ownership and post-delivery metadata retention. The [matched clipboard](evidence/clipboard-lease-40605378358/README.md), [delivery/cancellation](evidence/writing-delivery-commit-40606540349/README.md) and [recording-finalizer](evidence/recording-finalizers-40604292885/README.md) comparisons passed their controlled boundaries. [Native run 40617647503](evidence/undo-native-40617647503/README.md) passed seven TextEdit/Safari cases with exact text/range and clipboard observations. Positive Safari fixtures use precomposed text; a separate decomposed-output case remains unconfirmed and grants no Undo authority. This is corrected candidate acceptance, not a matched green for the earlier six-case failures. Product controls and full UI/Release remain open. No release or general editor support is claimed. See the [user guide](../../undo-writing-edit.md) and [current verification status](implementation-plan.md#current-verification-status). The audit below describes the historical starting source, not current line numbers or a new runtime result.

## First unit and decisions

Support one Undo for the latest confirmed **Edit selected text** (`rewriteSelection`) delivery, through both existing routes: selected-text AX mutation and captured system-menu Paste. Restore the original selected plain text and selection only while the same live editor still matches the confirmed result. This is a guarded inverse edit, never generic Cmd-Z.

The capability lives in memory for one RJT process. It survives recorder dismissal and session cleanup. It cannot be revived from History, a stored PID, a matching field in another window, or an app relaunch. A busy operation disables Undo. A failed generation before any editor attempt may leave the previous capability available if its state still validates. A newer RJT editor mutation attempt retires the previous capability, even if delivery is uncertain. A confirmed inverse consumes it; there is no stack or Redo in this unit.

Translation, drafting, ordinary dictation, review/diff, retry and durable transform history are later scope. Translation/draft can start with an empty selection; undo would then need deletion of inserted text. Empty-string system Paste is not established as a deletion operation. Do not claim insertion undo or bypass a web editor's required Paste route through a settable AX attribute, full `AXValue`, Backspace or synthetic keyboard fallback.

Plain-text scope is explicit. Current snapshots contain no original attributes, links or rich selection payload. The feature cannot promise restoration of rich formatting or detect formatting-only changes. It preserves exact UTF-16 text inside and outside the captured range; it does not promise an editor's native undo-stack behavior.

## Audited source boundary

Source was read at `aaaa286a794ac6f60773ef5149a30f214c586f23`. The owning files below were unchanged through checked head `d2e6a1530cfceee56d34a22a8c20a19403d758c9`. Recheck them at the implementation head; concurrent provider and verification work must be preserved. Line references describe that source, not runtime observations.

| Owner | Observed behavior and implication |
| --- | --- |
| [WritingTarget.swift](../../../VoiceInk/Services/WritingTarget.swift), lines 42–80 | Captures full value, UTF-16 range and selected text. Rejects overflow and split surrogate pairs; `matches` compares exact UTF-16. Keep that comparison, rather than synthesized `TextSnapshot ==`, whose String equality is canonical. Scalar boundaries inside decomposed graphemes remain supported. |
| Same file, lines 98–173, 200–260 | Original snapshot/route/access are private and immutable. `replace` returns `Void`; after a successful edit the original snapshot cannot authorize an inverse. Validation requires the captured PID, currently focused identical AX element, permissions, security and editability. No process-instance/undo capability is retained. |
| [WritingActionSession.swift](../../../VoiceInk/Services/WritingActionSession.swift), lines 7–35 | Owns one recording's action, language, provider and captured destination. It is not an app-lifetime undo owner. |
| [CursorTextContextReader.swift](../../../VoiceInk/Services/CursorTextContextReader.swift), lines 125–163 | Captured menu Paste validates exact value/range, focus/PID and menu ownership, retries discovery only before mutation, then issues one AXPress. An error may follow mutation. |
| Same file, lines 1669–1672 | Web-area ancestors require system Paste so DOM handlers update application state. Preserve this route contract for the inverse. |
| [CursorPaster.swift](../../../VoiceInk/Paste/CursorPaster.swift), lines 61–165 | Guards clipboard generation, session marker and exact UTF-16 payload; distinguishes no attempt from uncertain delivery. Confirmation reads exact full output, without retaining post-selection. A failed AX return can still be confirmed by observed output. |
| [TranscriptionPipeline.swift](../../../VoiceInk/Transcription/Engine/TranscriptionPipeline.swift), lines 189–228 | Stores generated output and request metadata, then delivers through `writingSession.target.replace`; no delivery receipt is retained. |
| Same file, lines 84–117, 396–399, 509–510 | Generic cancellation can run after writing delivery but before save. Cancellation calls `markAsCanceledTranscription`, which clears generated/request metadata. A confirmed editor change needs an explicit commit boundary before this check. |
| [VoiceInkEngine.swift](../../../VoiceInk/Transcription/Engine/VoiceInkEngine.swift), lines 730–775 | Passes the recording's captured session into the pipeline, then clears it. Undo ownership must survive this cleanup and reject stale operation completions. |
| [Transcription.swift](../../../VoiceInk/Models/Transcription.swift), lines 7–22, 104–126 | One original text/enhanced-text pair and request strings; no typed transform history or live destination authority. Cancellation clears result metadata through the existing plan. |

Existing [target tests](../../../VoiceInkTests/WritingTargetTests.swift), [captured-paste tests](../../../VoiceInkTests/CapturedWritingPasteTests.swift) and [live editor tests](../../../VoiceInkTests/WritingTargetLiveTests.swift) provide reusable boundaries. Their existing coverage is not proof of the new undo operation.

## Confirmed edit receipt

Extend `WritingTarget` with a typed confirmed-edit result. Preserve its current distinction between rejected/no-attempt and attempted-but-unconfirmed delivery. Do not reduce these to Bool or treat every AX error as failure.

The receipt owns:

- Transaction UUID, recording/transcription UUID and delivery generation.
- Original selected plain text and original UTF-16 range.
- Exact before/after full values in memory, and inserted range `(original.location, output.utf16.count)`.
- A complete observed post-delivery value/range/selected-text snapshot.
- The captured AX element, containing window identity, live `NSRunningApplication` instance and selected delivery route; retain process-instance checks rather than trusting a recycled PID.
- For menu delivery, the confirmed clipboard restoration lease described below.

Arm Undo only when output differs in exact UTF-16, expected full output is confirmed, and the same live editor yields a coherent post-selection. Require the expected collapsed caret at the inserted range's end for this first unit; if a supported editor has another stable postcondition, establish it in the native gate before accepting it. Do not capture an arbitrary later user selection as the operation's postcondition. Delivery may succeed while Undo remains unavailable because that postcondition could not be observed.

Retain at most one before/after field snapshot; add no background document monitoring, content collection or extra provider request. Full-field snapshots remain memory-only and are released with the capability. The existing 24,000-character selected-input limit remains in force; it is not a limit on the full field read by AX.

## One owner and the inverse

Add one `@MainActor` `WritingActionUndoController` owned by the app's `VoiceInkEngine` and passed to its pipeline. Expose availability/result through that owner. Do not add a second controller per session, a persistent global target registry or a second paste implementation.

Its states are empty, available(receipt), undoing(receipt), and retired. A monotonic delivery generation/UUID binds callbacks to their owner. Begin a new delivery generation immediately before a possible RJT editor mutation; retire any older capability. Install a new receipt only for the currently authorized generation after confirmed output. An old completion must neither replace a newer receipt nor clear its busy state. The inverse uses its own operation identity and cannot register itself as another undoable forward action.

All RJT delivery entry points must retire older capability before an editor attempt: writing pipeline, ordinary dictation paste, and Paste Last Transcript/Enhancement. Pass the same controller explicitly to the latter service at its existing callers. Copies alone do not retire the capability. This is a bounded integration with RJT's own writes; it is not a universal monitor of other apps' editing history.

Undo sequence:

1. Claim the available receipt while idle; verify its live process/window/element still exists. Do not activate an app, move focus, locate an equivalent text field or create a new destination.
2. Settle any prior confirmed clipboard restoration lease before changing selection. Cancellation during that wait leaves the editor untouched. Revalidate operation identity and cancellation after every suspension.
3. Require the same focused live editor, permission/security/editability state, exact full resulting value and exact observed post-selection. Any observed mismatch refuses and retires the receipt. Switching away may refuse without activating anything; returning to a matching original field never permits targeting a replacement process/window.
4. Add a guarded selected-range setter to `WritingTarget.Access`. Select only the inserted UTF-16 span, then read back exact value/range/selected text and revalidate identity. A range-set error can follow a change: inspect state before deciding whether anything further is authorized.
5. Build the inverse snapshot from the result value and selected inserted span. For system Paste, create the captured menu target from this inverse snapshot using the same element/process, not the stale forward `FocusedPasteTarget`. Reuse `pasteWritingReplacement` and its final authorization checks. For direct AX, replace selected text through the same direct route. No full-value write or route fallback.
6. Consume the capability immediately before the first inverse **text mutation attempt**. After an attempt, never repeat, issue Cmd-Z, restore text speculatively or try another route. Exact original full-value readback establishes text restoration even when AX returned an error; partial/no-op/uncertain output leaves an explicit unconfirmed outcome.
7. Once original text is confirmed, restore the original selected range and verify it. If text is restored but selection restoration fails, report that distinct result; do not repeat the edit. If the range changed but no text was attempted, restore only the still-owned pre-undo selection when value, focus and selection still match the controller's own intermediate state. Otherwise leave the user's newer state intact and retire the capability.

No persistent capability survives target termination or RJT restart. Detect process termination and release captured text promptly; revalidate lifetime at invocation regardless of notifications. A stale AX element or replaced window refuses. Same-value changes away and back, formatting-only changes, and an external edit racing between the final AX checks and action cannot be proven absent by these APIs. Describe the guarantee as exact observed state validation, not an atomic transaction with another app.

## Clipboard restoration is a prerequisite

The following race is inferred from actual source and independently reviewed; it has not been run as an undo scenario:

1. Forward Paste snapshots user clipboard **C** (`CursorPaster.swift:75–76`), writes temporary **F**, confirms the editor value and returns while restoration is scheduled (`139–151`).
2. Immediate inverse Paste snapshots still-present **F** as its previous clipboard and writes **U**.
3. Forward timer rejects U's different generation/session (`437–458`).
4. Inverse timer restores its saved F under another generation (`460–462`). The original C is stranded. Matching payload text alone cannot recover clipboard ownership.

Replace the independent restoration closures with one owned restoration lease per pasteboard. Keep it inside `CursorPaster`, alongside the existing clipboard code; do not expose clipboard snapshots to UI or persist them. Both captured writing Paste and ordinary RJT clipboard Paste must participate, otherwise an immediate ordinary paste after Undo can recreate the same nesting race. Preserve each route's existing restoration eligibility: ordinary `commandPosted` is not evidence of a confirmed writing edit, and no attempted-unconfirmed writing operation gains a restoration lease.

A lease captures all clipboard item formats, exact temporary UTF-16 payload, session UUID, change count, captured restoration policy/deadline and one-shot settlement state. Timer and explicit settler consume the same lease, once. Settle it before the next owned clipboard snapshot/write and before Undo changes selection. Revalidate any earlier `PreparedPasteContext` generation after settlement rather than reusing a snapshot of a retired temporary payload. Honor its captured not-before deadline: configured default is two seconds, minimum 0.25 seconds. Do not shorten the deadline solely because Undo arrived.

If the user copied something newer, retire the old lease without restoring over that copy; subsequent Undo snapshots the new clipboard normally. While waiting, cancellation stops only the new operation; the original forward restoration remains independently eligible. After every await recheck operation identity, cancellation and exact lease ownership. Final ownership checks, consumption, restoration and the next snapshot must be serialized on MainActor, with no intervening await. Inspect clipboard write/restoration results; a failed restoration aborts the new operation. Never settle an attempted-unconfirmed delivery automatically.

Undo itself always uses transient clipboard preservation. A forward operation with Keep Clipboard Content disabled intentionally has no restoration lease; Undo preserves whatever clipboard is current when the inverse starts. New copies during inverse delivery or delayed restoration always win. Reuse current all-format snapshots, double generation checks and session markers; do not compare only String canonical equality.

The lease can be canceled/retired internally when superseded, but cancellation of a new Undo must not cancel an unrelated still-owned forward restore. Target revalidation follows lease settlement. No generic clipboard-history service is needed.

## Commit after external delivery

Make writing delivery a visible runtime outcome in the pipeline: not attempted, attempted unconfirmed, or confirmed with optional undo capability. Install the confirmed receipt synchronously at observed delivery, before dismissal, duration work or History save. Do not install it merely because generation succeeded or `transcriptionState` was set to completed.

After confirmed delivery, later user/task cancellation cannot claim the editor was untouched, clear the generated text/request or revoke the fact that delivery happened. Finish saving the delivered record and keep its live capability when still valid. A History save failure reports storage failure without repeating or rolling back the external edit. A newer operation can retire capability normally.

Before any attempt, cancellation keeps the existing no-delivery behavior. After an uncertain attempt, preserve original instruction and generated output for recovery, mark the outcome unconfirmed in runtime state, retire prior undo authority and never auto-retry. This requires a bounded writing-branch cancellation change; do not rewrite unrelated ordinary-dictation cancellation policy.

## Persistence decision and later transforms

**First unit: no schema change, new store or persisted delivery scalar.** The latest-edit capability and delivery commit are runtime facts; existing History fields retain the generated output and instruction. Do not infer restart-safe undo from them or overload `transcriptionStatus` with invented values. This keeps the first undo unit independent of speculative schema work while fixing the actual delivery/cancellation boundary.

The early [40558902068 failure](evidence/store-seed-40558902068/failure-diagnosis.json) and [40562833675 snapshot](evidence/store-seed-40562833675/run-status.json) remain invalid as upgrade proof. Later runs now establish the [actual unchanged-schema control](evidence/store-seed-40575066549/audit-summary.json) and [four-field recognition metadata upgrade](evidence/dictation-metadata-40581983321/README.md). These local, source-bound results do not authorize persisted Undo or prove CloudKit synchronization. The [upgrade procedure](store-upgrade-verification-design.md) still applies to each new stored-field change.

After actual predecessor seed/control succeeds, use a minimal optional scalar on the existing `Transcription` only if the product separately needs durable delivery outcome. Give absent/unknown old values deliberate handling and prove predecessor clone → changed candidate save → process exit → reopen. A scalar does not justify another store and cannot authorize Undo. Do not make this optional metadata a dependency of the first live capability.

Durable original/result versions, diff/review and retry from the original require their own later transform-record unit, as already listed in [the implementation plan](implementation-plan.md#following-mac-units). That unit must model one-to-many attempts/results explicitly, preserve originals and instructions, bind records by UUID without persisting AX authority, define retention/deletion, and prove actual old-store upgrades. Do not hide a history stack in `enhancedText`, request JSON, UserDefaults or an opaque persisted live receipt. Choose its relationship/store grouping after the actual seed and real history requirements are available. This first unit does not choose a new transform store or claim review/retry complete.

## Implementation ownership and sequence

| Work unit | Owned files | Completion boundary |
| --- | --- | --- |
| Delivery receipt and guarded inverse | `VoiceInk/Services/WritingTarget.swift`; new `WritingActionUndoController.swift`; `VoiceInk/Services/CursorTextContextReader.swift`; target/controller tests | Both routes return actual outcomes; exact postcondition, safe range selection, one inverse attempt, process/window lifetime and latest generation enforced. |
| Clipboard lease | `VoiceInk/Paste/CursorPaster.swift`; `VoiceInkTests/CapturedWritingPasteTests.swift` | Same-boundary old/new race reproduction, all-format preservation, one settlement, cancellation and newer-copy safety. Coordinate the typed paste outcome with the delivery owner before parallel edits. |
| Pipeline and application owner | `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`; `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`; `VoiceInk/Services/WritingActionSession.swift` only if receipt identity requires it; `LastTranscriptionService.swift` and its shortcut/menu callers | Receipt commit precedes post-delivery cancellation; current owner wins; session cleanup preserves capability; all RJT editor attempts retire prior authority. Existing model schema stays unchanged. |
| User controls | Claude Opus 5.5: shortcut action/manager, menu/settings presentation, optional result notice. GPT-6.1 Sol: review | Clearly named Undo last writing edit; idle/availability states and plain-text scope; no focus retarget. Actual shortcut/menu interaction proof must show which external editor remains focused. No generic Cmd-Z binding. |
| Hosted acceptance and closeout | Relevant target/paste/engine tests, `WritingTargetLiveTests.swift`, selected remote driver/workflow, docs/Unreleased changelog | Exact selected IDs execute, native observations and metadata retained, full relevant Mac/Release gate green. Parent owns commits and CI transport. |

Order: prove the clipboard lease bug first; implement lease and receipt/controller; integrate the explicit pipeline commit and other RJT mutation callers; build the Claude controls; run actual native interactions; then complete the full relevant gate. Keep one owner for overlapping paste/receipt APIs. No new dependency is proposed.

## Required acceptance

| Case | Required actual observation |
| --- | --- |
| TextEdit AX and Safari textarea Paste | Forward rewrite and product Undo each attempt once. Original full text and original selection return exactly; prefix/suffix unchanged. Record route, same process/window/editor identity and before/result/restored ranges. |
| Unicode and length | Emoji, ZWJ sequence, decomposed combining marks, multiline, non-BMP prefix/suffix and shorter/longer output. Compare UTF-16 units; reject split surrogates/overflow and canonically equal normalization drift. Preserve supported scalar-boundary selections. |
| Postcondition unavailable | Forward text may complete, but missing/wrong post-range produces no Undo capability. No arbitrary later selection is accepted as receipt state. |
| No-op and unsupported inverse | Exact unchanged forward output creates no new undo. Missing range setter refuses without text attempt. Empty-original insertion remains explicitly unsupported until native route-specific deletion is established. |
| Value/range/focus drift | User types anywhere, changes selection, focuses another element/app, changes window/document, terminates/relaunches target or enables protected input. No inverse text attempt; unrelated document and clipboard remain intact. Restore an intermediate selection only while still owned. |
| Clipboard nesting regression | Current paster performs confirmed forward and reverse menu-paste operations under one unchanged oracle before the original restore deadline: actual old code strands F; candidate lease restores exact C once. Repeat with an ordinary RJT paste immediately after Undo and with an earlier prepared clipboard snapshot. Empty, image, custom binary and multiple items retain every format. Missing/setup failure is not the expected red result. |
| New clipboard generations | New copy before Undo, during lease wait, discovery, after confirmation and before either timer. Include identical text/marker with a different generation. New copy survives; no unauthorized editor posting. |
| Cancellation and settlement | Cancel before lease wait, during wait, after range selection, during menu discovery and after text attempt. No attempt before authorization; no second text mutation afterward. Timer/settler race settles once; failed restore aborts the inverse. |
| Ambiguous AX results | Error with exact confirmed mutation succeeds once. Accepted no-op, partial write, disappearing target and delayed/unconfirmed result never trigger retry, route switch or speculative rollback. |
| Commit and storage | Cancel immediately after confirmed writing delivery; generated output and request remain. Force History save failure after delivery; editor stays changed, capability remains valid, failure is visible, no duplicate paste. Before-attempt cancellation still makes no delivery. |
| Latest owner | Two completed rewrites expose only the newest capability; Undo twice cannot replay. Hold an old completion across reset/newer operation, then release it: it cannot install/retire the newer receipt. An uncertain newer attempt retires the old capability. Generation failure before an attempt does not create one. |
| Lifetime | Recorder cleanup does not erase Undo. App death/restart or destroyed/replaced editor releases authority; identical text/PID alone cannot restore it. History open/copy does not manufacture a target. |
| Product control | Actual configured shortcut and menu entry exercise product Undo without unintended activation. Disabled/busy/unavailable outcomes are clear. Capture relevant UI and original/result/restored editor values. |

For the clipboard and post-delivery cancellation defects, require red on the actual known-bad owning code and green on candidate under the same conditions. An old version that cannot compile a newly added Undo API is not regression proof. New feature acceptance uses the real candidate command, not a fake Undo implementation. Unit doubles cover scheduling and ambiguous outcomes; native TextEdit/Safari checks cover actual AX/Paste and selection behavior. Retain exact source, selected/enabled/executed IDs, app signatures/fresh permission receipts, identities and result observations. Run remotely; no shared user foreground, clipboard, saved Keychain or real documents are required.

No test in this plan alone proves rich-text restoration, every editor, physical keyboard behavior, human speech, provider quality, notarized distribution or persistent undo after restart.
