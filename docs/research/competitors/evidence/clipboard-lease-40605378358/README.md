# Clipboard restoration regression

[Run 40605378358](https://github.com/negentropi/roma-just-talk/actions/runs/40605378358) passed all five selected cases at `794fa2595f943ae501bbe3407a9dd1120c678f76`. The unchanged oracle reproduced three restoration failures on the old code and passed both controls. The candidate restores every original item format through overlapping writing pastes, a following ordinary paste and an earlier prepared clipboard context. The default two-second deadline is preserved; a newer user copy survives.

The [audit](independent-audit.json) verifies actual NSPasteboard values, timers, the live signed host and its exit, source hashes, the shared toolchain and 41 package checkouts. Each artifact was fetched once to remote storage. This uses controlled menu/document access; native editor delivery and the product Undo command remain separate acceptance checks. The five additional ownership tests compiled but were not selected in this run.

[Cross-run inputs](cross-lane-input-comparison.json) explicitly record nine differing static Whisper files after a rebuild. These clipboard cases invoke no ASR. This is a matched clipboard regression, without a claim that the whole apps or Whisper binaries are identical.

The old workflow's failed conclusion is retained: its exact three intended failures and two passing controls were valid, while an overbroad checker also rejected a benign Recorder log. The corrected classifier accepts those immutable raw observations and the candidate's five passes.
