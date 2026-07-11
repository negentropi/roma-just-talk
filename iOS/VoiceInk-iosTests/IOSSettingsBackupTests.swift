import XCTest
import VoiceInkCore

final class IOSSettingsBackupTests: XCTestCase {
    func testCategoriesPreserveSelectiveImportOrderAndTitles() {
        XCTAssertEqual(
            VoiceInkIOSSettingsBackupCategory.allCases.map(\.rawValue),
            ["general", "modes", "prompts", "dictionary", "customModels"]
        )
        XCTAssertEqual(
            VoiceInkIOSSettingsBackupCategory.allCases.map(\.title),
            ["General Settings", "Modes", "Custom Prompts", "Dictionary", "Custom Model Definitions"]
        )
    }

    func testCodecRoundTripsSelectedCategoriesWithoutSecrets() throws {
        let mode = Mode(name: "Meeting")
        let model = VoiceInkIOSCustomModelDefinition(
            id: UUID(),
            name: "private-model",
            displayName: "Private Model",
            description: "Portable metadata",
            apiEndpoint: "https://example.com/transcribe",
            modelName: "whisper-private",
            isMultilingualModel: true,
            supportedLanguages: ["en": "English"]
        )
        let backup = VoiceInkIOSSettingsBackupFile(
            version: "1.2.3",
            modes: VoiceInkIOSModesBackup(modes: [mode], selectedModeId: mode.id),
            dictionary: VoiceInkIOSDictionaryBackup(
                vocabularyTerms: ["Roma"],
                wordReplacements: [
                    VoiceInkWordReplacementRule(originalText: "voice ink", replacementText: "Roma")
                ]
            ),
            customModels: [model]
        )

        let data = try VoiceInkIOSSettingsBackupCodec.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(json.contains("secret"))

        let decoded = try VoiceInkIOSSettingsBackupCodec.decode(data)
        XCTAssertEqual(decoded.version, "1.2.3")
        XCTAssertEqual(decoded.availableCategories, [.modes, .dictionary, .customModels])
        XCTAssertEqual(decoded.modes?.modes.first?.name, "Meeting")
        XCTAssertEqual(decoded.dictionary?.vocabularyTerms, ["Roma"])
        XCTAssertEqual(decoded.customModels, [model])
    }

    func testCodecAcceptsOldPayloadWithoutVersion() throws {
        let decoded = try VoiceInkIOSSettingsBackupCodec.decode(Data("{}".utf8))

        XCTAssertEqual(decoded.version, VoiceInkIOSSettingsBackupCodec.fallbackVersion)
        XCTAssertTrue(decoded.availableCategories.isEmpty)
    }

    func testImportPlanAppliesOnlySelectedCategories() throws {
        let backup = VoiceInkIOSSettingsBackupFile(
            version: "1",
            prompts: [],
            dictionary: VoiceInkIOSDictionaryBackup(
                vocabularyTerms: ["Roma"],
                wordReplacements: []
            )
        )
        let plan = try VoiceInkIOSSettingsBackupImportPlan(
            backup: backup,
            categories: [.dictionary]
        )
        var events = [String]()

        try plan.applyRuntimeState(
            replaceCustomModels: { _ in events.append("models") },
            applyGeneral: { _ in events.append("general") },
            applyModes: { _ in events.append("modes") },
            applyPrompts: { _ in events.append("prompts") },
            applyDictionary: { dictionary in
                events.append("dictionary:\(dictionary.vocabularyTerms.joined())")
            }
        )

        XCTAssertEqual(events, ["dictionary:Roma"])
    }

    func testImportFailureBeforeLiveSettingsMutationPreservesRollbackBoundary() throws {
        let backup = VoiceInkIOSSettingsBackupFile(
            version: "1",
            general: sampleGeneral,
            customModels: []
        )
        let plan = try VoiceInkIOSSettingsBackupImportPlan(
            backup: backup,
            categories: [.general, .customModels]
        )
        var events = [String]()

        XCTAssertThrowsError(try plan.applyRuntimeState(
            replaceCustomModels: { _ in
                events.append("models")
                throw TestError.storage
            },
            applyGeneral: { _ in events.append("general") },
            applyModes: { _ in events.append("modes") },
            applyPrompts: { _ in events.append("prompts") },
            applyDictionary: { _ in events.append("dictionary") }
        ))
        XCTAssertEqual(events, ["models"])
    }

    func testImportPlanRejectsEmptyAndUnavailableSelections() {
        let backup = VoiceInkIOSSettingsBackupFile(version: "1", prompts: [])

        XCTAssertThrowsError(try VoiceInkIOSSettingsBackupImportPlan(backup: backup, categories: []))
        XCTAssertThrowsError(try VoiceInkIOSSettingsBackupImportPlan(
            backup: backup,
            categories: [.dictionary]
        ))
    }

    private var sampleGeneral: VoiceInkIOSGeneralSettingsBackup {
        VoiceInkIOSGeneralSettingsBackup(
            audioSessionTimeoutSeconds: 30,
            transcriptionCleanupSettings: VoiceInkIOSTranscriptionCleanupBackup(
                punctuationMode: .keep,
                isTextFormattingEnabled: true,
                lowercaseTranscription: false,
                removeFillerWords: true
            ),
            fillerWords: ["um"],
            selectedTranscriptionLanguage: "en",
            isVADEnabled: true,
            shouldPrewarmModel: false,
            appendTrailingSpace: true,
            isTranscriptionCleanupEnabled: true,
            transcriptionRetentionMinutes: 60,
            isAudioCleanupEnabled: true,
            audioRetentionDays: 7
        )
    }
}

private enum TestError: Error {
    case storage
}
