# Native AX action acknowledgement: matched red/green

[Run 40548782794](https://github.com/negentropi/roma-just-talk/actions/runs/40548782794) passed at source `737a8bb7aa4b1b07d20831b3ad4847692aed3054`, using Xcode 26.6 / macOS 26.6.2 arm64. One app and XCTest bundle were built once. Both lanes ran the same `testExternalAccessibilityWaitsForOneDelayedNativeButtonAction` oracle; only the external helper executable changed.

| Observed boundary | Old helper from `830d4521` | Candidate helper |
| --- | --- | --- |
| Native button callback count | 1 | 1 |
| Callback duration | 0.551255 s | 0.552065 s |
| Helper exit / native AX action error | 74 / `-25204` | 0 / 0 |
| XCTest outcome | One expected assertion failure, exit 65 | One pass, exit 0 |
| Action acknowledgement budget | Existing 250 ms element timeout | 2 s; setup succeeded |
| Recorded acknowledgement duration | Not recorded by old helper | 0.559069 s |

The old helper reported `cannotComplete` although its single real native-button callback completed. Its only test failure was the acknowledgement assertion at oracle line 140. The candidate waited for acknowledgement and passed. Both lanes had zero unexpected failures or skips; traversal, fixture-window identity, foreground state and actual AX trust checks succeeded.

App/test executable hashes and CDHashes stayed identical across both lanes. Helper binaries had different verified hashes. Fresh AX/microphone TCC rows matched the signed host requirement. Runtime observations matched each receipt's host PID to the exact compiled executable path. All 590 recorded source inputs stayed unchanged; the six key input hashes were independently checked against the immutable Git source.

`verification.json`, raw `baseline/boundary.json` and `candidate/boundary.json`, test logs, signature/TCC receipts and `retained-files.json` retain the compact evidence. The full 94,089,004-byte artifact remains on remote `/data`; its GitHub digest and ZIP CRC were verified. No large artifact was downloaded to the laptop.

This proves the helper acknowledgement fix against a controlled 550 ms native callback. It does not establish that the earlier Advanced disclosure action completed after its error; that run retained no post-action state. The original Advanced scenario and the full relevant suite still require a successful rerun. This is not Release validation.
