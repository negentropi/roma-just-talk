# Use Writing Actions and spoken snippets

These features belong to the existing VoiceInk-based Mac app. They use your configured transcription model and AI provider.

## Set up Writing Actions

1. Open **style** and configure an AI provider.
2. Under **Writing Actions**, assign shortcuts for **Translate dictation**, **Edit selected text**, or **Draft from instructions**.
3. Under **Translation Target**, add the languages you use. Select a target and use the arrow controls to reorder favorites.

Writing Actions work when ordinary Enhancement is off. A translation target controls the output language. It does not change the transcription language or model.

## Translate or draft into a field

1. Focus an editable field in another app.
2. Press the action's shortcut and speak.
3. Press the same shortcut to finish.

Translate treats your speech as content to translate. Draft treats it as an instruction to write a message or document. Ordinary dictation keeps its existing behavior.

## Edit selected text

1. Select text in an editable field in another app.
2. Press the editing shortcut.
3. Say an instruction such as "Make this shorter" or "Rewrite this in Spanish."
4. Press the same shortcut to finish.

Keep the original app, field, text, and selection unchanged while processing runs. The app checks them before replacement. It refuses protected fields, read-only selections, and editors that do not expose the information needed to validate a replacement. It does not replace the whole document as a fallback.

Native editors use selected-text Accessibility writes. Browser fields use the captured app's Paste command. The browser route checks the original field, text, selection, cancellation, and clipboard ownership immediately before its single attempt. If a target change or newer clipboard copy is detected, delivery stops.

Browser delivery temporarily uses the clipboard; clipboard contents are not included in the AI request. After confirmed replacement, restoration follows your existing clipboard setting and preserves newer copies. If delivery cannot be confirmed, generated text remains on the clipboard and in History so a delayed paste cannot consume restored, unrelated content. Check the field before trying again.

If generation fails or the destination changes, the instruction is not inserted. Open **past** (History) to recover the recording, transcript, and any generated result. Canceling prevents delivery. Explicit writing actions do not use snippets, ordinary cleanup prompts, screen or clipboard context, or automatic Send.

## Save and use a snippet

1. Open **Dictionary**, then **Snippets**.
2. Choose **New Snippet**.
3. Enter a trigger and its saved content. Content can contain line breaks, links, punctuation, and spaces.
4. Save it and say the trigger during ordinary dictation.

A trigger can contain up to 60 characters. Content can contain up to 4,000 characters. Trigger matching ignores case and repeated spaces. The longest overlapping phrase wins. Latin and other spaced scripts require word boundaries. Saved expansions are not searched again for more triggers.

When a dictation contains a snippet trigger, its surrounding words stay as recognized. AI rewriting, cleanup, word replacements, cursor capitalization, and added trailing spaces are bypassed for that dictation. Saved content therefore stays literal. A trigger spoken alone inserts only the saved content, without final punctuation added by recognition.

Disable a snippet to keep it in the library without expanding it. Delete removes it from the library.

If the saved library cannot be read, edits and imports stop with an error and preserve the stored data. Restore a valid settings backup before making changes.

## Transfer snippets as CSV

Use **Export CSV** to save the library. Use **Import CSV** to review a file before merging it. The header is `trigger,content,enabled`; `enabled` is optional and defaults to `true`.

Quoted fields can contain commas, quotes, and line breaks. Duplicate triggers require an explicit keep, replace, or reject choice. Invalid rows block the import. Import does not silently keep only the valid rows.

The library holds up to 1,000 snippets. Import files must be no larger than 3 MB. Settings backup includes snippets, translation preferences, and writing shortcuts. Older backups without these fields leave them unchanged.

## Verification status

The first Mac batch passed [remote verification on `ebc92f1e`](https://github.com/negentropi/roma-just-talk/actions/runs/40507127520), including shared Core, full Mac units, five native checks, matched regressions, three actual settings workflows and Release packaging. The [retained receipt](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/mac-40507127520/debug-native-ui-release-summary.json) identifies the tested artifact and limits. The [CI app artifact](https://github.com/negentropi/roma-just-talk/actions/runs/40507127520/artifacts/12738825628) is an unreleased build.

Native delivery uses controlled recognition and provider output. Separate authenticated CLI samples cover bounded translation and rewrite meaning. Neither establishes human speech, physical shortcuts, compatibility with every editor or general provider quality. The [implementation plan](research/competitors/implementation-plan.md) records those remaining boundaries and later feature work.
