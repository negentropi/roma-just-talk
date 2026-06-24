import Foundation
@testable import VoiceInkCore

final class CustomCloudModelPolicyTests: XCTestCase {
    func testGeneratedNamePreservesExistingLowercaseSpaceReplacementPolicy() {
        XCTAssertEqual(
            VoiceInkCustomCloudModelPolicy.generatedName(fromDisplayName: "My Custom Model"),
            "my-custom-model"
        )
    }

    func testNormalizedDraftPreservesCurrentMacOSFormPreparation() {
        let draft = VoiceInkCustomCloudModelPolicy.normalizedDraft(
            displayName: " My Custom Model ",
            apiEndpoint: " https://api.example.com/v1/audio/transcriptions ",
            apiKey: " key ",
            modelName: " whisper-1 "
        )

        XCTAssertEqual(
            draft,
            VoiceInkCustomCloudModelDraft(
                name: "my-custom-model",
                displayName: "My Custom Model",
                apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                apiKey: "key",
                modelName: "whisper-1"
            )
        )
    }

    func testRequiredFieldPolicyMatchesMacOSButtonEnablement() {
        XCTAssertFalse(
            VoiceInkCustomCloudModelPolicy.hasRequiredFields(
                VoiceInkCustomCloudModelPolicy.normalizedDraft(
                    displayName: " ",
                    apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                    apiKey: "key",
                    modelName: "whisper-1"
                )
            )
        )

        XCTAssertTrue(
            VoiceInkCustomCloudModelPolicy.hasRequiredFields(
                VoiceInkCustomCloudModelPolicy.normalizedDraft(
                    displayName: "Custom",
                    apiEndpoint: "not a url",
                    apiKey: "key",
                    modelName: "whisper-1"
                )
            )
        )
    }

    func testMacOSFormControlPresentationOwnsSubmitState() {
        let draft = VoiceInkCustomCloudModelPolicy.normalizedDraft(
            displayName: "Custom",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "key",
            modelName: "whisper-1"
        )
        let ready = VoiceInkCustomCloudModelPolicy.formControlPresentation(
            for: draft,
            isSaving: false
        )

        XCTAssertEqual(
            ready,
            VoiceInkCustomCloudModelFormControlPresentation(
                isSubmitProgressVisible: false,
                isSubmitButtonDisabled: false,
                usesEnabledSubmitStyle: true
            )
        )

        XCTAssertEqual(
            VoiceInkCustomCloudModelPolicy.formControlPresentation(
                for: draft,
                isSaving: true
            ),
            VoiceInkCustomCloudModelFormControlPresentation(
                isSubmitProgressVisible: true,
                isSubmitButtonDisabled: true,
                usesEnabledSubmitStyle: true
            )
        )

        XCTAssertEqual(
            VoiceInkCustomCloudModelPolicy.formControlPresentation(
                for: VoiceInkCustomCloudModelPolicy.normalizedDraft(
                    displayName: "",
                    apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                    apiKey: "key",
                    modelName: "whisper-1"
                ),
                isSaving: false
            ),
            VoiceInkCustomCloudModelFormControlPresentation(
                isSubmitProgressVisible: false,
                isSubmitButtonDisabled: true,
                usesEnabledSubmitStyle: false
            )
        )
    }

    func testValidationReturnsExistingMacOSErrorsInOrder() {
        let errors = VoiceInkCustomCloudModelPolicy.validationErrors(
            for: VoiceInkCustomCloudModelDraft(
                name: " ",
                displayName: "",
                apiEndpoint: "not a url",
                apiKey: "\n",
                modelName: " "
            ),
            existingModels: []
        )

        XCTAssertEqual(
            errors,
            [
                "Name cannot be empty",
                "Display name cannot be empty",
                "API endpoint must be a valid URL",
                "API key cannot be empty",
                "Model name cannot be empty"
            ]
        )
    }

    func testValidationRejectsDuplicateNameUnlessEditingSameModel() {
        let id = UUID()
        let draft = VoiceInkCustomCloudModelDraft(
            name: "custom",
            displayName: "Custom",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "key",
            modelName: "whisper-1"
        )

        XCTAssertEqual(
            VoiceInkCustomCloudModelPolicy.validationErrors(
                for: draft,
                existingModels: [VoiceInkCustomCloudModelIdentity(id: id, name: "custom")]
            ),
            ["A model with this name already exists"]
        )

        XCTAssertEqual(
            VoiceInkCustomCloudModelPolicy.validationErrors(
                for: draft,
                existingModels: [VoiceInkCustomCloudModelIdentity(id: id, name: "custom")],
                excludingId: id
            ),
            []
        )
    }

    func testMacOSFormPresentationPreservesDefaultsAndCopy() {
        let presentation = VoiceInkCustomCloudModelFormPresentation.macOS

        XCTAssertEqual(presentation.defaultAPIEndpoint, "https://api.example.com/v1/audio/transcriptions")
        XCTAssertEqual(presentation.defaultModelName, "large-v3-turbo")
        XCTAssertTrue(presentation.defaultIsMultilingual)
        XCTAssertEqual(presentation.compatibilityWarningText, "Only OpenAI-compatible transcription APIs are supported")
        XCTAssertEqual(presentation.displayNameFieldTitle, "Display Name")
        XCTAssertEqual(presentation.displayNamePlaceholder, "My Custom Model")
        XCTAssertEqual(presentation.apiEndpointFieldTitle, "API Endpoint")
        XCTAssertEqual(presentation.apiEndpointPlaceholder, "https://api.example.com/v1/audio/transcriptions")
        XCTAssertEqual(presentation.apiKeyFieldTitle, "API Key")
        XCTAssertEqual(presentation.apiKeyPlaceholder, "your-api-key")
        XCTAssertEqual(presentation.modelNameFieldTitle, "Model Name")
        XCTAssertEqual(presentation.modelNamePlaceholder, "whisper-1")
        XCTAssertEqual(presentation.multilingualToggleTitle, "Multilingual Model")
        XCTAssertEqual(presentation.validationAlertTitle, "Validation Errors")
        XCTAssertEqual(presentation.validationAlertDismissButtonTitle, "OK")
        XCTAssertEqual(presentation.defaultModelDescription, "Custom transcription model")
        XCTAssertEqual(
            presentation.keychainSaveFailureMessage,
            "Failed to securely save API Key to Keychain. Please check your system settings or try again."
        )
    }

    func testMacOSFormPresentationSelectsAddAndEditLabelsAndIcons() {
        let presentation = VoiceInkCustomCloudModelFormPresentation.macOS

        XCTAssertEqual(presentation.buttonTitle(isEditing: false), "Add Model")
        XCTAssertEqual(presentation.buttonTitle(isEditing: true), "Edit Model")
        XCTAssertEqual(presentation.title(isEditing: false), "Add Custom Model")
        XCTAssertEqual(presentation.title(isEditing: true), "Edit Custom Model")
        XCTAssertEqual(presentation.submitButtonTitle(isEditing: false), "Add Model")
        XCTAssertEqual(presentation.submitButtonTitle(isEditing: true), "Update Model")
        XCTAssertEqual(presentation.addButtonSystemImageName, "plus")
        XCTAssertEqual(presentation.closeSystemImageName, "xmark")
        XCTAssertEqual(presentation.warningSystemImageName, "exclamationmark.triangle.fill")
        XCTAssertEqual(presentation.submitButtonSystemImageName(isEditing: false), "plus.circle.fill")
        XCTAssertEqual(presentation.submitButtonSystemImageName(isEditing: true), "checkmark.circle.fill")
    }

    func testBackupRecordPreservesExistingCodableShapeAndImportNormalization() throws {
        let id = UUID(uuidString: "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE")!
        let backup = VoiceInkCustomCloudModelBackup(
            id: id,
            name: "custom",
            displayName: "Custom",
            description: "Transcribes audio",
            apiEndpoint: " https://api.example.com/v1/audio/transcriptions ",
            modelName: " whisper-1 ",
            isMultilingualModel: true,
            supportedLanguages: ["en": "English"],
            apiKey: " "
        )

        XCTAssertEqual(backup.normalizedAPIEndpointForImport, "https://api.example.com/v1/audio/transcriptions")
        XCTAssertEqual(backup.normalizedModelNameForImport, "whisper-1")
        XCTAssertEqual(backup.apiKeyForImport, Optional(" "))

        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(VoiceInkCustomCloudModelBackup.self, from: data)
        XCTAssertEqual(decoded, backup)
    }

    func testBackupRecordBuildsSharedImportPlanForMacOSAdapter() {
        let id = UUID(uuidString: "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE")!
        let backup = VoiceInkCustomCloudModelBackup(
            id: id,
            name: "custom",
            displayName: "Custom",
            description: "Transcribes audio",
            apiEndpoint: " https://api.example.com/v1/audio/transcriptions ",
            modelName: " whisper-1 ",
            isMultilingualModel: true,
            supportedLanguages: ["en": "English"],
            apiKey: " "
        )

        XCTAssertEqual(
            backup.importPlan,
            VoiceInkCustomCloudModelImportPlan(
                id: id,
                name: "custom",
                displayName: "Custom",
                description: "Transcribes audio",
                apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                modelName: "whisper-1",
                isMultilingualModel: true,
                supportedLanguages: ["en": "English"],
                apiKeyToRestore: " "
            )
        )
    }

    func testBackupRecordSkipsOnlyMissingOrEmptyAPIKeyOnImport() {
        XCTAssertNil(VoiceInkCustomCloudModelBackup(
            id: UUID(),
            name: "custom",
            displayName: "Custom",
            description: "",
            apiEndpoint: "",
            modelName: "",
            isMultilingualModel: false,
            supportedLanguages: [:],
            apiKey: nil
        ).apiKeyForImport)

        XCTAssertNil(VoiceInkCustomCloudModelBackup(
            id: UUID(),
            name: "custom",
            displayName: "Custom",
            description: "",
            apiEndpoint: "",
            modelName: "",
            isMultilingualModel: false,
            supportedLanguages: [:],
            apiKey: ""
        ).apiKeyForImport)
    }

    func testStoredRecordMigratesLegacyAPIKeyButNeverReencodesIt() throws {
        let data = """
        {
          "id": "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE",
          "name": "custom",
          "displayName": "Custom",
          "description": "Transcribes audio",
          "apiEndpoint": "https://api.example.com/v1/audio/transcriptions",
          "modelName": "whisper-1",
          "isMultilingualModel": true,
          "supportedLanguages": { "en": "English" },
          "apiKey": " legacy-key "
        }
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(VoiceInkCustomCloudModelStoredRecord.self, from: data)

        XCTAssertEqual(record.legacyAPIKeyForKeychainMigration, " legacy-key ")
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(record)
        ) as? [String: Any]
        XCTAssertNil(encoded?["apiKey"])
    }

    func testStoredRecordSkipsOnlyMissingOrEmptyLegacyAPIKeyMigration() throws {
        XCTAssertNil(VoiceInkCustomCloudModelStoredRecord(
            id: UUID(),
            name: "custom",
            displayName: "Custom",
            description: "",
            apiEndpoint: "",
            modelName: "",
            isMultilingualModel: false,
            supportedLanguages: [:],
            legacyAPIKey: nil
        ).legacyAPIKeyForKeychainMigration)

        XCTAssertNil(VoiceInkCustomCloudModelStoredRecord(
            id: UUID(),
            name: "custom",
            displayName: "Custom",
            description: "",
            apiEndpoint: "",
            modelName: "",
            isMultilingualModel: false,
            supportedLanguages: [:],
            legacyAPIKey: ""
        ).legacyAPIKeyForKeychainMigration)

        XCTAssertEqual(VoiceInkCustomCloudModelStoredRecord(
            id: UUID(),
            name: "custom",
            displayName: "Custom",
            description: "",
            apiEndpoint: "",
            modelName: "",
            isMultilingualModel: false,
            supportedLanguages: [:],
            legacyAPIKey: " "
        ).legacyAPIKeyForKeychainMigration, " ")
    }

    func testCustomCloudModelStorageUsesSharedDefaultsKeyAndRoundTripsRecords() throws {
        let suiteName = "VoiceInkCore.CustomCloudModelPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let record = VoiceInkCustomCloudModelStoredRecord(
            id: UUID(uuidString: "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE")!,
            name: "custom",
            displayName: "Custom",
            description: "Transcribes audio",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "whisper-1",
            isMultilingualModel: true,
            supportedLanguages: ["en": "English"]
        )

        XCTAssertEqual(VoiceInkCustomCloudModelStorage.userDefaultsKey, "customCloudModels")
        let missingRecords: [VoiceInkCustomCloudModelStoredRecord]? = try VoiceInkCustomCloudModelStorage.loadModels(
            from: defaults
        )
        XCTAssertNil(missingRecords)

        try VoiceInkCustomCloudModelStorage.saveModels([record], to: defaults)

        XCTAssertTrue(defaults.data(forKey: VoiceInkCustomCloudModelStorage.userDefaultsKey) != nil)
        let loadedRecords: [VoiceInkCustomCloudModelStoredRecord]? = try VoiceInkCustomCloudModelStorage.loadModels(
            from: defaults
        )
        XCTAssertEqual(loadedRecords, [record])
    }

    func testCustomCloudModelStorageCanClearSharedDefaultsKey() throws {
        let suiteName = "VoiceInkCore.CustomCloudModelPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try VoiceInkCustomCloudModelStorage.saveModels([
            VoiceInkCustomCloudModelStoredRecord(
                id: UUID(),
                name: "custom",
                displayName: "Custom",
                description: "",
                apiEndpoint: "",
                modelName: "",
                isMultilingualModel: false,
                supportedLanguages: [:]
            )
        ], to: defaults)

        VoiceInkCustomCloudModelStorage.clear(from: defaults)

        XCTAssertNil(defaults.data(forKey: VoiceInkCustomCloudModelStorage.userDefaultsKey))
    }

    func testCustomCloudTranscriptionPolicyPreservesOpenAICompatibleRequestDefaults() {
        let options = VoiceInkCustomCloudTranscriptionPolicy.openAICompatibleOptions

        XCTAssertEqual(VoiceInkCustomCloudTranscriptionPolicy.apiErrorDomain, "CustomWhisperTranscriptionService")
        XCTAssertEqual(VoiceInkCustomCloudTranscriptionPolicy.invalidEndpointDescription, "Invalid API endpoint URL")
        XCTAssertEqual(options.openAICompatibleResponseFormat, "json")
        XCTAssertEqual(options.openAICompatibleTemperature, "0")
        XCTAssertEqual(options.openAICompatibleErrorDomain, VoiceInkCustomCloudTranscriptionPolicy.apiErrorDomain)
        XCTAssertFalse(options.openAICompatibleAllowsPlainTextFallback)
    }

    func testCustomCloudTranscriptionPolicyClassifiesEndpointAndText() throws {
        XCTAssertEqual(
            VoiceInkCustomCloudTranscriptionPolicy.endpointURL(
                from: "https://api.example.com/v1/audio/transcriptions"
            )?.absoluteString,
            "https://api.example.com/v1/audio/transcriptions"
        )
        XCTAssertNil(VoiceInkCustomCloudTranscriptionPolicy.endpointURL(from: "http://["))
        XCTAssertNil(VoiceInkCustomCloudTranscriptionPolicy.endpointURL(from: ""))

        XCTAssertTrue(VoiceInkCustomCloudTranscriptionPolicy.acceptsTranscriptionText("transcript"))
        XCTAssertFalse(VoiceInkCustomCloudTranscriptionPolicy.acceptsTranscriptionText(""))
    }
}
