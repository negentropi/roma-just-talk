# Shared Core iOS compile: 40587704440

[Actual hosted run](https://github.com/negentropi/roma-just-talk/actions/runs/40587704440), exact `ebf629b4cf109f7a36109ccac7b20ac70f9f48ab`, passed direct iOS Simulator Debug compilation and static packaging. Both arm64 and x86_64 individually compiled `DictationProfile.swift`, `DictationPolish.swift` and `TranscriptionRunProcessor.swift` from the actual shared Core. [Receipt](receipt.json).

The one downloaded evidence archive is 252,728 bytes, SHA-256 `b03127e5b53a1e9d829facf11433a447327acf191901872adf4dcf9189ae2940`; all 23 members pass CRC. It remains on `/data` on the remote server. Raw build, dependency and resolution logs stay there; their sizes/hashes are retained in [artifact-members.json](artifact-members.json), with actual compilation lines in [build-excerpt.txt](build-excerpt.txt). The 79.3 MB Simulator app artifact was not downloaded; its GitHub digest and CI inner archive/executable receipts remain metadata only.

All 594 bound non-lock source hashes and 21 original lock snapshots match the pinned Git commit. The runner generated only the explicitly allowed iOS resolution metadata: both original iOS pins preserved, 42-pin seed from the existing original and canonical Mac graphs, 25 resolved pins with exact reviewed states and repositories (only terminal `.git` equivalence). The accepted graph and unrelated locks stayed unchanged through compilation. Config verification, deep strict signature verification and static Whisper checks succeeded in the actual job.

Independent source review approved the audit contracts before artifact arrival. The actual artifact required narrowing compile-line matching to individual `SwiftCompile normal <architecture> /path` entries, excluding the separate batched summary; no CI rerun or second download. The [audit](audit.py) then passed against the retained original remote archive.

This proves compilation and static packaging only. No Simulator launch, microphone, keyboard, device or iOS Light/Clarity feature behavior. The new profiles have no active iOS consumers. No full runtime dependency checkout/tree census was retained by this workflow.
