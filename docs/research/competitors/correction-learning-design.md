# Queued Mac unit: approved corrections

The approval flow remains design only. Shared matching preparation is implemented below; no History approval, SwiftData field, automatic learning or new literal entry is exposed yet. Add an explicit **Save correction** action before attempting automatic correction learning.

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

The unchanged extracted engine failed both literal cases. `a952ff67` now escapes replacement text, with the same production-engine fixture red on the old source and green on the candidate. [Retained receipt](evidence/literal-replacement/receipt.json). Existing comma alternatives and CJK controls passed. Shared core verification passed on `f901c372`; this fixes a prerequisite, not the approved-correction workflow.

The ASCII-only boundary pattern also changed `éclair` to `éclear` and `Romaé` to `RJTé`. The [matched Unicode proof](evidence/unicode-replacement/receipt.json) now records eight failures on the old engine and none on the candidate using the same five registered test methods. The correction blocks adjacent letters, marks and decimal digits outside the existing unspaced script ranges. Those original ranges, mixed Latin/CJK/Thai/Korean matches, and punctuation/underscore separators remain intact. [Run 40498370543](https://github.com/negentropi/roma-just-talk/actions/runs/40498370543) passed full shared-core and Mac unit verification on `b1161b7d`. This is not a claim of universal linguistic segmentation.

## Acceptance

1. Approve a correction through History. The next matching dictation uses it. Canceling approval produces no rule.
2. Matched known-bad/candidate tests prove literal dollar signs, backslashes and comma-containing phrases. Preserve documented legacy comma alternatives, longest overlap and script-specific boundaries.
3. Disable or delete an entry after warming the cache. The next output immediately reflects the change.
4. Review duplicate/conflicting rules before replacement. Do not silently overwrite another entry.
5. Round-trip identity, enabled state, matching kind and provenance through backup. Import old map-only backups using the existing contract.
6. Delete the source History record. The explicitly approved rule remains usable and its unavailable source is explained.
7. Inspect actual approval/Dictionary UI, keyboard use, persistence and failure recovery.

Automatic correction learning remains separate work. It needs a persisted successful-delivery receipt and reliable attribution of later edits to that exact owned range. This proposed History action does not establish those capabilities.

## Shared matching preparation

`VoiceInkWordReplacementRule` now has explicit legacy comma-alternative and literal kinds. Existing two-string construction and missing JSON kind preserve legacy behavior; legacy encoding retains its original two keys. Explicit null, wrong-type and unknown kinds reject rather than reinterpret comma-containing data. New literal kinds are not safe for an older array reader that ignores unknown keys. They must remain outside legacy export maps; full-record backup/import and version handling are prerequisites before app activation. Shared edit reconstruction preserves kind, but its legacy trim/duplicate validation is not yet a complete literal-editor contract.

Literal rules match the original input. Select non-overlapping source spans by leftmost start, longest matched UTF-16 length, then declared rule order. Keep those source spans present while running existing legacy passes over the full text, rejecting any legacy match that crosses a protected span. Apply accepted legacy edits right-to-left and remap protected offsets. Insert literal outputs last and stop. Replacement output never becomes another rule's input or boundary context. Legacy-only libraries retain their current sequential behavior; this is a bounded compatibility choice for stored comma configuration, not a newly discovered promise for arbitrary chains.

Do not split the input into gaps or use opaque placeholders. Gaps create false word boundaries. Spaced scripts retain the existing ICU boundary policy. Non-spaced matches use Foundation search and advance one Unicode scalar to find overlaps, preserving its canonical matching behavior and actual matched UTF-16 length. A tiny [same-oracle production-engine probe](evidence/literal-rule-canonical-probe/receipt.json) caught and corrected the initial regex mismatch for decomposed `é東京`; four checks failed before the correction, all five pass afterward. This proves that Foundation boundary only.

Fourteen registered Core tests use the pre-existing Codable/apply APIs with JSON fixtures, so the same source can run on the actual old implementation. They cover literal commas, terminal output, overlaps, crossing legacy matches, exact Unicode/dollars/backslashes, canonical matches, missing/invalid kinds, legacy encoding, edit-kind retention and omission from legacy maps. [Actual matched run 40571902653](https://github.com/negentropi/roma-just-talk/actions/runs/40571902653), exact `808c1a36`, ran all 1,721 checks in both lanes. The baseline passed all 1,707 old checks and three new controls; eleven new methods failed through 23 fixture assertions. The candidate passed all 1,721. The [independent review](evidence/literal-rules-40571902653/independent-review.json) verifies the same oracle and runner, complete source inventories, all 22 dependency pins, unchanged toolchain and retained artifact hashes. This proves the Core policy/codec boundary; no app approval, backup upgrade or stored-rule migration is claimed.

At app integration, read unknown stored matching kinds as unsupported data. Never turn an explicit unknown value into comma alternatives. The throwing Light/Clarity snapshot should fail preparation; Custom must not execute an invalid rule as legacy. Approval conflicts, enabled-state invalidation, provenance and persistent-store upgrades remain separate acceptance work.
