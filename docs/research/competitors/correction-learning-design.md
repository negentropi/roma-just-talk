# Queued Mac unit: approved corrections

Design only. Add an explicit **Save correction** action in History before attempting automatic correction learning.

## User contract

Choose a phrase from a displayed transcript, enter the desired spelling or phrase, review the exact future replacement, then approve it. Dictionary provides review, edit, disable and delete. Canceling approval changes nothing. Unrelated typing never creates a rule.

An approved correction is a deliberate library entry. It does not prove that the displayed text was inserted into another app. Current `Transcription.completed` is insufficient evidence: `TranscriptionPipeline` observes `pasteResult.didDeliverText` but does not persist that receipt or make delivery failure change the completed status.

History's existing original variant is processed text for many records. Do not relabel it as recovered raw recognition.

## Data and compatibility

Extend `WordReplacement` rather than adding a second learned-rule store. Keep its identity, creation date and enabled state. Add explicit matching kind and optional provenance with approval origin, source transcript UUID and source variant. Validate approval against the captured variant and text revision.

Existing rows retain the documented comma-separated-alternatives contract. New approved corrections represent one literal phrase, including commas. Dictionary's existing enabled-rule cache remains the execution owner; every save, toggle and delete invalidates it.

Approved rules survive source-history deletion. Retain the explicitly saved phrase pair and a UUID reference without a cascading model relationship. If the source disappears, show that it is unavailable. Do not retain an extra full transcript merely for provenance.

Current backup exports replacements as `[String: String]`, losing identity, dates and enabled state. Add an optional versioned full-record array to the existing backup. New readers prefer it; old map-only backups retain their existing merge behavior. Do not put literal-comma corrections into a legacy map that older apps would reinterpret.

Claude Opus 5.5 owns History approval and Dictionary controls. GPT-6.1 Sol reviews them. Existing `WordReplacementView` has edit/delete controls but does not expose the model's enable flag.

## Engine prerequisites found during discovery

The replacement engine passes replacement text to a regex-template API without escaping it. No template-language promise was found in the reviewed UI, documentation or tests. Actual production-engine probes found:

| Rule | Current output | Required literal output |
| --- | --- | --- |
| `cost` to `$5.00` | `.00` | `$5.00` |
| `path` to `C:\Temp\$1` | Loses backslashes | `C:\Temp\$1` |

The unchanged extracted engine failed both literal cases. A proposed escaped-template version passed them and retained comma-alternative and CJK controls. Local receipt: `/tmp/rjt-replacement-literal.J1ZLyV`. Production has not been changed by this discovery.

The current spaced-script boundary pattern is ASCII-only. Separate probes found `éclair` becoming `éclear` and `Romaé` becoming `RJTé`. Fix those boundaries while retaining deliberate CJK substring matching. Tests must separate these semantics rather than claim universal Unicode behavior.

## Acceptance

1. Approve a correction through History. The next matching dictation uses it. Canceling approval produces no rule.
2. Matched known-bad/candidate tests prove literal dollar signs, backslashes and comma-containing phrases. Preserve documented legacy comma alternatives, longest overlap and script-specific boundaries.
3. Disable or delete an entry after warming the cache. The next output immediately reflects the change.
4. Review duplicate/conflicting rules before replacement. Do not silently overwrite another entry.
5. Round-trip identity, enabled state, matching kind and provenance through backup. Import old map-only backups using the existing contract.
6. Delete the source History record. The explicitly approved rule remains usable and its unavailable source is explained.
7. Inspect actual approval/Dictionary UI, keyboard use, persistence and failure recovery.

Automatic correction learning remains separate work. It needs a persisted successful-delivery receipt and reliable attribution of later edits to that exact owned range. This proposed History action does not establish those capabilities.
