# Mac unit: approved corrections

The candidate implements explicit History approval, Dictionary review and full-record backup. [Full run 40655003105](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/microphone-native-id-full-40655003105/README.md) passes all eight settings UI workflows, independent read-only verification of the closed normal stores and Release build/packaging. The [application-service checkpoint](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/microphone-native-id-full-40655003105/unit-failure-checkpoint/README.md) passes all 29 correction cases, preserving three unchanged failed-save regression successes. Earlier [local-store upgrade](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/correction-library-store-40599070748/audit-summary.json), [matched context freshness](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/dictionary-context-40602009529/README.md) and [minimal-model SDK](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/swiftdata-save-probe-40610436627/README.md) proofs retain their separate scopes. The [verification status](implementation-plan.md#current-verification-status) records the current boundaries: the eight UI workflows do not cover backup conflict-dialog interaction, and automatic learning and CloudKit synchronization remain separate. No release was published. [User instructions](../../approved-corrections.md). Source descriptions below retain the discovery-time state.

## User contract

Choose a phrase from a displayed transcript, enter the desired spelling or phrase, review the exact future replacement, then approve it. Dictionary provides review, edit, disable and delete. Canceling approval changes nothing. Unrelated typing never creates a rule.

An approved correction is a deliberate library entry. It does not prove that the displayed text was inserted into another app. Current `Transcription.completed` is insufficient evidence: `TranscriptionPipeline` observes `pasteResult.didDeliverText` but does not persist that receipt or make delivery failure change the completed status.

History's existing original variant is processed text for many records. Do not relabel it as recovered raw recognition.

## Data and compatibility

Extend `WordReplacement` rather than adding a second learned-rule store. Keep its identity, creation date and enabled state. Add explicit matching kind and optional provenance with approval origin, source transcript UUID and source variant. Validate approval against the captured variant and text revision.

Existing rows retain the documented comma-separated-alternatives contract. New approved corrections represent one literal phrase, including commas. The candidate removes the process-wide enabled-rule cache and fetches copied rules from the supplied context for each operation. Light/Clarity keep their captured immutable snapshots; Custom reads its current operation's context. A failed fetch or invalid enabled record never becomes an empty cached library or an implicitly legacy rule.

### Older synced readers

The production dictionary configuration uses private CloudKit; `LOCAL_BUILD` disables it. An older app still reads `originalText` and `replacementText` as comma-alternative rules and ignores added matching-kind fields. Merely excluding literal rules from legacy backup maps is insufficient for that separate persisted-data contract.

New literal rows therefore use optional `literalOriginalText` and `literalReplacementText` payload fields and leave both old text fields exactly empty. Legacy rows retain their existing fields and have no literal payload. The canonical record adapter validates this distinction: unknown kinds, incomplete payloads and mixed representations reject rather than executing as legacy. Four optional kind/provenance fields accompany the two literal payload fields. Existing identity, date and enable columns retain their roles. UI, matching and full-record backup consume the validated canonical pair.

An [actual old-engine probe](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/correction-legacy-reader-projection/receipt.json) demonstrates why: placing `Acme, Inc.` in the old source field changes `Acme approved.`; an empty legacy pair preserves it exactly. The probe uses unmodified declarations from the actual tag. It does not establish SwiftData downgrade, older-client UI, CloudKit transport or account sync. Candidate persistence and full-record adapters still need native proof.

Apple requires forward-compatible records and separate production-schema deployment. See [Core Data models for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit) and [deploying the schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema). No CloudKit schema is changed or promoted by this local implementation task. Verify development-account mixed-version synchronization and deploy the additive fields before an explicitly authorized release.

Approved rules survive source-history deletion. Retain the explicitly saved phrase pair and a UUID reference without a cascading model relationship. If the source disappears, show that it is unavailable. Do not retain an extra full transcript merely for provenance.

Current backup exports replacements as `[String: String]`, losing identity, dates and enabled state. Add an optional versioned full-record array to the existing backup. New readers prefer it; old map-only backups retain their existing merge behavior. Do not put literal-comma corrections into a legacy map that older apps would reinterpret.

Claude Opus 5.5 owns History approval and Dictionary controls. GPT-6.1 Sol reviews them. Existing `WordReplacementView` has edit/delete controls but does not expose the model's enable flag.

## Engine prerequisites found during discovery

The replacement engine passes replacement text to a regex-template API without escaping it. No template-language promise was found in the reviewed UI, documentation or tests. Actual production-engine probes found:

| Rule | Current output | Required literal output |
| --- | --- | --- |
| `cost` to `$5.00` | `.00` | `$5.00` |
| `path` to `C:\Temp\$1` | Loses backslashes | `C:\Temp\$1` |

The unchanged extracted engine failed both literal cases. `a952ff67` now escapes replacement text, with the same production-engine fixture red on the old source and green on the candidate. [Retained receipt](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/literal-replacement/receipt.json). Existing comma alternatives and CJK controls passed. Shared core verification passed on `f901c372`; this fixes a prerequisite, not the approved-correction workflow.

The ASCII-only boundary pattern also changed `éclair` to `éclear` and `Romaé` to `RJTé`. The [matched Unicode proof](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/unicode-replacement/receipt.json) now records eight failures on the old engine and none on the candidate using the same five registered test methods. The correction blocks adjacent letters, marks and decimal digits outside the existing unspaced script ranges. Those original ranges, mixed Latin/CJK/Thai/Korean matches, and punctuation/underscore separators remain intact. [Run 40498370543](https://github.com/negentropi/roma-just-talk/actions/runs/40498370543) passed full shared-core and Mac unit verification on `b1161b7d`. This is not a claim of universal linguistic segmentation.

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

Do not split the input into gaps or use opaque placeholders. Gaps create false word boundaries. Spaced scripts retain the existing ICU boundary policy. Non-spaced matches use Foundation search and advance one Unicode scalar to find overlaps, preserving its canonical matching behavior and actual matched UTF-16 length. A tiny [same-oracle production-engine probe](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/literal-rule-canonical-probe/receipt.json) caught and corrected the initial regex mismatch for decomposed `é東京`; four checks failed before the correction, all five pass afterward. This proves that Foundation boundary only.

Fourteen registered Core tests use the pre-existing Codable/apply APIs with JSON fixtures, so the same source can run on the actual old implementation. They cover literal commas, terminal output, overlaps, crossing legacy matches, exact Unicode/dollars/backslashes, canonical matches, missing/invalid kinds, legacy encoding, edit-kind retention and omission from legacy maps. [Actual matched run 40571902653](https://github.com/negentropi/roma-just-talk/actions/runs/40571902653), exact `808c1a36`, ran all 1,721 checks in both lanes. The baseline passed all 1,707 old checks and three new controls; eleven new methods failed through 23 fixture assertions. The candidate passed all 1,721. The [independent review](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/literal-rules-40571902653/independent-review.json) verifies the same oracle and runner, complete source inventories, all 22 dependency pins, unchanged toolchain and retained artifact hashes. This proves the Core policy/codec boundary; no app approval, backup upgrade or stored-rule migration is claimed.

At app integration, read unknown stored matching kinds as unsupported data. Never turn an explicit unknown value into comma alternatives. The throwing Light/Clarity snapshot should fail preparation; Custom must not execute an invalid rule as legacy. Approval conflicts, enabled-state invalidation, provenance and persistent-store upgrades remain separate acceptance work.

## Independent Core backup preparation

`WordReplacementLibrary.swift` adds a version-1 full-record value and pure import preflight. Records retain UUID, creation date, enabled state, exact source/output strings, explicit matching kind and optional provenance. Manual library rows may omit provenance. History approval provenance uses `historyManual`, a transcript UUID and one of `recognition`, `processed` or `enhanced`; it stores no transcript relationship or copied transcript.

The optional top-level `wordReplacementLibrary` payload sits alongside the unchanged `wordReplacements` map. Missing payload stays absent. Present null, unsupported version, missing/null/unknown matching kind and incomplete provenance reject. A present empty record array remains present, so a future importer can prefer it over the legacy map. Existing Mac export/import does not read or write this payload yet; this preparation does not activate full-record backup.

Preflight never mutates input. Identical UUID records are idempotent; changing any field under the same UUID is a conflict. Identity equality compares actual UTF-8 and UTF-16 strings rather than Swift's canonical text equality. Whole literal sources compare case-insensitively for duplicate/conflict detection; equal output requires exact string bytes. Duplicates identify the retained existing or proposed record, including repeated imports of a duplicate. Legacy sources retain trimmed comma-alternative boundaries and preserve alternative order and multiplicity. Partial overlap, changed alternative order/multiplicity or different matching semantics requires review. Conflicts carry both complete records and their reason; any conflict prevents all proposed insertions.

Fourteen registered checks cover existing-codec JSON round trips, strict payload validation, legacy map controls, exact records, provenance and preflight outcomes. The first self-contained test class uses only the old public settings codec, allowing a later matched old-reader/candidate proof without new-API compilation failure. [Core run 40576969692](https://github.com/negentropi/roma-just-talk/actions/runs/40576969692), exact `143ce8fb`, passed all 1,744 registered checks, including these fourteen, seven draft metadata checks and two style preference checks. The [independent receipt](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/core-40576969692/README.md) verifies native exit 0, all 1,721 prior checks, the complete 157-file source census and unchanged lock bytes. Actual dependency checkout trees and a post-run toolchain snapshot were not retained. App adapters, stored-field migration, old-reader comparison and History/Dictionary approval remain pending.

## Library save isolation

Correction creation, editing, enabling, deletion and dictionary imports now commit through a private context with autosave disabled. The caller's pending edits constrain validation but are never saved or rolled back by that operation. A fresh writer also rechecks the stored rule revision, conflicts and History source before saving. Unchanged edits and duplicate approvals still perform those checks. Bulk vocabulary and replacement additions share one save before any other selected backup category is applied.

After a durable commit, a normal caller-context fetch refreshes registered rule values and query membership. The [actual SDK probe](https://github.com/negentropi/roma-just-talk/blob/99d0ebba40cfcd0f04a1536b4118cabe3a96a075/docs/research/competitors/evidence/swiftdata-save-probe-40610436627/README.md) measured this with both main and explicit contexts while preserving an unsaved rule and vocabulary word. A persisted-only fetch overwrote the dirty rule, so this path retains the default pending-change merge. A deleted retained object can still report that it is attached and not deleted; fresh writer lookup determines mutation authority. A refresh failure reports that the changes were saved and never rolls back or repeats the write. The probe is not an app or SwiftUI query test; actual app persistence and UI acceptance remain separate gates.
