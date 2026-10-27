# Actual shortcut-backup decoder comparison

The same fourteen JSON cases ran against the actual old and candidate `ShortcutBackup` decoder declarations. The old decoder compiled successfully, then exited 1 with six failed assertions: malformed modern payloads containing valid legacy Carbon keys decoded instead of rejecting. All eight controls passed. The candidate compiled successfully, passed all fourteen cases and exited 0.

Controls cover absent-kind legacy Carbon decoding, both valid modern kinds, valid modern data taking precedence over conflicting Carbon fields, and rejection of missing/wrong-type legacy fields. This does not claim validation of every legacy numeric value.

Baseline source is `03887dd257c3ec296df35c44cac3f77870676580`, with the unchanged owning file retained as `baseline-ShortcutMigration.swift`. Candidate owning-file SHA-256 is `c62dfa1872e618993d36a87a23563cac0ac8ee9644cd2e527915598f30f6500b`. Both executables used the same unchanged full production `Shortcut.swift` and the same `Oracle.swift` hash `c1a39b01797312afdfb45de7160ddc0220416b9dc988525a9e1d60c8ffe6c614`.

## Extraction boundary

- `Backup-baseline.swift` and `Backup-candidate.swift` contain the actual `LegacyKeyboardShortcut` and `ShortcutBackup` declarations, copied from each owning file before `enum ShortcutMigration`. Only the unused `import VoiceInkCore` line was removed.
- The whole actual `Shortcut.swift` was compiled unchanged, including its real Codable representation and Carbon conversion.
- Its unrelated event-method signatures require `ShortcutMonitor.EventKind`. `EventKind.swift` retains that actual enum declaration in the original class namespace; no event-monitor implementation runs.
- The fixture enum in `Oracle.swift` is copied verbatim from retained `ShortcutBackupTests.swift`. The probe uses the real JSON decoder and production types; it contains no substitute decoder or `Shortcut` implementation.

`baseline-build.json` and `candidate-build.json` retain exact compiler commands, exit codes and elapsed times. The first system-framework compile took 21.8 seconds; the cached candidate compile took 0.95 seconds. This is not a performance comparison. Raw build/check logs and native exits are retained. No binaries, SDK caches or broader temporary directory were copied here.

The toolchain was recorded after the checks: Apple Swift 6.2, macOS 26.6.1, arm64, Command Line Tools SDK. Run `python3 docs/research/competitors/evidence/shortcut-backup-codec-20261028/analyze-result.py` from the repository to recheck source extraction, fixture identity, complete PASS/FAIL records and retained hashes.

Independent read-only review checked the source, extraction boundary, same fixtures, logs and retained hashes. No findings; see `independent-review.json`.

Scope: actual serialization source comparison. Full app compilation, the three new native app test methods, shortcut dispatch, Undo, UI, permissions, keyboard events, clipboard, Keychain and provider behavior are outside this probe. No release claim.
