# Exact SwiftData model probe

Diagnostic app only. No distribution qualification or production repair claim.

The `VoiceInk` executable target compiles unchanged copies of the four production model files. Its real `VoiceInkCore` dependency also builds the existing `VoiceInkNVIDIA` dependency graph. SwiftPM requires target sources inside the package directory, so the model copies are intentional and byte-checked before and after compilation.

The Xcode app lock omits some Core/NVIDIA dependencies. The probe binds the committed Xcode, Core and NVIDIA locks by exact hashes, merges their pins into a v2 lock and forces resolution from that lock. It rejects new package identities, changed versions or revisions, conflicting shared pins and dirty or mismatched actual checkouts. Identical revisions permit the existing `.git` URL spelling difference.

One observed shared-pin conflict has an explicit authority. Xcode pins Swift Atomics 1.3.0 at `b601256eab081c0f92f059e12818ac1d4f178ff7`. Core and NVIDIA pin 1.3.1 at `0442cb5a3f98ab802acb777929fdb446bda11a34`. Successful candidate run `37131204306`, source `71daeaee964811da3ec71ad66370eee1d013e5d0`, reports the compiled app graph using 1.3.0 in its Release, Debug and final package lists. The probe selects that app revision and retains both conflicting input pins in its receipt. No other revision conflict is allowed. Production lock files remain unchanged.

`build.sh` requires the observed Xcode 26.6 build 17F113, Swift 6.3.3 and SDK 26.5. The probe uses Swift language 5 and macOS minimum 14.2.1. It creates and signs a new diagnostic app wrapper. The wrapper is required because the reduced bare executable aborted on Sonoma before testing configuration behavior with `Unable to determine Bundle Name`.

```sh
bash Tools/SwiftDataExactModelProbe/build.sh \
  .swiftdata-exact-probe /path/to/fresh-build-directory
python3 Tools/SwiftDataExactModelProbe/run-cases.py \
  .swiftdata-exact-probe/VoiceInkSwiftDataExactProbe.app/Contents/MacOS/voiceink-swiftdata-probe \
  /path/to/fresh-observations
```

Copy the entire recorded app wrapper unchanged to the exact Sonoma guest. Run the same observer against its `Contents/MacOS` executable. Retain the observed OS version, build, architecture, bundle manifest, signature, child PID, log and exit status. Every case gets fresh task-owned store URLs in the guest's local temporary directory. Stores do not run on the shared output volume. After the child exits, the observer copies its SQLite files to the output for retention and records the original absolute store path and filesystem. The probe does not use application support files, production migration preferences or CloudKit accounts.

| Layout | Context cases | Storage mapping |
| --- | --- | --- |
| Combined | New MainActor context, container mainContext, detached context, ModelActor | The current three subset configurations share one full-schema container. |
| Separate stats | New MainActor context, detached context | Transcript and dictionary keep their original two-configuration container. Stats gets its own one-configuration container. |
| Separate domains | New MainActor context, detached context | Each existing store URL gets its own container and exact subset schema. |
| Full schema control | Detached context | All three configurations receive the full schema. This changes storage routing and is not a proposed repair. |

The observer records Core Data store version-hash metadata before the first SessionMetric fetch. A declared container schema alone does not prove that the backing store contains that entity. All four model fetches must return zero in the fresh fixture. Uncaught Objective-C exceptions terminate one child and preserve its raw result while later controls continue.

These cases test fresh metadata and entity lookup. They do not prove existing-store migration, dictionary CloudKit, saving, dashboard queries, transcription completion or normal downloaded-app first Open. A production change still needs the original app boundary to turn red to green on the same OS.
