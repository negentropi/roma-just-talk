import Foundation
import VoiceInkCore

final class UndoShortcutTests: XCTestCase {
    private struct Binding: Codable, Equatable {
        let keyCode: UInt16
        let modifierFlagsRawValue: UInt
    }

    func testUndoStartsUnassignedWithoutRecordingDefaultsOrLegacyAliases() throws {
        let action = VoiceInkShortcutActionIdentifier.undoLastWritingEdit
        XCTAssertEqual(action.storageName, "undoLastWritingEdit")
        XCTAssertEqual(action.shortcutStorageKey, "Shortcut_undoLastWritingEdit")
        XCTAssertTrue(action.isStoredShortcut)
        XCTAssertNil(action.recordingShortcutSlot)
        XCTAssertNil(action.legacyKeyboardShortcutName)
        XCTAssertNil(action.legacyKeyboardShortcutStorageKey)
        XCTAssertFalse(VoiceInkShortcutActionIdentifier.legacyKeyboardShortcutActions.contains(action))
        XCTAssertFalse(VoiceInkShortcutActionIdentifier.legacyCustomRecordingShortcutActions.contains(action))

        try withDefaults { defaults in
            defaults.register(defaults: VoiceInkRecordingShortcutPreference.registeredDefaults)
            XCTAssertNil(VoiceInkShortcutStoragePreference.shortcutData(for: action.shortcutStorageKey, from: defaults))
            XCTAssertFalse(VoiceInkShortcutStoragePreference.isShortcutCleared(for: action.shortcutStorageKey, from: defaults))
            let alias = "KeyboardShortcuts_undoLastWritingEdit"
            let sentinel = Data("unowned value".utf8)
            defaults.set(sentinel, forKey: alias)
            VoiceInkRecordingShortcutPreference.removeLegacyKeyboardShortcut(for: action, from: defaults)
            XCTAssertEqual(defaults.data(forKey: alias), sentinel)
            XCTAssertNil(defaults.object(forKey: action.shortcutStorageKey))
        }
    }

    func testUndoStorageRestoresStateAndResetClearsOnlyItsManagedBinding() throws {
        let key = VoiceInkShortcutActionIdentifier.undoLastWritingEdit.shortcutStorageKey
        let clearedKey = VoiceInkShortcutStoragePreference.clearedKey(for: key)
        let binding = Binding(keyCode: 16, modifierFlagsRawValue: 1 << 19)
        let bytes = try JSONEncoder().encode(binding)
        try withDefaults { defaults in
            defaults.set("Keep", forKey: "UnrelatedPreference")
            VoiceInkShortcutStoragePreference.saveShortcutData(bytes, for: key, to: defaults)
            let saved = VoiceInkShortcutStoragePreference.storedState(for: key, from: defaults)
            XCTAssertEqual(saved.shortcutData, bytes)
            XCTAssertNil(saved.clearedValue)
            VoiceInkShortcutStoragePreference.markShortcutCleared(for: key, to: defaults)
            XCTAssertNil(VoiceInkShortcutStoragePreference.shortcutData(for: key, from: defaults))
            XCTAssertTrue(VoiceInkShortcutStoragePreference.isShortcutCleared(for: key, from: defaults))
            VoiceInkShortcutStoragePreference.restoreStoredState(saved, for: key, to: defaults)
            let restored = try XCTUnwrap(VoiceInkShortcutStoragePreference.shortcutData(for: key, from: defaults))
            XCTAssertEqual(try JSONDecoder().decode(Binding.self, from: restored), binding)
            XCTAssertNil(defaults.object(forKey: clearedKey))

            for cleared in [false, true] {
                defaults.set(bytes, forKey: key)
                defaults.set(cleared, forKey: clearedKey)
                VoiceInkSharedPreferenceReset.clearCoreUserSettings(from: defaults)
                XCTAssertNil(defaults.object(forKey: key))
                XCTAssertNil(defaults.object(forKey: clearedKey))
                XCTAssertEqual(defaults.string(forKey: "UnrelatedPreference"), "Keep")
            }
        }
    }

    func testUndoBackupRoundTripsAndImportsWithoutRecordingSelection() throws {
        let action = VoiceInkShortcutActionIdentifier.undoLastWritingEdit
        let binding = Binding(keyCode: 16, modifierFlagsRawValue: 1 << 19)
        var requested = [VoiceInkShortcutActionIdentifier]()
        let records = VoiceInkShortcutBackupPolicy.generalBackupShortcutRecords { candidate -> Binding? in
            requested.append(candidate)
            return candidate == action ? binding : nil
        }
        XCTAssertEqual(requested.filter { $0 == action }.count, 1)
        XCTAssertEqual(records, [action: binding])
        let empty = try JSONDecoder().decode(VoiceInkGeneralSettingsBackupPayload<Binding>.self, from: Data("{}".utf8))
        let backup = VoiceInkSettingsBackupFile<Binding>(
            version: "test", customPrompts: [], powerModeConfigs: [], powerModeShortcuts: nil,
            vocabularyWords: nil, wordReplacements: nil,
            generalSettings: .init(shortcutBackupRecords: records, preferences: empty.generalSettingsBackupPreferences),
            customEmojis: nil, customCloudModels: nil
        )
        let bytes = try VoiceInkSettingsBackupFileCodec.encode(backup)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let general = try XCTUnwrap(json["generalSettings"] as? [String: Any])
        XCTAssertTrue(general["undoLastWritingEditShortcut"] != nil)
        let reopened: VoiceInkSettingsBackupFile<Binding> = try VoiceInkSettingsBackupFileCodec.decode(from: bytes)
        let restored = try XCTUnwrap(reopened.generalSettings?.shortcutBackupRecords)
        XCTAssertEqual(restored, [action: binding])
        XCTAssertEqual(VoiceInkShortcutBackupPolicy.generalBackupShortcutExportPlan(availableActionIdentifiers: Set(restored.keys)), [action])
        let plan = VoiceInkShortcutBackupPolicy.generalBackupShortcutImportPlan(importedActionIdentifiers: Set(restored.keys))
        XCTAssertEqual(plan.map(\.actionIdentifier), [action])
        XCTAssertNil(plan.first?.recordingShortcutSlot)
        XCTAssertNil(plan.first?.recordingShortcutSelection)
        try withDefaults { defaults in
            for item in plan {
                let value = try XCTUnwrap(restored[item.actionIdentifier])
                VoiceInkShortcutStoragePreference.saveShortcutData(try JSONEncoder().encode(value),
                                                                  for: item.actionIdentifier.shortcutStorageKey, to: defaults)
            }
            let stored = try XCTUnwrap(VoiceInkShortcutStoragePreference.shortcutData(for: action.shortcutStorageKey, from: defaults))
            XCTAssertEqual(try JSONDecoder().decode(Binding.self, from: stored), binding)
            XCTAssertNil(VoiceInkRecordingShortcutPreference.selection(for: .primary, from: defaults))
            XCTAssertNil(VoiceInkRecordingShortcutPreference.selection(for: .secondary, from: defaults))
        }
    }

    func testOldMissingAndNullUndoBackupsLeaveTheExistingBindingUntouched() throws {
        let key = VoiceInkShortcutActionIdentifier.undoLastWritingEdit.shortcutStorageKey
        let original = try JSONEncoder().encode(Binding(keyCode: 16, modifierFlagsRawValue: 1 << 19))
        for payload in [
            #"{"generalSettings":{}}"#,
            #"{"generalSettings":{"undoLastWritingEditShortcut":null}}"#,
            #"{"generalSettings":{"pasteLastTranscriptionShortcut":{"keyCode":9,"modifierFlagsRawValue":262144}}}"#
        ] {
            let backup: VoiceInkSettingsBackupFile<Binding> = try VoiceInkSettingsBackupFileCodec.decode(from: Data(payload.utf8))
            let records = try XCTUnwrap(backup.generalSettings?.shortcutBackupRecords)
            XCTAssertNil(records[.undoLastWritingEdit])
            let plan = VoiceInkShortcutBackupPolicy.generalBackupShortcutImportPlan(importedActionIdentifiers: Set(records.keys))
            XCTAssertFalse(plan.contains { $0.actionIdentifier == .undoLastWritingEdit })
            try withDefaults { defaults in
                VoiceInkShortcutStoragePreference.saveShortcutData(original, for: key, to: defaults)
                for item in plan {
                    let binding = try XCTUnwrap(records[item.actionIdentifier])
                    VoiceInkShortcutStoragePreference.saveShortcutData(try JSONEncoder().encode(binding),
                                                                      for: item.actionIdentifier.shortcutStorageKey, to: defaults)
                }
                XCTAssertEqual(VoiceInkShortcutStoragePreference.shortcutData(for: key, from: defaults), original)
            }
        }
    }

    func testInvalidTypedUndoBackupRejectsBeforeAnyShortcutApplication() throws {
        let key = VoiceInkShortcutActionIdentifier.undoLastWritingEdit.shortcutStorageKey
        let original = try JSONEncoder().encode(Binding(keyCode: 16, modifierFlagsRawValue: 1 << 19))
        let invalid: [Any] = ["binding", 42, [:], ["keyCode": "wrong", "modifierFlagsRawValue": 0],
                              ["keyCode": -1, "modifierFlagsRawValue": 0], ["keyCode": 16, "modifierFlagsRawValue": NSNull()]]
        try withDefaults { defaults in
            VoiceInkShortcutStoragePreference.saveShortcutData(original, for: key, to: defaults)
            for value in invalid {
                let input = try JSONSerialization.data(withJSONObject: ["generalSettings": ["undoLastWritingEditShortcut": value]])
                var applied = [VoiceInkShortcutActionIdentifier]()
                var rejected = false
                do {
                    let backup: VoiceInkSettingsBackupFile<Binding> = try VoiceInkSettingsBackupFileCodec.decode(from: input)
                    let records = backup.generalSettings?.shortcutBackupRecords ?? [:]
                    for item in VoiceInkShortcutBackupPolicy.generalBackupShortcutImportPlan(importedActionIdentifiers: Set(records.keys)) {
                        applied.append(item.actionIdentifier)
                        let binding = try XCTUnwrap(records[item.actionIdentifier])
                        VoiceInkShortcutStoragePreference.saveShortcutData(try JSONEncoder().encode(binding),
                                                                          for: item.actionIdentifier.shortcutStorageKey, to: defaults)
                    }
                } catch {
                    rejected = true
                }
                XCTAssertTrue(rejected)
                XCTAssertTrue(applied.isEmpty)
                XCTAssertEqual(VoiceInkShortcutStoragePreference.shortcutData(for: key, from: defaults), original)
            }
        }
    }

    private func withDefaults(_ operation: (UserDefaults) throws -> Void) throws {
        let name = "UndoShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try operation(defaults)
    }
}
