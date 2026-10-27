# Undo the latest writing edit

Implementation status: the current candidate includes Undo and its clipboard-restoration integration. Candidate native editor, clipboard, cancellation and menu/shortcut verification remain pending. This guide describes the implemented contract; it is not a release or runtime-verification receipt.

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

The [known-bad clipboard run](research/competitors/evidence/clipboard-lease-40602002286/independent-audit.json) reproduced three overlapping-restoration failures and passed two controls. Candidate execution of those same cases and the immediate-Undo interaction remain pending.

Cancellation before the inverse text attempt leaves the field text unchanged. If RJT temporarily selected the inserted span, it restores the prior caret only while the field still matches that intermediate state. Once an inverse text mutation is attempted, the receipt is consumed; RJT does not repeat it or guess whether another attempt would help.

After a forward Writing Action changes the editor, later cancellation preserves its generated text and request metadata for History. An unconfirmed attempt also retains that recovery material. A later History save failure reports the storage problem without repeating or rolling back the editor action.

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

The [implementation plan](research/competitors/transform-undo-design.md) tracks the clipboard prerequisite, cancellation boundary and native TextEdit/Safari checks. Source and unit-test preparation alone do not prove those interactions, every editor, physical shortcuts, speech, provider quality or a signed release.

Implementation owners: [live target](../VoiceInk/Services/WritingTarget.swift), [memory-only controller](../VoiceInk/Services/WritingActionUndoController.swift), [delivery integration](../VoiceInk/Transcription/Engine/TranscriptionPipeline.swift), [menu and notices](../VoiceInk/Views/UndoLastWritingEditControl.swift), and [shortcut/backup contract](../VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift).
