# Correction persistence unit checkpoint

[Run 40613521362](https://github.com/negentropi/roma-just-talk/actions/runs/40613521362) tested `53d62fb11fbdb425781e1cab3b087a627c18dfc1`. Its Mac unit step passed. The overall workflow failed later in the settings UI step, and Release packaging was skipped. This folder records the unit result only.

The three unchanged regression cases that failed in [run 40607608894](../../polish-mac-40607608894/unit-failure-checkpoint/README.md) now each have exactly one concrete `Success` record and no failure issue in the decoded unit xcresult.

| Case | Old result | Candidate result |
| --- | --- | --- |
| `failedApprovalSaveKeepsExistingRulesAndUnrelatedUnsavedEdits` | Failure, two issues. The failed save left the proposed record visible. | Success, no issue |
| `failedSaveRemovesOnlyImportInsertionsAndPreservesUnrelatedDirtyEdits` | Failure, one issue. The first caller fetch had an unexpected replacement count. | Success, no issue |
| `failedEditToggleAndDeleteRestoreOnlyTheirOwnEntry` | Failure, two issues. Original rows disappeared from queries after failed deletion. | Success, no issue |

All three whole test files and their shared fixture are byte-identical between the old and candidate heads. They use actual persistent read-only SwiftData stores and retain unrelated unsaved caller edits. The candidate saves dictionary mutations in a private context, rolls back only that writer on failure, and refreshes the caller with an ordinary fetch after successful saves. This is actual application-service regression proof at those test boundaries.

The following 41 positive cases also each have exactly one concrete `Success` record and no issue. The first 37 were already successful in the old run and remain successful. The four new persistence cases ran only on the candidate.

| Test file | Candidate successful cases |
| --- | ---: |
| `WritingActionUndoTests.swift` | 20 |
| `WritingActionUndoPipelineTests.swift` | 8 |
| `ClipboardRestorationOwnershipTests.swift` | 5 |
| `ShortcutBackupTests.swift` | 3 |
| `AudioFileTranscriptionPersistenceTests.swift` | 1 |
| `DictionaryPersistenceIsolationTests.swift` | 4 |

The four new cases verify successful rule update, toggle, deletion, approval and import while preserving dirty rule and vocabulary bystanders. They also verify stale unchanged saves, same-state toggles, deleted retained rows, and exact NFD/NFC History source revisions with and without a duplicate rule. These new fixtures use an in-memory store and fresh contexts. They do not prove a closed-process disk reopen or visible SwiftUI query behavior.

`correction-group-results.json` also retains all 29 successful correction cases: six Library adapter, seven History approval, two context freshness, ten backup adapter, and four persistence isolation cases. Seven overlap the selected 44-case census. These two counts must not be added as distinct cases.

The complete decoded unit result has 340 summary records, containing 310 `Success` and 30 `Skipped` records. Two parameterized identifiers appear twice. There are 338 unique identifiers: nine successful Onboarding XCTest identifiers, plus 329 Swift Testing identifiers containing 299 `Success` and 30 `Skipped`. No failure message appears in the complete decoded unit result. These are xcresult identifier counts, not a claim of 340 distinct executions or a retained raw Swift Testing console aggregate.

`selected-unit-results.json` retains the 44 concrete candidate records, including their xcresult member paths, summary references and decoded summary hashes. `xcresult-census.json` pairs them with the old case records and failure issues. The Clipboard suite is top-level; the other selected suites extend `VoiceInkTests`. The auditor checks their exact identifiers rather than matching method-name substrings.

The full candidate decoded unit details remain at `/data/rjt-writing-check-01a17bef/40613521362/unit-details/details.json`, 5,075,554 bytes, SHA-256 `c0941f976ac2af5c6ae8892ed6dadccb8d9404823d89fa5f2f18cfc64f85e405`. The broad evidence owner fetched the full workflow artifact once. This subfolder fetched no artifact or GitHub log. Its selected JSON is an excerpt from that decoded result.

`source/` retains 24 whole files from the tested head: ten test files, seven unchanged gate/project/package files, and seven production files. `source-registry.json` records their sizes and hashes. The three old regression files, five files covering the 37 prior positives, context freshness tests, workflow, driver, project, scheme and package declarations are byte-identical to the old head. Actual toolchain, signing and dependency observations belong to the parent folder's broader audit; identical source declarations alone do not prove those runtime conditions.

`unit-environment-comparison.json` compares the original unit xcresult invocation records. Both used the macOS 26.5 SDK, macOS 26.6.2 build 25G83, arm64 target architecture, and an Apple M1 virtual machine with 7,168 MB memory. This is observed destination and SDK agreement. Those records do not retain an exact Xcode binary version, so no exact-version readback is claimed.

Run `python3 audit.py` inside this repository to check the selected result records, old/new outcomes, pinned source bytes and hashes. `audit-xcresult.py` can reproduce the census against the complete decoded candidate JSON and the old `unit-results.json`. This checkpoint does not accept the failed UI gate or the skipped Release gate.
