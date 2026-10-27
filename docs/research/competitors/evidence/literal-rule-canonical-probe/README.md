# Literal-rule canonical matching probe

The actual production-engine extraction failed four Unicode assertions before the correction and passed them afterward. The repeated Japanese overlap control passed both lanes. This proves the small Foundation matching boundary exercised here. It does not prove the full Core executable or app integration.

Non-spaced legacy rules use Foundation case-insensitive string search. That search matches `é東京` against `e\u{301}東京`. The initial literal implementation used escaped ICU regex matching for the same phrase and missed its decomposed form. The corrected non-spaced literal branch uses Foundation search and advances one Unicode scalar from each match start to retain overlapping candidates. The spaced-script branch retains its existing ICU boundary policy.

## Retained artifacts

- [Receipt](receipt.json) records exact source, extracted-engine, oracle, harness, and raw-result hashes.
- [Raw result](raw-result.json) preserves the completed probe's stdout JSON. It was not regenerated during packaging.
- [Probe body](probe.py) retains the Python body executed through stdin. It reconstructs the previous source in memory and checks its known full-file SHA-256 before the first Swift execution.
- [Known-bad engine](known-bad-engine.swift) and [candidate engine](candidate-engine.swift) retain the exact extracted fragments. Each fragment excludes the fixed `import Foundation` prefix.
- [Oracle](oracle.swift) retains the identical Swift checks appended to both lane fragments.

The probe used `/usr/bin/swift -`, with a two-second timeout per child invocation. Both child invocations returned zero. The harness separately required the intended known-bad failures and all candidate passes. No Swift source or binary file was created by the stdin harness. The Swift interpreter could use its normal toolchain cache.

The saved engine fragments, oracle, and receipt were packaged after execution from the hash-checked source and retained harness. Packaging did not rerun Swift. Exact per-child stdout text and execution timestamps were not retained separately; `raw-result.json` is the actual completed harness stdout containing each parsed child's observations.

To rerun from the repository root, first compare the candidate source with the receipt's full-file hash, then run `python3 docs/research/competitors/evidence/literal-rule-canonical-probe/probe.py`. The harness asserts the reconstructed known-bad hash; the candidate hash check remains a separate prerequisite. This command executes the tiny native engine probe only. It does not run a model, provider, normal app, full Core gate, SwiftData migration, or UI.
