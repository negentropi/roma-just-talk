import XCTest
import RomaCore

final class IOSSettingsBackupTests: XCTestCase {
    func testCategoriesPreserveSelectiveImportOrderAndTitles() {
        XCTAssertEqual(
            RomaIOSSettingsBackupCategory.allCases.map(\.rawValue),
            ["general", "modes", "prompts", "dictionary", "customModels"]
        )
        XCTAssertEqual(
            RomaIOSSettingsBackupCategory.allCases.map(\.title),
            ["General Settings", "Modes", "Custom Prompts", "Dictionary", "Custom Model Definitions"]
        )
    }

    func testCodecRoundTripsSelectedCategoriesWithoutSecrets() throws {
        let mode = Mode(name: "Meeting")
        let model = RomaIOSCustomModelDefinition(
            id: UUID(),
            name: "private-model",
            displayName: "Private Model",
            description: "Portable metadata",
            apiEndpoint: "https://example.com/transcribe",
            modelName: "whisper-private",
            isMultilingualModel: true,
            supportedLanguages: ["en": "English"]
        )
        let backup = RomaIOSSettingsBackupFile(
            version: "1.2.3",
            modes: RomaIOSModesBackup(modes: [mode], selectedModeId: mode.id),
            dictionary: RomaIOSDictionaryBackup(
                vocabularyTerms: ["Roma"],
                wordReplacements: [
                    RomaWordReplacementRule(originalText: "voice ink", replacementText: "Roma")
                ]
            ),
            customModels: [model]
        )

        let data = try RomaIOSSettingsBackupCodec.encode(backup)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(json.contains("secret"))

        let decoded = try RomaIOSSettingsBackupCodec.decode(data)
        XCTAssertEqual(decoded.version, "1.2.3")
        XCTAssertEqual(decoded.availableCategories, [.modes, .dictionary, .customModels])
        XCTAssertEqual(decoded.modes?.modes.first?.name, "Meeting")
        XCTAssertEqual(decoded.dictionary?.vocabularyTerms, ["Roma"])
        XCTAssertEqual(decoded.customModels, [model])
    }

    func testCodecAcceptsOldPayloadWithoutVersion() throws {
        let decoded = try RomaIOSSettingsBackupCodec.decode(Data("{}".utf8))

        XCTAssertEqual(decoded.version, RomaIOSSettingsBackupCodec.fallbackVersion)
        XCTAssertTrue(decoded.availableCategories.isEmpty)
    }

    func testImportPlanAppliesOnlySelectedCategories() throws {
        let backup = RomaIOSSettingsBackupFile(
            version: "1",
            prompts: [],
            dictionary: RomaIOSDictionaryBackup(
                vocabularyTerms: ["Roma"],
                wordReplacements: []
            )
        )
        let plan = try RomaIOSSettingsBackupImportPlan(
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
        let backup = RomaIOSSettingsBackupFile(
            version: "1",
            general: sampleGeneral,
            customModels: []
        )
        let plan = try RomaIOSSettingsBackupImportPlan(
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
        let backup = RomaIOSSettingsBackupFile(version: "1", prompts: [])

        XCTAssertThrowsError(try RomaIOSSettingsBackupImportPlan(backup: backup, categories: []))
        XCTAssertThrowsError(try RomaIOSSettingsBackupImportPlan(
            backup: backup,
            categories: [.dictionary]
        ))
    }

    func testCustomModelBackupValidationUsesSharedPolicy() {
        let valid = RomaCustomCloudModelStoredRecord(
            id: UUID(),
            name: "private-model",
            displayName: "Private Model",
            description: "Portable metadata",
            apiEndpoint: "https://example.com/transcribe",
            modelName: "whisper-private",
            isMultilingualModel: true,
            supportedLanguages: [:]
        )

        XCTAssertEqual(RomaCustomCloudModelPolicy.storedRecordValidationErrors([valid]), [])

        let duplicate = RomaCustomCloudModelStoredRecord(
            id: UUID(),
            name: valid.name,
            displayName: "Duplicate",
            description: "Duplicate metadata",
            apiEndpoint: valid.apiEndpoint,
            modelName: valid.modelName,
            isMultilingualModel: false,
            supportedLanguages: [:]
        )
        XCTAssertEqual(
            RomaCustomCloudModelPolicy.storedRecordValidationErrors([valid, duplicate]),
            [RomaCustomCloudModelPolicy.invalidStoredNamesMessage]
        )

        let invalid = RomaCustomCloudModelStoredRecord(
            id: UUID(),
            name: "invalid-model",
            displayName: "Invalid",
            description: "Invalid metadata",
            apiEndpoint: "relative/path",
            modelName: " ",
            isMultilingualModel: false,
            supportedLanguages: [:]
        )
        XCTAssertEqual(
            RomaCustomCloudModelPolicy.storedRecordValidationErrors([invalid]),
            [RomaCustomCloudModelPolicy.invalidStoredConfigurationMessage]
        )
    }

    private var sampleGeneral: RomaIOSGeneralSettingsBackup {
        RomaIOSGeneralSettingsBackup(
            audioSessionTimeoutSeconds: 30,
            transcriptionCleanupSettings: RomaIOSTranscriptionCleanupBackup(
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
