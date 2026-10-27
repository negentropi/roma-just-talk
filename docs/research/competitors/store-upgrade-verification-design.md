# Store upgrade verification for dictation polish

Design preparation only. No schema change, old-store creation, migration, build or runtime verification was performed for this document.

Felix selected cleanup levels, styles, corrections and undo as the next Mac priority. The current global Custom/None stage leaves the model classes unchanged. Later recognition metadata, approved-correction provenance and transform history need an actual old-store upgrade check before their storage changes are accepted.

## Observed owning declarations

The app explicitly sets `PRODUCT_MODULE_NAME = VoiceInk` in both Debug and Release. Its persisted model classes are top-level `Transcription`, `VocabularyWord`, `WordReplacement` and `SessionMetric` types. The displayed app name is separate from that module name. See [project settings](../../../VoiceInk.xcodeproj/project.pbxproj).

The [app container construction](../../../VoiceInk/VoiceInk.swift) supplies the schema in this order:

1. `Transcription`
2. `VocabularyWord`
3. `WordReplacement`
4. `SessionMetric`

It uses three named configurations and store files.

| Configuration | Model group | File | CloudKit setting |
| --- | --- | --- | --- |
| `default` | `Transcription` | `default.store` | `.none` |
| `dictionary` | `VocabularyWord`, `WordReplacement` | `dictionary.store` | `.none` with `LOCAL_BUILD`; otherwise `.private(VoiceInkAppIdentity.iCloudContainerIdentifier)` |
| `stats` | `SessionMetric` | `stats.store` | `.none` |

The files are under the existing app-specific Application Support directory. The app's factory catches persistent-container failure and tries an in-memory container. An upgrade test must throw on the original container error. A successful in-memory fallback cannot count as a migrated store.

The CloudKit condition is a compilation condition, not the Xcode configuration name. The [Makefile's `local` target](../../../Makefile) defines `LOCAL_BUILD` even with `CONFIGURATION=Release`. The verified first-batch CI Release artifact therefore uses the local dictionary configuration. It does not prove the other configuration's CloudKit behavior or the state of any deployed CloudKit schema.

No `VersionedSchema` or `SchemaMigrationPlan` declaration was found in the reviewed app or tests. Existing [model fixtures](../../../VoiceInkTests/VoiceInkTests.swift) and newer pipeline fixtures use in-memory stores. They do not establish an old persistent-store upgrade.

## Historical source bridge

The local `v1.95.1` tag resolves to `846d05df04d5821a7b5dc8588304cb58e3bd8368`.

The following four files are byte-identical between that tag and the verified first-batch source `ebc92f1e60fdabbb9e26b2817f414d154865a9d5`:

- [Transcription.swift](../../../VoiceInk/Models/Transcription.swift)
- [VocabularyWord.swift](../../../VoiceInk/Models/VocabularyWord.swift)
- [WordReplacement.swift](../../../VoiceInk/Models/WordReplacement.swift)
- [SessionMetric.swift](../../../VoiceInk/Models/SessionMetric.swift)

The four-model schema order and three-store factory in `VoiceInk.swift` are also unchanged. Its only diff between those revisions concerns the updater UI outside that factory.

This makes the verified `ebc92f1e` product a useful predecessor for seeding those model declarations with the reviewed build graph. A future receipt must record the tag, both commit IDs, exact model hashes and factory comparison. This source bridge does not establish every historical release, an existing user's actual store contents or live CloudKit compatibility.

## Entity identity must be observed

Source establishes the module and model declarations. It does not establish the framework's runtime persistent entity names or metadata hashes. Do not assume that copied `LegacyTranscription` classes, nested version enums or type aliases preserve them.

The installed public SwiftData SDK exposes `Schema.entities`, `Schema.Entity.name`, and Codable schema descriptions. It also exposes `Schema.entityName(for:)` on macOS 15 and later, and `PersistentIdentifier.entityName`. Future seed and candidate processes should emit actual names and a schema description instead of hardcoding guessed names. See [Apple's Schema documentation](https://developer.apple.com/documentation/swiftdata/schema).

## Recommended old-product to candidate test

Use hosted tests that import the actual `VoiceInk` product types. Build the same source-compatible seeding oracle against the pinned predecessor, then build candidate verification against the changed product. Keep temporary storage outside the normal app directory and reject any preexisting fixture directory.

1. Construct the old container using the actual four model classes and the same three configuration names and model groups. Give it explicit, unique on-disk URLs with CloudKit disabled. Require persistent configurations and successful saves.
2. Seed fixed UUIDs, dates, durations, model names, original/enhanced text, optional metadata, disabled replacements and legacy comma alternatives. Include decomposed Unicode, emoji, quotes and multiline text. Record exact UTF-8/UTF-16 values, schema description, actual entity names, model/source hashes, app identity and store paths.
3. Finish the old test and require its host process to exit. Clone the complete closed fixture directory, including any remaining WAL/SHM files. Preserve the seed directory unchanged. Do not copy only a live `.store` file.
4. Open the clone in the candidate product. Use a throwing container initializer and the intended store grouping. Do not route through `try?`, recreate the store or allow the app's memory fallback. Fetch every old row and verify its identity and values. Newly added optional fields must remain absent on old records; historical processed text must not be relabeled as recovered recognition output.
5. Write new metadata and new-format correction entries through the candidate. Save explicitly. Verify that existing disabled state and legacy matching semantics remain intact.
6. Exit the candidate process. Reopen the same candidate store in another process and verify both the preserved old values and new values. A fresh `ModelContext` in the same process is useful, but it is not this restart check.
7. Bind the result to exact source and model manifests, package pins, actual selected test IDs, binary/signature identity, process exits and store-directory receipts. Missing tests, skips, setup errors and container fallback are invalid proof.

Apple documents automatic migrations as part of `ModelContainer`. Use the real predecessor-to-candidate result to establish whether these particular additive changes work. Do not introduce a new versioned schema or aliases solely to make a test look like an upgrade. If automatic migration fails for the intended change, diagnose the concrete store error and then design the required migration. See [Apple's ModelContainer documentation](https://developer.apple.com/documentation/swiftdata/modelcontainer).

### Alternative considered

Two small native executables compiled from exact old/current model files could avoid rebuilding the full app. They would need the real Core dependencies, the same module name and a verified match to an actual old-product store and schema metadata. Without that comparison, the smaller executable is an approximation. Start with the hosted actual-product route; use a smaller probe only after its equivalence is established.

The local dictionary test proves local migration under the declared configuration. It does not initialize or promote a CloudKit schema, test account sync or establish an actual user's deployment. Apple's CloudKit guidance treats those as separate operations. See [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).

## Backup and iOS contracts

Mac and iOS replacements share a basic Core rule type but have separate persisted formats.

| Owner | Current contract |
| --- | --- |
| [Mac backup file](../../../VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift) | Optional top-level `wordReplacements` map from original string to replacement string. Missing or null is absent. Values must decode as strings. |
| [Mac export](../../../VoiceInk/Services/ImportExportService.swift) | Fetches all SwiftData replacements and projects each through `voiceInkRule`, which retains only the two strings. UUID, creation date, enable state and order are lost. Exact duplicate original keys keep the last replacement. |
| [Mac import](../../../VoiceInk/Services/BackupImporter.swift) | Additive. Conflicting existing names are skipped. New records receive fresh UUID/date values and enabled `true`, so a disabled row imported into an empty store becomes active under the current format. |
| [iOS backup DTO](../../../VoiceInkCore/Sources/VoiceInkCore/IOSSettingsBackup.swift) | Nested `dictionary` object with vocabulary strings and an array of `VoiceInkWordReplacementRule`. It is not the Mac map format. |
| [iOS backup manager](../../../iOS/VoiceInk-ios/IOSSettingsBackupManager.swift) | Reads and writes those arrays directly. Dictionary import replaces the current arrays. No automatic Mac/iOS replacement-backup conversion was found. |

The shared [replacement engine and rule](../../../VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift) currently encode two required strings. Runtime splits `originalText` on commas, trims alternatives and applies the longest first. No literal-comma escape exists. Existing rows retain this named data contract.

Adding required Codable fields to the shared rule without legacy decoding defaults would make old iOS arrays fail decoding. The [preference reader](../../../VoiceInkCore/Sources/VoiceInkCore/UserDefaultsPreferences.swift) catches decode failure and returns an empty array. New fields must therefore preserve old decoding deliberately.

The [iOS settings owner](../../../iOS/VoiceInk-ios/AppSettings.swift) passes rules into current transcription, history processing and audio retranscription. Enabled and matching-kind semantics must reach those callers if the shared type changes. The [iOS edit sheet](../../../iOS/VoiceInk-ios/IOSWordReplacementEditView.swift) uses a temporary UI UUID; shared edit logic reconstructs a two-string rule. It must preserve richer fields rather than reset them. Mac's existing edit mutates text on the same stored object.

For future approved corrections, add a distinct optional full-record backup field with explicit precedence over the legacy map. Preserve map decoding and its additive merge semantics. Do not emit literal-comma corrections into the legacy map for older readers. A Mac-only extra field can leave iOS source unchanged, but that alone provides no iOS portability.

Provenance should retain a transcript UUID and explicit source variant without introducing a cascading relationship to local transcript storage. Existing session metrics already use a transcription UUID across store groups. This preserves an approved correction when its source history entry is deleted.

## Ownership for the later implementation

A storage owner should handle actual model fields, old-store fixtures and restart verification. The dictionary owner should handle matching kind, legacy decoding, cache projection and backup import/export. Any shared Core rule change must include its iOS preference, editing and processing consumers. Claude Opus 5.5 owns user-facing History and Dictionary controls; GPT-6.1 Sol reviews that UI.

Prove It Works drove the old-binary and process-restart requirement. Laziness Protocol drove reuse of actual app models and store grouping. This remains a design artifact, not migration proof.
