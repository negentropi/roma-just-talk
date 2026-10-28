# Shared Core iOS compilation: 40605454469

[Hosted run](https://github.com/negentropi/roma-just-talk/actions/runs/40605454469), exact `794fa2595f943ae501bbe3407a9dd1120c678f76`, passed direct iOS Simulator Debug compilation and static packaging. The raw build log contains individual arm64 and x86_64 compilation entries for `UserDefaultsPreferences.swift`, `DictationProfile.swift`, `TranscriptionRunProcessor.swift` and `DictationPolish.swift`. [Receipt](receipt.json), [actual compilation lines](build-excerpt.txt).

All 600 bound source hashes and 46 tracked lock snapshots match pinned Git blobs. The lock count includes retained evidence snapshots. Only the allowed runner-generated iOS resolution metadata changes: both original iOS pins survive, the seed contains 42 pins and all 25 resolved pins match the original or canonical reviewed states and repositories. Other locks and source files stay unchanged through the build. Configuration, deep strict ad-hoc signature verification and static Whisper checks pass in the actual job.

One evidence artifact was downloaded directly to the remote server: 262,487 bytes, SHA-256 `bc19b747a024264549a9c3b3fa2ab39d4cb3e363d51bae60a16fdbdd2e981474`; all 23 members pass CRC. Original archive: `/data/rjt-writing-check-01a17bef/undo-ios-40605454469/compile-evidence.zip`. Raw build, dependency and resolution logs remain there. [Member hashes](artifact-members.json) identify retained files; generated Python bytecode is omitted. The 79.3 MB Simulator app artifact was not downloaded; its GitHub digest and CI executable/archive hashes remain metadata.

The [audit](audit.py) reads that original archive on the remote server. It binds both artifact metadata objects to the exact run, head and branch, verifies the pinned workflow/helper, then checks source, package and build receipts. [Git expectations verification](git-expectations-verification.json) records a separate local comparison against immutable Git blobs.

This proves compilation and static packaging only. No Simulator launch, runtime tests, microphone, keyboard, device, iOS Undo behavior or release proof. No full dependency checkout/tree census was retained.
