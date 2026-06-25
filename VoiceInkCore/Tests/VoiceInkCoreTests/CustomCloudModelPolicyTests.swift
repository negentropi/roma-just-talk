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

    func testMacOSFormPresentationBuildsValidationAlertMessage() {
        XCTAssertEqual(
            VoiceInkCustomCloudModelFormPresentation.macOS.validationAlertMessage(
                for: [
                    "Name cannot be empty",
                    "API key cannot be empty"
                ]
            ),
            "Name cannot be empty\nAPI key cannot be empty"
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

    func testBackupImportPlanAppliesRuntimeStateForMacOSAdapter() {
        let id = UUID(uuidString: "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE")!
        let plan = VoiceInkCustomCloudModelImportPlan(
            id: id,
            name: "custom",
            displayName: "Custom",
            description: "Transcribes audio",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "whisper-1",
            isMultilingualModel: true,
            supportedLanguages: ["en": "English"],
            apiKeyToRestore: "secret"
        )
        var restoredAPIKeys = [(String, UUID)]()

        let model = plan.applyRuntimeState(
            makeModel: { id, name, displayName, description, apiEndpoint, modelName, isMultilingualModel, supportedLanguages in
                VoiceInkCustomCloudModelImportPlan(
                    id: id,
                    name: name,
                    displayName: displayName,
                    description: description,
                    apiEndpoint: apiEndpoint,
                    modelName: modelName,
                    isMultilingualModel: isMultilingualModel,
                    supportedLanguages: supportedLanguages,
                    apiKeyToRestore: nil
                )
            },
            restoreAPIKey: { apiKey, modelId in
                restoredAPIKeys.append((apiKey, modelId))
            }
        )

        XCTAssertEqual(
            model,
            VoiceInkCustomCloudModelImportPlan(
                id: id,
                name: "custom",
                displayName: "Custom",
                description: "Transcribes audio",
                apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                modelName: "whisper-1",
                isMultilingualModel: true,
                supportedLanguages: ["en": "English"],
                apiKeyToRestore: nil
            )
        )
        XCTAssertEqual(restoredAPIKeys.map(\.0), ["secret"])
        XCTAssertEqual(restoredAPIKeys.map(\.1), [id])
    }

    func testBackupImportCollectionPlanAppliesRuntimeStateInMacOSOrder() {
        let firstBackup = VoiceInkCustomCloudModelBackup(
            id: UUID(uuidString: "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE")!,
            name: "first",
            displayName: "First",
            description: "First custom model",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "first-model",
            isMultilingualModel: true,
            supportedLanguages: ["en": "English"],
            apiKey: nil
        )
        let secondBackup = VoiceInkCustomCloudModelBackup(
            id: UUID(uuidString: "1CE7D350-8555-4B4B-A9C1-24E8484E9C8A")!,
            name: "second",
            displayName: "Second",
            description: "Second custom model",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "second-model",
            isMultilingualModel: false,
            supportedLanguages: [:],
            apiKey: nil
        )

        var events = [String]()
        let plan = VoiceInkCustomCloudModelBackupImportPlan(backups: [firstBackup, secondBackup])
        plan.applyRuntimeState(
            makeModel: { backup in
                events.append("make:\(backup.name)")
                return backup.name
            },
            setCustomModels: { models in
                events.append("set:\(models.joined(separator: ","))")
            },
            saveCustomModels: {
                events.append("save")
            },
            refreshAvailableModels: {
                events.append("refresh")
            },
            reportNoCustomModels: {
                events.append("none")
            },
            reportImportedModelCount: { count in
                events.append("report:\(count)")
            }
        )

        XCTAssertEqual(
            events,
            [
                "make:first",
                "make:second",
                "set:first,second",
                "save",
                "refresh",
                "report:2"
            ]
        )
    }

    func testBackupImportCollectionPlanReportsMissingCustomModelsOnly() {
        var events = [String]()
        let plan = VoiceInkCustomCloudModelBackupImportPlan(backups: nil)
        plan.applyRuntimeState(
            makeModel: { backup in
                events.append("make:\(backup.name)")
                return backup.name
            },
            setCustomModels: { models in
                events.append("set:\(models.joined(separator: ","))")
            },
            saveCustomModels: {
                events.append("save")
            },
            refreshAvailableModels: {
                events.append("refresh")
            },
            reportNoCustomModels: {
                events.append("none")
            },
            reportImportedModelCount: { count in
                events.append("report:\(count)")
            }
        )

        XCTAssertEqual(events, ["none"])
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

    func testCustomCloudModelStorageDiagnosticsPreserveMacOSLogCopy() {
        XCTAssertEqual(
            VoiceInkCustomCloudModelStorage.decodeFailedMessage(errorDescription: "Bad JSON"),
            "Failed to decode custom models: Bad JSON"
        )
        XCTAssertEqual(
            VoiceInkCustomCloudModelStorage.encodeFailedMessage(errorDescription: "Disk full"),
            "Failed to encode custom models: Disk full"
        )
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

    func testCustomCloudTranscriptionPolicyBuildsSharedTransportRequest() async throws {
        let requestCapture = CustomCloudTranscriptionRequestCapture()

        let text = try await VoiceInkCustomCloudTranscriptionPolicy.transcribeAudioData(
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "custom-key",
            model: "custom-stt",
            audioData: Data([1, 2, 3]),
            fileName: "clip.wav",
            language: "en",
            prompt: "spell Roma correctly"
        ) { request in
            await requestCapture.store(request)
            return "custom transcript"
        }

        let capturedRequest = await requestCapture.value
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(text, "custom transcript")
        XCTAssertEqual(request.url.absoluteString, "https://api.example.com/v1/audio/transcriptions")
        XCTAssertEqual(request.apiKey, "custom-key")
        XCTAssertEqual(request.model, "custom-stt")
        XCTAssertEqual(request.audioData, Data([1, 2, 3]))
        XCTAssertEqual(request.fileName, "clip.wav")
        XCTAssertEqual(request.language, "en")
        XCTAssertEqual(request.prompt, "spell Roma correctly")
        XCTAssertEqual(request.options, VoiceInkCustomCloudTranscriptionPolicy.openAICompatibleOptions)
    }

    func testCustomCloudTranscriptionPolicyRejectsEmptyTransportText() async {
        do {
            _ = try await VoiceInkCustomCloudTranscriptionPolicy.transcribeAudioData(
                apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                apiKey: "custom-key",
                model: "custom-stt",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil
            ) { _ in
                ""
            }
            XCTFail("Expected empty custom cloud transcription error")
        } catch VoiceInkCloudTranscriptionError.noTranscriptionReturned {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomCloudTranscriptionPolicyMapsHTTPNSError() async {
        do {
            _ = try await VoiceInkCustomCloudTranscriptionPolicy.transcribeAudioData(
                apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                apiKey: "custom-key",
                model: "custom-stt",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil
            ) { _ in
                throw NSError(
                    domain: VoiceInkCustomCloudTranscriptionPolicy.apiErrorDomain,
                    code: 429,
                    userInfo: [NSLocalizedDescriptionKey: "rate limited"]
                )
            }
            XCTFail("Expected API request failure")
        } catch VoiceInkCloudTranscriptionError.apiRequestFailed(let statusCode, let message) {
            XCTAssertEqual(statusCode, 429)
            XCTAssertEqual(message, "rate limited")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomCloudTranscriptionPolicyMapsUnknownErrorsToNetworkError() async {
        do {
            _ = try await VoiceInkCustomCloudTranscriptionPolicy.transcribeAudioData(
                apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                apiKey: "custom-key",
                model: "custom-stt",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil
            ) { _ in
                throw NSError(
                    domain: "Transport",
                    code: -7,
                    userInfo: [NSLocalizedDescriptionKey: "connection dropped"]
                )
            }
            XCTFail("Expected network error")
        } catch VoiceInkCloudTranscriptionError.networkError(let error) {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "Transport")
            XCTAssertEqual(nsError.code, -7)
            XCTAssertEqual(nsError.localizedDescription, "connection dropped")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomCloudTranscriptionPolicyMapsInvalidEndpointToNetworkError() async {
        do {
            _ = try await VoiceInkCustomCloudTranscriptionPolicy.transcribeAudioData(
                apiEndpoint: "http://[",
                apiKey: "custom-key",
                model: "custom-stt",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil
            ) { _ in
                XCTFail("Invalid endpoint should not call transport")
                return "unexpected"
            }
            XCTFail("Expected network error")
        } catch VoiceInkCloudTranscriptionError.networkError(let error) {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, VoiceInkCustomCloudTranscriptionPolicy.apiErrorDomain)
            XCTAssertEqual(nsError.code, -1)
            XCTAssertEqual(nsError.localizedDescription, VoiceInkCustomCloudTranscriptionPolicy.invalidEndpointDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor CustomCloudTranscriptionRequestCapture {
    private var storedValue: VoiceInkCustomCloudTranscriptionRequest?

    var value: VoiceInkCustomCloudTranscriptionRequest? {
        storedValue
    }

    func store(_ request: VoiceInkCustomCloudTranscriptionRequest) {
        storedValue = request
    }
}
