# Private SwiftData writer / dirty caller probe

Run [40610436627](https://github.com/negentropi/roma-just-talk/actions/runs/40610436627), exact commit `24aefe58af68787223bba974859b6ecf321145ca`. Xcode 26.6, Swift 6.3.3, macOS 26.6.2; actual SDK declarations retained.

120 independent subprocess/store cases completed. Each caller loaded A+B, then left B and a different Word unsaved. A private context updated, toggled, deleted, inserted, or batched changes; readonly cases failed and rolled back only that writer. Every first-observation method had a fresh case, for both mainContext and explicit ModelContext.

| First caller operation | Observed result |
| --- | --- |
| Ordinary full fetch | Updated/toggled A refreshed in the same object; B and Word edits preserved. Deleted A absent from query; C insert visible. |
| `includePendingChanges = false` | Dirty B reset to stored value in all 40 cases; Word still dirty and `hasChanges` still true. |
| `model(for:)` | A remained stale after update/toggle; held A returned after deletion. |
| `processPendingChanges` or 20 ms runloop before normal fetch | Same ordinary-fetch result; no extra refresh API established. |

Deleted A stayed attached with old properties and `isDeleted == false`, although query membership correctly excluded it. Those flags and `model(for:)` did not establish stored existence. Readonly saves failed with Cocoa error 513; private rollback/release preserved stored rows and ordinary queries preserved both unsaved bystanders.

[Verification](verification.json) and the [independent 7,148-check audit](independent-matrix-audit.json) summarize all cases. `rule-*.json` holds raw staged receipts; `rule-subprocess-results.json` records every exit/stage. Source, toolchain, public SDK declarations, build log and all raw child logs retained. Artifact fetched once; complete archive kept remotely under `/data/rjt-writing-check-01a17bef/40610436627/`.

This probes SDK behavior using minimal model types and eleven Rule scalar fields. It does not prove application services, SwiftUI `@Query`, visible UI, CloudKit, or a closed-process reopen. Production-model tests and native gates remain required.
