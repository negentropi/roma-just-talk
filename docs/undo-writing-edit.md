# Undo the latest writing edit

The current candidate includes Undo and clipboard-restoration ownership. Component regression checks and seven native TextEdit/Safari cases pass. Product menu/shortcut and combined UI/Release acceptance remain open. This guide describes the implemented contract; it is not a release receipt.

**Undo Last Writing Edit** restores the selected plain text from your latest confirmed **Edit selected text** action. It also tries to restore the original selection. There is one step, held in memory until RJT quits.

## Use it

Keep the edited field focused, with its result and caret unchanged. Use **Undo Last Writing Edit** in RJT's menu bar menu, or assign its optional shortcut under **Settings → Additional Shortcuts** and use it from that field. No shortcut is assigned by default. This command does not send Cmd-Z, switch apps or move focus to find a destination.

Settings shows **Available**, **Busy** or **Nothing to undo** beside the shortcut recorder. Available means RJT holds an edit receipt; the command still checks the live editor before changing anything. Recording, processing, delivery or an Undo already in progress prevents another Undo.

The shortcut binding is included in settings backup. An older backup without this binding leaves your current choice unchanged. Undo's receipt and full-field before/after snapshots stay in memory. Writing Action transcription, result and request metadata retain their existing History behavior.

## What can be restored

Undo is armed only after RJT confirms a changed result from **Edit selected text**, the expected caret at the end of that result, and an editor whose selection can be restored. A generated response in History alone does not establish that an editor changed or make it undoable.

Before restoring text, RJT requires the same live app instance, window and focused editable field, the exact resulting field text, and the observed caret or selection. Changed text, moved selection, a protected field, lost Accessibility access, a closed window or a terminated app can prevent Undo. Matching text in a different field, window or relaunched app does not qualify.

The inverse replaces only the span inserted by that writing edit. It uses the original delivery route: selected-text Accessibility replacement or the captured system-menu Paste command. A browser field that needed Paste keeps that route. RJT does not replace the full field or try another route after an uncertain attempt.

A newer RJT editor mutation attempt retires the previous receipt, even when that attempt is unconfirmed. This includes ordinary dictation, another Writing Action and Paste Last Transcription or Enhancement. Preparation or generation that stops before any editor attempt may leave the earlier receipt available, subject to the same live checks. Recorder dismissal alone does not erase it.

## Clipboard and cancellation

Undo settles a pending confirmed forward-paste restoration before changing the selection, honoring its original restoration deadline. Writing Paste and ordinary clipboard Paste share that restoration owner. Undo's menu-Paste route preserves the current clipboard even when ordinary paste restoration is disabled. Snapshots retain every readable item format; an unreadable format stops preparation. Generation and session checks leave a newer clipboard copy untouched. A failed restoration stops the next paste while that clipboard generation remains current. Canceling a waiting Undo does not cancel the earlier paste's restoration.

The [matched clipboard check](research/competitors/evidence/clipboard-lease-40605378358/README.md) reproduced three failures on the old code and passed all five cases on the candidate, including both controls. It uses actual clipboard formats and timers with controlled menu/document access. The native Undo results below have their own scope.

Cancellation before the inverse text attempt leaves the field text unchanged. If RJT temporarily selected the inserted span, it restores the prior caret only while the field still matches that intermediate state. Once an inverse text mutation is attempted, the receipt is consumed; RJT does not repeat it or guess whether another attempt would help.

After a forward Writing Action changes the editor, later cancellation preserves its generated text and request metadata for History. An unconfirmed attempt also retains that recovery material. A later History save failure reports the storage problem without repeating or rolling back the editor action. The [matched delivery comparison](research/competitors/evidence/writing-delivery-commit-40606540349/README.md) passed confirmed and uncertain delivery cancellation with controlled editor access. The [recording-finalizer comparison](research/competitors/evidence/recording-finalizers-40604292885/README.md) separately passed stale-owner context checks.

The command distinguishes these outcomes:

| Outcome | Meaning |
| --- | --- |
| Original text and selection restored | Both were confirmed by readback. |
| Original text restored, selection unconfirmed | Text was confirmed; original selection could not be confirmed. No second text replacement follows. |
| Stopped or refused before replacement | No inverse text mutation was attempted. A changed editor or lost permission can cause refusal. |
| Sent, restoration unconfirmed | An inverse was attempted but the original text was not confirmed. Inspect the field before editing again. The receipt is consumed. |
| Busy or nothing to undo | No inverse is started. |

## Scope and verification

This first unit covers a nonempty selection rewritten by **Edit selected text**. Translate, Draft, ordinary dictation and insertion undo are outside its scope. There is no Undo stack or Redo. Quitting RJT or terminating the destination app releases the receipt.

Only plain text and UTF-16 ranges are retained. Original formatting, links and rich-text attributes are not restored. Formatting-only changes and an external edit racing the final checks cannot be ruled out by these APIs. Exact observed text and identity checks do not make an edit atomic with another app.

[Native run 40617647503](research/competitors/evidence/undo-native-40617647503/README.md) passed all seven cases. TextEdit covered process replacement refusal, decomposed Unicode text/selection restoration and drift refusal. Safari covered forward/inverse delivery, both clipboard preferences, a newer clipboard copy and latest-owner cancellation during a pending restoration lease. The private lease wait entry was not instrumented.

Safari's successful fixtures use precomposed text. A separate case requests decomposed text and observes different exact UTF-16 readback. That result remains unconfirmed, cannot arm Undo, and stays unchanged when Undo returns unavailable. The exact-output guard is unchanged. These are the corrected seven-case acceptance conditions; they do not turn the earlier six-case failures into passes. Product menu/shortcut and full UI/Release acceptance remain open.

The [implementation plan](research/competitors/implementation-plan.md#current-verification-status) tracks the current gates. These results do not establish every editor, physical shortcuts, speech, provider quality or a published release.

Implementation owners: [live target](../VoiceInk/Services/WritingTarget.swift), [memory-only controller](../VoiceInk/Services/WritingActionUndoController.swift), [delivery integration](../VoiceInk/Transcription/Engine/TranscriptionPipeline.swift), [menu and notices](../VoiceInk/Views/UndoLastWritingEditControl.swift), and [shortcut/backup contract](../VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift).
