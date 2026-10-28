import Foundation
import VoiceInkCore

final class WritingFeatureBackupTests: XCTestCase {
    func testLegacyBackupLeavesNewFeaturesAbsent() throws {
        let backup: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(
            from: Data("{\"generalSettings\":{}}".utf8)
        )
        XCTAssertNil(backup.spokenSnippets)
        XCTAssertNil(backup.generalSettings?.writingActions)
        XCTAssertTrue(backup.generalSettings?.shortcutBackupRecords.isEmpty == true)
    }

    func testFeatureBackupRoundTripsExactContentTargetsAndShortcuts() throws {
        let snippet = VoiceInkSpokenSnippet(trigger: "signature", content: " first\r\n\nlast \n", enabled: false)
        let actions = VoiceInkWritingActionPreferences(targetLanguages: ["zh-Hant", "fr"], selectedTargetLanguage: "fr")
        let shortcuts: [VoiceInkShortcutActionIdentifier: String] = [
            .translateRecording: "translate",
            .rewriteSelectionRecording: "rewrite",
            .draftRecording: "draft",
        ]
        let data = try VoiceInkSettingsBackupFileCodec.encode(
            makeBackup(snippets: [snippet], actions: actions, shortcuts: shortcuts)
        )
        let restored: VoiceInkSettingsBackupFile<String> = try VoiceInkSettingsBackupFileCodec.decode(from: data)

        XCTAssertEqual(restored.spokenSnippets, [snippet])
        XCTAssertEqual(restored.generalSettings?.writingActions, actions)
        XCTAssertEqual(restored.generalSettings?.shortcutBackupRecords, shortcuts)
        XCTAssertEqual(
            VoiceInkShortcutBackupPolicy.generalBackupShortcutExportPlan(availableActionIdentifiers: Set(shortcuts.keys)),
            [.translateRecording, .rewriteSelectionRecording, .draftRecording]
        )
        XCTAssertEqual(
            VoiceInkShortcutBackupPolicy.generalBackupShortcutImportPlan(importedActionIdentifiers: Set(shortcuts.keys))
                .map(\.actionIdentifier),
            [.translateRecording, .rewriteSelectionRecording, .draftRecording]
        )

        try withDefaults { defaults in
            defaults.set("ja", forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage)
            try VoiceInkWritingFeatureBackupImportPlan(backup: restored, categories: [.dictionary, .general])
                .apply(to: defaults)
            XCTAssertEqual(VoiceInkSpokenSnippets.load(from: defaults), [snippet])
            XCTAssertEqual(VoiceInkWritingActionPreferences.load(from: defaults), actions)
            XCTAssertEqual(defaults.string(forKey: VoiceInkUserDefaultsKey.selectedTranscriptionLanguage), "ja")
        }
    }

    func testInvalidSnippetBackupDoesNotApplyValidWritingPreferences() throws {
        try withDefaults { defaults in
            let original = VoiceInkSpokenSnippet(trigger: "old", content: "Keep me")
            try VoiceInkSpokenSnippets.save([original], to: defaults)
            try VoiceInkWritingActionPreferences().save(to: defaults)
            let oldSnippets = defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey)
            let oldActions = defaults.data(forKey: VoiceInkWritingActionPreferences.storageKey)
            let backup = try makeBackup(
                snippets: [VoiceInkSpokenSnippet(trigger: "", content: "Invalid")],
                actions: .init(targetLanguages: ["fr"], selectedTargetLanguage: "fr")
            )
            do {
                try VoiceInkWritingFeatureBackupImportPlan(backup: backup, categories: [.dictionary, .general])
                    .apply(to: defaults)
                XCTFail("Invalid snippets must reject the complete feature import")
            } catch {}
            XCTAssertEqual(defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey), oldSnippets)
            XCTAssertEqual(defaults.data(forKey: VoiceInkWritingActionPreferences.storageKey), oldActions)
        }
    }

    func testInvalidWritingTargetsRejectBeforeAnyFeatureMutation() throws {
        try withDefaults { defaults in
            try VoiceInkSpokenSnippets.save([.init(trigger: "old", content: "Keep me")], to: defaults)
            try VoiceInkWritingActionPreferences().save(to: defaults)
            let oldSnippets = defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey)
            let oldActions = defaults.data(forKey: VoiceInkWritingActionPreferences.storageKey)
            for actions in [
                VoiceInkWritingActionPreferences(targetLanguages: [], selectedTargetLanguage: ""),
                VoiceInkWritingActionPreferences(targetLanguages: ["en", "en"], selectedTargetLanguage: "en"),
                VoiceInkWritingActionPreferences(targetLanguages: ["not-a-language"], selectedTargetLanguage: "not-a-language"),
                VoiceInkWritingActionPreferences(targetLanguages: ["en"], selectedTargetLanguage: "fr"),
            ] {
                let backup = try makeBackup(snippets: [.init(trigger: "new", content: "New")], actions: actions)
                do {
                    try VoiceInkWritingFeatureBackupImportPlan(backup: backup, categories: [.dictionary, .general])
                        .apply(to: defaults)
                    XCTFail("Invalid targets must reject before saved snippets change")
                } catch {}
                XCTAssertEqual(defaults.data(forKey: VoiceInkSpokenSnippets.userDefaultsKey), oldSnippets)
                XCTAssertEqual(defaults.data(forKey: VoiceInkWritingActionPreferences.storageKey), oldActions)
            }
        }
    }

    func testImportCategoriesAndMissingFieldsPreserveUnselectedPreferences() throws {
        try withDefaults { defaults in
            let snippet = VoiceInkSpokenSnippet(trigger: "old", content: "Keep me")
            let actions = VoiceInkWritingActionPreferences(targetLanguages: ["fr"], selectedTargetLanguage: "fr")
            try VoiceInkSpokenSnippets.save([snippet], to: defaults)
            try actions.save(to: defaults)

            let oldBackup = try makeBackup()
            try VoiceInkWritingFeatureBackupImportPlan(backup: oldBackup, categories: [.dictionary, .general])
                .apply(to: defaults)
            XCTAssertEqual(VoiceInkSpokenSnippets.load(from: defaults), [snippet])
            XCTAssertEqual(VoiceInkWritingActionPreferences.load(from: defaults), actions)

            let emptyLibrary = try makeBackup(snippets: [], actions: .init())
            try VoiceInkWritingFeatureBackupImportPlan(backup: emptyLibrary, categories: [.dictionary])
                .apply(to: defaults)
            XCTAssertTrue(VoiceInkSpokenSnippets.load(from: defaults).isEmpty)
            XCTAssertEqual(VoiceInkWritingActionPreferences.load(from: defaults), actions)

            let invalidUnselectedLibrary = try makeBackup(
                snippets: [.init(trigger: "", content: "Invalid")], actions: .init()
            )
            try VoiceInkWritingFeatureBackupImportPlan(backup: invalidUnselectedLibrary, categories: [.general])
                .apply(to: defaults)
            XCTAssertEqual(VoiceInkWritingActionPreferences.load(from: defaults), .init())
        }
    }

    func testSharedResetClearsWritingFeaturesAndShortcutsOnlyWithinOwnedSettings() throws {
        try withDefaults { defaults in
            try VoiceInkSpokenSnippets.save([.init(trigger: "old", content: "Text")], to: defaults)
            try VoiceInkWritingActionPreferences(targetLanguages: ["fr"], selectedTargetLanguage: "fr").save(to: defaults)
            let actions: [VoiceInkShortcutActionIdentifier] = [.translateRecording, .rewriteSelectionRecording, .draftRecording]
            for action in actions { defaults.set("binding", forKey: action.shortcutStorageKey) }
            defaults.set("Keep", forKey: "UnrelatedPreference")

            VoiceInkSharedPreferenceReset.clearCoreUserSettings(from: defaults)

            XCTAssertNil(defaults.object(forKey: VoiceInkSpokenSnippets.userDefaultsKey))
            XCTAssertNil(defaults.object(forKey: VoiceInkWritingActionPreferences.storageKey))
            for action in actions { XCTAssertNil(defaults.object(forKey: action.shortcutStorageKey)) }
            XCTAssertEqual(defaults.string(forKey: "UnrelatedPreference"), "Keep")
        }
    }

    private func makeBackup(
        snippets: [VoiceInkSpokenSnippet]? = nil,
        actions: VoiceInkWritingActionPreferences? = nil,
        shortcuts: [VoiceInkShortcutActionIdentifier: String] = [:]
    ) throws -> VoiceInkSettingsBackupFile<String> {
        let emptyGeneral = try JSONDecoder().decode(VoiceInkGeneralSettingsBackupPayload<String>.self, from: Data("{}".utf8))
        return VoiceInkSettingsBackupFile(
            version: "1.95.2", customPrompts: [], powerModeConfigs: [], powerModeShortcuts: nil,
            vocabularyWords: nil, wordReplacements: nil,
            generalSettings: .init(
                shortcutBackupRecords: shortcuts,
                preferences: emptyGeneral.generalSettingsBackupPreferences,
                writingActions: actions
            ),
            customEmojis: nil, customCloudModels: nil, spokenSnippets: snippets
        )
    }

    private func withDefaults(_ run: (UserDefaults) throws -> Void) throws {
        let suite = "WritingFeatureBackupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try run(defaults)
    }
}
