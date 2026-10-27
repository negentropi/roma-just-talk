# Predecessor seed and schema-order diagnosis

[Run 40568776080](https://github.com/negentropi/roma-just-talk/actions/runs/40568776080), source `cc88b5b1e79a158e5665d81b7d179a42ebe12935`, failed before building the current app. Its two actual predecessor-host tests passed: seed, close/copy, then reopen in another process. All 35 stored fields and persistent identities agreed. Actual archived signing retained Hardened Runtime.

The driver rejected unordered `storedAttributes` permutations in otherwise equal schemas. Original raw/canonical JSON and the complete difference remain here. `schema-fixture-receipt.json` binds the regression inputs to the native artifact, host PIDs and source. The extracted old function reproduces the failure; the repaired function normalizes these same inputs without losing fields, defaults or meaningful array order. See `schema-canonicalization-regression.json` and `schema-integrated-self-test.jsonl` for that narrower verification.

`roma.dictation-store-seed-control-audit.json` records the one-download archive hash/CRC and independent retained-member, source, signature, native-test and closed-store checks. This is not current-app or new-field migration proof. Actual app startup attempted recorder pre-roll; microphone inactivity is not established.
