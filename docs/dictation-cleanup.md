# Choose dictation cleanup

In **models**, open the settings gear and choose a **Dictation Cleanup** profile. Close the Mac sheet with its close button or Escape.

| Profile | Behavior |
| --- | --- |
| **Custom** | Uses your existing formatting, filler words, dictionary, snippets, prompts and AI enhancement settings. Default for existing installations. |
| **None** | Keeps the exact text returned by speech recognition. Skips snippets, replacements, cleanup, AI, cursor capitalization and added spaces. |
| **Light** | Uses whole-dictation snippets, then a small deterministic hesitation rule and saved dictionary replacements. No AI. |
| **Clarity** | Uses whole-dictation snippets, or dictionary replacements followed by bounded AI cleanup in the selected style. |

Your libraries and Custom settings stay saved when you switch profiles. Inactive controls show the saved values; choose Custom to use them again. Recognition model, language, VAD and model-prompt controls keep their existing roles.

[Save an approved correction from History](approved-corrections.md) to add one literal phrase to Dictionary. Review its preview before approving; None continues to bypass replacements.

The choice applies globally. A recording captures it before microphone permission and Power Mode preparation. Each imported file captures it when that item starts processing; retranscription captures it when invoked. Later profile, style or library changes affect the next operation. Custom retains its existing live formatting and enhancement behavior.

Dedicated **Translate**, **Edit selected text** and **Draft** Writing Actions retain their separate behavior and AI settings.

## Light

With an explicitly saved English language choice, Light removes one opening `um, ` or `uh, ` before substantive text. For example, `Um, send it tomorrow.` becomes `send it tomorrow.` It preserves the remaining text exactly, then applies your saved replacements.

An automatic, missing or non-English language choice skips that hesitation step. Registered default English alone does not count as an explicit choice. Quotes, code, structured text, URLs and email addresses also protect the utterance from hesitation removal. Light does not apply Custom filler lists or remove meaningful repeated words.

For Light and Clarity, say a saved snippet trigger by itself to insert its content literally. Snippet content bypasses replacements and AI. Custom keeps its existing snippet behavior.

## Clarity and styles

Clarity requests punctuation, disfluency and small grammar repairs while preserving language, meaning, names, numbers, negation, uncertainty and substantive repetition.

- **Natural:** retain the speaker’s wording.
- **Casual:** allow small conversational phrasing changes.
- **Formal:** allow small grammar and register changes.

The saved style remains selected when you switch to another profile. Clarity uses the AI provider and model selected when the operation begins. This recording’s Power Mode AI overrides apply to Custom. Clarity does not select a Custom prompt or collect clipboard, screen or selected-text context.

Light and Clarity deliver their result literally, without cursor recasing, a trial prefix or an added trailing space.

## Failures and History

If Clarity cannot prepare a provider, the request fails, or its response cannot be decoded, RJT retains the untouched recognition text and reports the processing failure. An unreadable replacement library also preserves recognition text. Snippet matches take precedence over those unrelated preparation failures. Blank recognition stays exact and makes no AI request.

Cancellation before delivery suppresses the pending result. Starting another recording supersedes unfinished processing from the earlier active run; the older recording remains recoverable in History. Cancellation cannot remove text already inserted into another app.

New completed ordinary records retain recognition text separately from **Original**, which continues to mean the processed text before AI enhancement. History offers **Recognized** when that captured text differs from Original. **Enhanced** contains a successful AI result; a cleanup failure appears as a separate warning. Older records keep their existing labels and values because discarded recognition text cannot be recovered.

A retry that preserves raw text reports that outcome instead of claiming cleanup succeeded. A storage failure remains an error. None, Light and Clarity never paste an older transcript through the Special shortcut’s empty-recognition fallback.

## Backup and reset

Settings backup includes profile and style. Older backups that omit either leave the current choice unchanged. Explicit invalid values reject before import. Switching profiles preserves settings and libraries; the existing full data reset retains its normal deletion behavior and returns cleanup/style to Custom/Natural.

## Verification

The [implementation plan](research/competitors/clarity-run-plan-design.md) tracks native integration, new settings/History checks and storage upgrade verification. The [Custom/None plan](research/competitors/raw-profile-plan.md) records matched pipeline, real Whisper file import and native settings proof. [Twenty-seven independently reviewed Clarity samples](research/competitors/evidence/clarity-semantic-40582234931/independent-semantic-review.md) cover nine synthetic utterances and three styles through the tested Local CLI route. These samples do not establish general model quality, microphone accuracy or every editor/provider combination.
