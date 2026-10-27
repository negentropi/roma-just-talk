# Core foundation verification

[Run 40576969692](https://github.com/negentropi/roma-just-talk/actions/runs/40576969692) passed at exact source `143ce8fbb4b2cc3f5a8383d98f7ce8443e018dd5`. All **1,744 registered Core checks passed once**, in declared order, with native exit 0 and no skipped checks. The prior 1,721 registrations remain in order; the 23 additions cover 14 full-record library/codec/preflight checks, seven draft-metadata checks and two style-preference checks.

The audit compares every retained PASS name with the pinned runner and verifies the complete 157-file source census against immutable Git blobs. Before/after source checks passed and final Git status was empty. Retained Core/NVIDIA/Xcode lock bytes match the tested revision with 22/22/41 pins. SwiftPM used `--force-resolved-versions --skip-update`; actual dependency checkout trees were not retained, so the receipt makes no checkout-source audit claim.

The 51,419-byte artifact was downloaded once, matched GitHub's SHA-256 `a0415a0d64229c2b2e26cd9e095dc97ed329ecc32b68db5cfbfd939991d04872`, and passed all ZIP CRC checks. All eleven original members, including the complete build/check log, remain under `artifact/`. Artifact metadata binds it to this exact run, branch and head. `download-receipt.json` records the download and member hashes.

Run `python3 docs/research/competitors/evidence/core-40576969692/analyze-result.py` from the repository to revalidate the retained source, registrations, log, locks and artifact members. `receipt.json` records the result and scope.

Independent read-only review recomputed the receipt and checked the raw log, complete source census, artifact associations and retained members. No findings; see `independent-review.json`.

Scope: actual native Core compilation and policy/codec checks. This does not establish app activation, stored-field migration, UI behavior, provider behavior, semantic quality, release readiness or a matched old-reader comparison. Toolchain was captured before compilation only. The successful run emitted the existing `--skip-update` deprecation warning.
