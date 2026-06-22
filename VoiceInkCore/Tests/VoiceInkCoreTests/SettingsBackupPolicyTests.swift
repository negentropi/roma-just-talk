import Foundation
@testable import VoiceInkCore

final class SettingsBackupPolicyTests: XCTestCase {
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
}
