# Invalid Local CLI identity fixture

[Run 40566195249](https://github.com/negentropi/roma-just-talk/actions/runs/40566195249), source `919670ae5b918afbfad6f4d88982a481c1c4b532`: actual Core/NVIDIA and all three service targets compiled in 162.12 seconds with the frozen 22-pin graph. Sources, locks, signed wrappers, and signatures stayed unchanged.

The comparison is **invalid**. All three native probes exited 2 at process identity checks; the supervisor recorded no verified root identity. Baseline/raw completed no case receipts; the candidate completed only pre-cancellation before the same identity failure. No intended old-version failure or candidate lifetime success was established. Owned fixture gates were released and all cleanup receipts reported no remaining children.

The original mismatched `ps` tuple was not retained. `darwin-ps-shape-observation.json` is a separate, tiny background Darwin experiment: long and spaced executable paths cause the mixed-column `comm` field to truncate, while `proc_pidpath` plus canonical path/device/inode identifies the exact file. It is mechanism evidence, not a reconstruction of missing CI output. No RJT app, provider, credentials, or UI was exercised by that experiment.

`receipt.json` summarizes the failed run. The original artifact was downloaded once, verified against GitHub's size/SHA-256, and retained in `artifact/`; the failed log was fetched once. Driver correction must retain strict process ownership and capture observed/expected native fields before retrying.
