import Foundation
@testable import VoiceInkCore

final class SettingsBackupPolicyTests: XCTestCase {
    private struct TestShortcutBackup: Codable, Equatable {
        let shortcut: String
    }

    func testBackupCategoriesPreserveMacOSImportOrderAndTitles() {
        XCTAssertEqual(
            VoiceInkSettingsBackupCategory.allCases.map(\.rawValue),
            ["general", "prompts", "powerMode", "dictionary", "customModels"]
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupCategory.allCases.map(\.title),
            [
                "General Settings",
                "Custom Prompts",
                "Power Mode",
                "Dictionary",
                "Custom Model Definitions"
            ]
        )
    }

    func testBackupImportPolicySummarizesAllAndSelectedCategories() {
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.categorySummary(
                for: Set(VoiceInkSettingsBackupCategory.allCases)
            ),
            "All settings"
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.categorySummary(for: [.dictionary, .prompts]),
            "Custom Prompts, Dictionary"
        )
    }

    func testBackupImportPolicyRemindsOnlyForAPIKeyDependentCategories() {
        XCTAssertFalse(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: []))
        XCTAssertFalse(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.general, .dictionary]))
        XCTAssertTrue(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.prompts]))
        XCTAssertTrue(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.powerMode]))
        XCTAssertTrue(VoiceInkSettingsBackupImportPolicy.needsAPIKeyReminder(for: [.customModels]))
    }

    func testBackupImportPolicyBuildsCurrentVersionWithFallback() {
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.currentVersion(bundleShortVersion: "2.4.0"),
            "2.4.0"
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportPolicy.currentVersion(bundleShortVersion: nil),
            "0.0.0"
        )
    }

    func testBackupVersionReviewReportsOnlyMismatches() {
        var events = [String]()

        VoiceInkSettingsBackupImportPolicy.versionReview(
            importedVersion: "2.4.0",
            currentVersion: "2.4.0"
        ).applyRuntimeState { importedVersion, currentVersion in
            events.append("\(importedVersion)->\(currentVersion)")
        }

        VoiceInkSettingsBackupImportPolicy.versionReview(
            importedVersion: "2.3.0",
            currentVersion: "2.4.0"
        ).applyRuntimeState { importedVersion, currentVersion in
            events.append("\(importedVersion)->\(currentVersion)")
        }

        XCTAssertEqual(events, ["2.3.0->2.4.0"])
    }

    func testBackupImportSelectionReviewAppliesMacOSImportFlowDecisions() throws {
        var events = [String]()

        try VoiceInkSettingsBackupImportPolicy.importSelectionReview(
            selectedCategories: nil
        ).applyRuntimeState(
            reportNoSettingsImported: {
                events.append("canceled")
            },
            reportEmptyCategorySelection: {
                events.append("empty")
            },
            importSelectedCategories: { categories in
                events.append("import:\(VoiceInkSettingsBackupImportPolicy.categorySummary(for: categories))")
            }
        )

        try VoiceInkSettingsBackupImportPolicy.importSelectionReview(
            selectedCategories: []
        ).applyRuntimeState(
            reportNoSettingsImported: {
                events.append("canceled")
            },
            reportEmptyCategorySelection: {
                events.append("empty")
            },
            importSelectedCategories: { categories in
                events.append("import:\(VoiceInkSettingsBackupImportPolicy.categorySummary(for: categories))")
            }
        )

        try VoiceInkSettingsBackupImportPolicy.importSelectionReview(
            selectedCategories: [.general, .dictionary]
        ).applyRuntimeState(
            reportNoSettingsImported: {
                events.append("canceled")
            },
            reportEmptyCategorySelection: {
                events.append("empty")
            },
            importSelectedCategories: { categories in
                events.append("import:\(VoiceInkSettingsBackupImportPolicy.categorySummary(for: categories))")
            }
        )

        XCTAssertEqual(
            events,
            [
                "canceled",
                "empty",
                "import:General Settings, Dictionary"
            ]
        )
    }

    func testBackupImportDiagnosticsPreserveMacOSStatusCopy() {
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.noGeneralSettingsMessage,
            "No general settings found in the imported file."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.noVocabularyWordsMessage,
            "No vocabulary words found in the imported file. Existing items remain unchanged."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.noWordReplacementsMessage,
            "No word replacements found in the imported file. Existing replacements remain unchanged."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.noDictionaryEntriesImportedMessage,
            "No new dictionary entries were imported."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.generalSettingsImportedMessage,
            "Successfully imported general settings."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.noCustomModelsMessage,
            "No custom models found in the imported file."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.saveFailedDescription(
                item: "dictionary entries",
                localizedDescription: "disk full"
            ),
            "Failed to save imported dictionary entries: disk full"
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.customPromptsImportedMessage(count: 3),
            "Successfully imported 3 custom prompts."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.powerModeConfigurationsImportedMessage(count: 2),
            "Successfully imported 2 Power Mode configurations."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.skippedInvalidReplacementsMessage(count: 4),
            "Skipped 4 invalid word replacements from the imported file."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.dictionaryEntriesImportedMessage(
                vocabularyWordCount: 2,
                wordReplacementCount: 1
            ),
            "Successfully imported 2 vocabulary words and 1 word replacements to SwiftData."
        )
        XCTAssertEqual(
            VoiceInkSettingsBackupImportDiagnostics.customModelsImportedMessage(count: 5),
            "Successfully imported 5 custom model definitions."
        )
    }

    func testBackupImportErrorPreservesMacOSSaveFailureCopy() {
        let error = VoiceInkSettingsBackupImportError.saveFailed(
            item: "dictionary entries",
            localizedDescription: "disk full"
        )

        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: error),
            "Failed to save imported dictionary entries: disk full"
        )
    }

    func testBackupPresentationPreservesMacOSPanelAndAlertCopy() {
        let presentation = VoiceInkSettingsBackupPresentation.macOS

        XCTAssertEqual(presentation.defaultFileName, "VoiceInk_Settings_Backup.json")
        XCTAssertEqual(presentation.exportPanelTitle, "Export VoiceInk Settings")
        XCTAssertEqual(presentation.exportPanelMessage, "Choose a location to save your settings.")
        XCTAssertEqual(presentation.importPanelTitle, "Import VoiceInk Settings")
        XCTAssertEqual(presentation.importPanelMessage, "Choose a settings backup, then select what you want to import.")
        XCTAssertEqual(presentation.importSelectionTitle, "Import Settings")
        XCTAssertEqual(presentation.importSelectionMessage, "Choose what to import from this backup.")
        XCTAssertEqual(presentation.allCategoriesTitle, "All")
        XCTAssertEqual(presentation.individualCategoriesTitle, "Individual categories")
        XCTAssertEqual(presentation.importActionTitle, "Import")
        XCTAssertEqual(presentation.cancelActionTitle, "Cancel")
        XCTAssertEqual(presentation.okActionTitle, "OK")
        XCTAssertEqual(presentation.configureAPIKeysActionTitle, "Configure API Keys")
        XCTAssertEqual(presentation.exportSuccessTitle, "Export Successful")
        XCTAssertEqual(presentation.exportErrorTitle, "Export Error")
        XCTAssertEqual(presentation.exportCanceledTitle, "Export Canceled")
        XCTAssertEqual(presentation.importCanceledTitle, "Import Canceled")
        XCTAssertEqual(presentation.importErrorTitle, "Import Error")
        XCTAssertEqual(presentation.versionMismatchTitle, "Version Mismatch")
        XCTAssertEqual(presentation.importSuccessTitle, "Import Successful")
    }

    func testBackupPresentationBuildsDynamicExportAndImportMessages() {
        let presentation = VoiceInkSettingsBackupPresentation.macOS

        XCTAssertEqual(
            presentation.exportSuccessMessage(fileName: "Roma.json"),
            "Your settings have been successfully exported to Roma.json."
        )
        XCTAssertEqual(
            presentation.exportSaveFailureMessage(localizedDescription: "disk full"),
            "Could not save settings to file: disk full"
        )
        XCTAssertEqual(
            presentation.exportEncodingFailureMessage(localizedDescription: "bad data"),
            "Could not encode settings to JSON: bad data"
        )
        XCTAssertEqual(
            presentation.versionMismatchMessage(importedVersion: "1.0", currentVersion: "2.0"),
            "The imported settings file (version 1.0) is from a different version than your application (version 2.0). Proceeding with import, but be aware of potential incompatibilities."
        )
        XCTAssertEqual(
            presentation.importFailureMessage(localizedDescription: "bad json"),
            "Error importing settings: bad json. The file might be corrupted or not in the correct format."
        )
    }

    func testBackupPresentationBuildsImportSuccessTextWithOptionalAPIKeyReminder() {
        let presentation = VoiceInkSettingsBackupPresentation.macOS

        XCTAssertEqual(
            presentation.importSuccessInformativeText(fileName: "Roma.json", categories: [.general]),
            """
            Settings imported successfully from Roma.json.

            Imported: General Settings.

            It is recommended to restart VoiceInk for all changes to take full effect.
            """
        )
        XCTAssertEqual(
            presentation.importSuccessInformativeText(fileName: "Roma.json", categories: [.prompts]),
            """
            Settings imported successfully from Roma.json.

            Imported: Custom Prompts.

            IMPORTANT: If you were using AI enhancement features, please make sure to reconfigure your API keys in the Enhancement section.

            It is recommended to restart VoiceInk for all changes to take full effect.
            """
        )
    }

    func testSettingsBackupFilePreservesMacOSLegacyDecodeDefaults() throws {
        let data = try XCTUnwrap("{}".data(using: .utf8))
        let backup = try JSONDecoder().decode(VoiceInkSettingsBackupFile<TestShortcutBackup>.self, from: data)

        XCTAssertEqual(backup.version, "0.0.0")
        XCTAssertEqual(backup.customPrompts, [])
        XCTAssertEqual(backup.powerModeConfigs, [])
        XCTAssertNil(backup.powerModeShortcuts)
        XCTAssertNil(backup.vocabularyWords)
        XCTAssertNil(backup.wordReplacements)
        XCTAssertNil(backup.generalSettings)
        XCTAssertNil(backup.customEmojis)
        XCTAssertNil(backup.customCloudModels)
    }

    func testSettingsBackupFileRoundTripsTopLevelSharedWireShape() throws {
        let promptId = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        let powerModeId = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
        let customModelId = UUID(uuidString: "00000000-0000-0000-0000-000000000703")!
        let backup = VoiceInkSettingsBackupFile<TestShortcutBackup>(
            version: "2.4.0",
            customPrompts: [
                VoiceInkCustomPrompt(
                    id: promptId,
                    title: "Roma",
                    promptText: "Clean dictation",
                    isActive: true,
                    icon: "sparkles",
                    description: "Polish transcript",
                    isPredefined: false,
                    triggerWords: ["roma"],
                    useSystemInstructions: true
                )
            ],
            powerModeConfigs: [
                PowerModeConfig(
                    id: powerModeId,
                    name: "Focus",
                    emoji: "F",
                    isAIEnhancementEnabled: true,
                    selectedPrompt: promptId.uuidString,
                    selectedTranscriptionModelName: "large-v3",
                    selectedLanguage: "en",
                    selectedAIProvider: "openai",
                    selectedAIModel: "gpt-4.1"
                )
            ],
            powerModeShortcuts: [
                powerModeId.uuidString: TestShortcutBackup(shortcut: "command-space")
            ],
            vocabularyWords: [
                VoiceInkVocabularyWordBackup(word: "VoiceInk")
            ],
            wordReplacements: [
                "voice ink": "VoiceInk"
            ],
            generalSettings: nil,
            customEmojis: ["F"],
            customCloudModels: [
                VoiceInkCustomCloudModelBackup(
                    id: customModelId,
                    name: "custom",
                    displayName: "Custom",
                    description: "Custom OpenAI-compatible model",
                    apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                    modelName: "whisper-1",
                    isMultilingualModel: true,
                    supportedLanguages: ["en": "English"],
                    apiKey: nil
                )
            ]
        )

        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(VoiceInkSettingsBackupFile<TestShortcutBackup>.self, from: data)

        XCTAssertEqual(decoded.version, "2.4.0")
        XCTAssertEqual(decoded.customPrompts.map(\.id), [promptId])
        XCTAssertEqual(decoded.customPrompts.map(\.title), ["Roma"])
        XCTAssertEqual(decoded.powerModeConfigs.map(\.id), [powerModeId])
        XCTAssertEqual(decoded.powerModeConfigs.map(\.name), ["Focus"])
        XCTAssertEqual(decoded.powerModeShortcuts, [powerModeId.uuidString: TestShortcutBackup(shortcut: "command-space")])
        XCTAssertEqual(decoded.vocabularyWords, [VoiceInkVocabularyWordBackup(word: "VoiceInk")])
        XCTAssertEqual(decoded.wordReplacements, ["voice ink": "VoiceInk"])
        XCTAssertEqual(decoded.customEmojis, ["F"])
        XCTAssertEqual(decoded.customCloudModels?.map(\.id), [customModelId])
        XCTAssertEqual(decoded.customCloudModels?.map(\.modelName), ["whisper-1"])
    }

    func testSettingsBackupFileCodecPreservesPrettyPrintedExportAndSharedDecode() throws {
        let backup = VoiceInkSettingsBackupFile<TestShortcutBackup>(
            version: "2.4.0",
            customPrompts: [],
            powerModeConfigs: [],
            powerModeShortcuts: nil,
            vocabularyWords: nil,
            wordReplacements: nil,
            generalSettings: nil,
            customEmojis: nil,
            customCloudModels: nil
        )

        let data = try VoiceInkSettingsBackupFileCodec.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded: VoiceInkSettingsBackupFile<TestShortcutBackup> = try VoiceInkSettingsBackupFileCodec.decode(from: data)

        XCTAssertTrue(json.contains("\n"))
        XCTAssertTrue(json.contains("  \"version\""))
        XCTAssertEqual(decoded.version, "2.4.0")
        XCTAssertEqual(decoded.customPrompts, [])
        XCTAssertEqual(decoded.powerModeConfigs, [])
    }
}
