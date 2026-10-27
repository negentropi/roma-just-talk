# Dictionary context comparison: invalid pretest attempt

[Run 40595186584](https://github.com/negentropi/roma-just-talk/actions/runs/40595186584), exact `a5601328e66d6949b5de052b81112ffadaeb1d1c`, was canceled after the old-baseline build failed. No native test ran. This is neither old-bug reproduction nor a passing candidate. [Receipt](receipt.json).

The actual old build archive records eleven copies of one error: the nonisolated setup helper called `DictionaryService.removeWordReplacement` inside `#require`, violating its main-actor isolation. The historical receiver itself was unchanged; only the identical public-API oracle was injected. Both full tracked source manifests match their pinned Git revisions. Candidate compilation was canceled before native execution.

The observations archive (289,146 bytes) and native build archive (444,712 bytes) were each downloaded once to remote `/data`; SHA-256 and all 23/7 CRC members verified. Raw 4.89/4.70 MB build logs stay there; an actual compiler excerpt and all source contracts remain here. The single `gh --log-failed` request returned zero bytes for the canceled run, so diagnosis uses the archived build output.

The follow-up marks the setup helper `@MainActor` and materializes its removal result before the macro. Both test-method bodies remain unchanged. The new common source hash is `3e76e3c168c50c73b028ba564746981cb0a82e5f0371d3a60174cde76b41cd33`; retry 40599068412 is tracked separately. No cache-behavior or CloudKit synchronization claim follows from this failed build.
