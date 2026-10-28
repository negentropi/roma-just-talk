import Foundation
import VoiceInkCore

final class ClarityStyleBackupTests: XCTestCase {
    func testStyleBackupRoundTripsAndAppliesEveryStableStyle() throws {
        for (style, rawValue) in [(VoiceInkClarityStyle.natural, "natural"), (.casual, "casual"), (.formal, "formal")] {
            let preferences = try backupPreferences(clarityStyle: style, clipboardRestoreDelay: 1.25)
            let data = try VoiceInkSettingsBackupFileCodec.encode(makeBackup(preferences: preferences))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let general = try XCTUnwrap(json["generalSettings"] as? [String: Any])
            XCTAssertEqual(json["version"] as? String, "2.4.0")
            XCTAssertEqual(general["clarityStyle"] as? String, rawValue)
            XCTAssertNil(json["clarityStyle"])
            let decoded: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(from: data)
            let restored = try XCTUnwrap(decoded.generalSettings?.generalSettingsBackupPreferences)

            try withDefaults { defaults in
                let snippets = try seedIndependentPreferences(defaults)
                VoiceInkClarityStyle.casual.save(to: defaults)
                var events = [String]()
                VoiceInkGeneralSettingsBackupPolicy.importPlans(from: restored).applyRuntimeState(
                    to: defaults,
                    applyRecordingShortcutImportPlan: { _ in events.append("shortcuts") },
                    applyMacOSShellImportPlan: { _ in events.append("shell") },
                    applyRecordingFeedbackImportPlan: { _ in events.append("feedback") },
                    reportImportedGeneralSettings: { events.append("reported") }
                )

                XCTAssertEqual(events, ["shortcuts", "shell", "feedback", "reported"])
                XCTAssertEqual(VoiceInkClarityStyle.current(in: defaults), style)
                XCTAssertEqual(defaults.string(forKey: VoiceInkClarityStyle.storageKey), rawValue)
                XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 1.25)
                assertIndependentPreferences(defaults, snippets: snippets)
            }
        }
    }

    func testMissingAndNullStylePreserveCurrentStyleOnLegacyImport() throws {
        for payload in [
            #"{"generalSettings":{"clipboardRestoreDelay":1.25}}"#,
            #"{"generalSettings":{"clarityStyle":null,"clipboardRestoreDelay":1.25}}"#
        ] {
            let backup: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(from: Data(payload.utf8))
            let preferences = try XCTUnwrap(backup.generalSettings?.generalSettingsBackupPreferences)
            XCTAssertNil(preferences.clarityStyle)

            try withDefaults { defaults in
                let snippets = try seedIndependentPreferences(defaults)
                VoiceInkClarityStyle.formal.save(to: defaults)
                VoiceInkGeneralSettingsBackupPolicy.applyCorePreferenceImportPlans(
                    VoiceInkGeneralSettingsBackupPolicy.importPlans(from: preferences), to: defaults
                )

                XCTAssertEqual(VoiceInkClarityStyle.current(in: defaults), .formal)
                XCTAssertEqual(defaults.string(forKey: VoiceInkClarityStyle.storageKey), "formal")
                XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 1.25)
                assertIndependentPreferences(defaults, snippets: snippets)
            }
        }
    }

    func testInvalidStyleRejectsBeforePreferenceOrLibraryMutation() throws {
        for value: Any in ["unknown-style", "Formal", 42] {
            let data = try JSONSerialization.data(withJSONObject: [
                "generalSettings": ["clarityStyle": value, "dictationProfile": "custom", "clipboardRestoreDelay": 1.25],
                "spokenSnippets": [["id": UUID().uuidString, "trigger": "new", "content": "Imported", "enabled": true]]
            ])
            try withDefaults { defaults in
                let snippets = try seedIndependentPreferences(defaults)
                VoiceInkClarityStyle.formal.save(to: defaults)
                var runtimeEvents = [String]()
                var rejected = false
                do {
                    let backup: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(from: data)
                    if let preferences = backup.generalSettings?.generalSettingsBackupPreferences {
                        VoiceInkGeneralSettingsBackupPolicy.importPlans(from: preferences).applyRuntimeState(
                            to: defaults,
                            applyRecordingShortcutImportPlan: { _ in runtimeEvents.append("shortcuts") },
                            applyMacOSShellImportPlan: { _ in runtimeEvents.append("shell") },
                            applyRecordingFeedbackImportPlan: { _ in runtimeEvents.append("feedback") },
                            reportImportedGeneralSettings: { runtimeEvents.append("reported") }
                        )
                    }
                    try VoiceInkWritingFeatureBackupImportPlan(backup: backup, categories: [.general, .dictionary]).apply(to: defaults)
                    XCTFail("An explicit invalid style must reject the complete backup before import")
                } catch DecodingError.dataCorrupted(let context) {
                    rejected = true
                    XCTAssertEqual(context.codingPath.map(\.stringValue), ["generalSettings", "clarityStyle"])
                } catch DecodingError.typeMismatch(_, let context) {
                    rejected = true
                    XCTAssertEqual(context.codingPath.map(\.stringValue), ["generalSettings", "clarityStyle"])
                }

                XCTAssertTrue(rejected)
                XCTAssertEqual(runtimeEvents, [])
                XCTAssertEqual(VoiceInkClarityStyle.current(in: defaults), .formal)
                XCTAssertEqual(VoiceInkPastePreference.clipboardRestoreDelay(from: defaults), 2.5)
                assertIndependentPreferences(defaults, snippets: snippets)
            }
        }
    }

    func testDefaultBackupOmitsStyleAndPreservesExistingWireKeys() throws {
        let data = try VoiceInkSettingsBackupFileCodec.encode(makeBackup(preferences: backupPreferences()))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let general = try XCTUnwrap(json["generalSettings"] as? [String: Any])

        XCTAssertEqual(Set(json.keys), Set(["version", "customPrompts", "powerModeConfigs", "generalSettings"]))
        XCTAssertEqual(json["version"] as? String, "2.4.0")
        XCTAssertNil(general["clarityStyle"])
        XCTAssertNil(general["dictationProfile"])
        let decoded: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(from: data)
        XCTAssertNil(decoded.generalSettings?.generalSettingsBackupPreferences.clarityStyle)
    }

    func testResetRemovesStylePreferenceAndReturnsNatural() throws {
        try withDefaults { defaults in
            VoiceInkClarityStyle.formal.save(to: defaults)
            VoiceInkDictationProfile.none.save(to: defaults)
            defaults.set("keep", forKey: "ClarityStyleBackupTests.unowned")

            VoiceInkSharedPreferenceReset.clearCoreUserSettings(from: defaults)

            XCTAssertNil(defaults.object(forKey: VoiceInkClarityStyle.storageKey))
            XCTAssertEqual(VoiceInkClarityStyle.current(in: defaults), .natural)
            XCTAssertNil(defaults.object(forKey: VoiceInkDictationProfile.storageKey))
            XCTAssertEqual(defaults.string(forKey: "ClarityStyleBackupTests.unowned"), "keep")
        }
    }

    private func backupPreferences(
        clarityStyle: VoiceInkClarityStyle? = nil,
        clipboardRestoreDelay: Double? = nil
    ) throws -> VoiceInkGeneralSettingsBackupPreferences {
        let empty = try JSONDecoder().decode(VoiceInkGeneralSettingsBackupPayload<String>.self, from: Data("{}".utf8))
            .generalSettingsBackupPreferences
        return VoiceInkGeneralSettingsBackupPolicy.backupPreferences(
            recordingShortcut: empty.recordingShortcut,
            macOSShell: empty.macOSShell,
            transcriptionAutoCleanup: empty.transcriptionAutoCleanup,
            audioCleanup: empty.audioCleanup,
            recordingFeedback: empty.recordingFeedback,
            transcriptionCleanup: empty.transcriptionCleanup,
            paste: VoiceInkPasteBackupPreferences(shouldRestoreClipboardAfterPaste: nil, clipboardRestoreDelay: clipboardRestoreDelay),
            clarityStyle: clarityStyle
        )
    }

    private func makeBackup(preferences: VoiceInkGeneralSettingsBackupPreferences) -> VoiceInkSettingsBackupFile<String> {
        VoiceInkSettingsBackupFile(
            version: "2.4.0", customPrompts: [], powerModeConfigs: [], powerModeShortcuts: nil,
            vocabularyWords: nil, wordReplacements: nil,
            generalSettings: VoiceInkGeneralSettingsBackupPayload<String>(shortcutBackupRecords: [:], preferences: preferences),
            customEmojis: nil, customCloudModels: nil
        )
    }

    private func seedIndependentPreferences(_ defaults: UserDefaults) throws -> [VoiceInkSpokenSnippet] {
        VoiceInkDictationProfile.none.save(to: defaults)
        VoiceInkPastePreference.saveClipboardRestoreDelay(2.5, to: defaults)
        defaults.set("ja", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
        let snippets = [VoiceInkSpokenSnippet(trigger: "existing", content: "Cafe\u{301} 🧪\r\nKeep", enabled: false)]
        try VoiceInkSpokenSnippets.save(snippets, to: defaults)
        return snippets
    }

    private func assertIndependentPreferences(_ defaults: UserDefaults, snippets: [VoiceInkSpokenSnippet]) {
        XCTAssertEqual(VoiceInkDictationProfile.current(in: defaults), .none)
        XCTAssertEqual(defaults.string(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage), "ja")
        XCTAssertEqual(VoiceInkSpokenSnippets.load(from: defaults), snippets)
    }

    private func withDefaults(_ operation: (UserDefaults) throws -> Void) throws {
        let suite = "ClarityStyleBackupTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try operation(defaults)
    }
}
