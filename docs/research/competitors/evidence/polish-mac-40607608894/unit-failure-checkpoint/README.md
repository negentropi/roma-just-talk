# Unit failure checkpoint

[Run 40607608894](https://github.com/negentropi/roma-just-talk/actions/runs/40607608894), tested head `4b50179da8ea145738bae9dcd011aa6d93de8669`, **failed** during the full Mac unit suite. The app compiled and ran the tests. Swift Testing reported 325 tests in 34 suites, 31.320 seconds, and five issues in three correction cases.

| Case | Actual failed assertion |
| --- | --- |
| `failedApprovalSaveKeepsExistingRulesAndUnrelatedUnsavedEdits` | The snapshot after the read-only save failure contained three records rather than the original two. The proposed record remained present. Two issues at lines 214 and 216. |
| `failedSaveRemovesOnlyImportInsertionsAndPreservesUnrelatedDirtyEdits` | The first caller-context fetch after the failed import did not contain the expected one replacement. The log does not print the actual count. One issue at line 217. |
| `failedEditToggleAndDeleteRestoreOnlyTheirOwnEntry` | The first caller-context fetch after each failed deletion omitted the original row. Two issues at line 185, one for each seeded row. |

The fixtures use persistent read-only stores, disable autosave, and retain unsaved caller edits. The expected save failures include Cocoa error 513. The source and actual issue records establish these failure boundaries. They do not prove a corrected implementation.

The other assertions in these three cases did not record issues. Those controls include preserved unrelated dirty values, rejection of the writes, and restored record values after failed edit or enable-state changes. The backup count's actual value must remain unspecified because Swift Testing did not expand that expression.

The following 37 methods each have exactly one start, one passing result, and no issue in the retained log records. `positive-census.json` lists every method. `positive-records.log` retains all 74 start/result lines.

| Pinned test file | Actual passed methods |
| --- | ---: |
| `WritingActionUndoTests.swift` | 20 |
| `WritingActionUndoPipelineTests.swift` | 8 |
| `ClipboardRestorationOwnershipTests.swift` | 5 |
| `ShortcutBackupTests.swift` | 3 |
| `AudioFileTranscriptionPersistenceTests.swift` | 1 |

`source/` retains 14 whole files read from the tested Git head, including all three failing test files and the complete shared `CorrectionLibraryFixture`. `source/source-manifest.json` records each whole file's SHA-256 and byte count. It also records the original line ranges and hashes for the three exact method extractions in `source/red-methods/`. The copies were compared with `git show` before the persistence fixes. Keep the three whole failing test files unchanged for the candidate run.

The failed-step log was fetched once and remains on the remote worker at `/data/rjt-full-mac-40607608894/failed.log`, 15,101,012 bytes, SHA-256 `dbc626c9e7cffce26f9026341b55ed783f1b1f6d71df2febf51a911cac9e7e0c`. This checkpoint retains selected records rather than copying the 15 MB log to the local checkout. `failure-summary.json` preserves the raw aggregate and all five issue lines. Its 293 no-parameter starts and outcomes are a parser subset, not the suite total.

The retained excerpts also include SQLite warnings when the test fixture removes an open temporary store. These are fixture cleanup diagnostics. They do not establish corruption of a user's store or successful closure of the temporary database.

Live TextEdit/Safari, matched snippet regression, settings UI, and Release packaging steps were skipped after the unit failure. No new claim about those boundaries follows from this run. The parent evidence folder owns the full artifact and broader result audit. This subfolder fetched no app archive and contains only the narrow failure checkpoint.

Run `python3 audit.py` from this folder to verify the retained source hashes, exact method extractions, raw positive records, five failure anchors, and skipped downstream steps without running or downloading the app.
