import Foundation
@testable import RomaCore

final class CustomCloudModelPolicyTests: XCTestCase {
    func testGeneratedNamePreservesExistingLowercaseSpaceReplacementPolicy() {
        XCTAssertEqual(
            RomaCustomCloudModelPolicy.generatedName(fromDisplayName: "My Custom Model"),
            "my-custom-model"
        )
    }

    func testNormalizedDraftPreservesCurrentMacOSFormPreparation() {
        let draft = RomaCustomCloudModelPolicy.normalizedDraft(
            displayName: " My Custom Model ",
            apiEndpoint: " https://api.example.com/v1/audio/transcriptions ",
            apiKey: " key ",
            modelName: " whisper-1 "
        )

        XCTAssertEqual(
            draft,
            RomaCustomCloudModelDraft(
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
            RomaCustomCloudModelPolicy.hasRequiredFields(
                RomaCustomCloudModelPolicy.normalizedDraft(
                    displayName: " ",
                    apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                    apiKey: "key",
                    modelName: "whisper-1"
                )
            )
        )

        XCTAssertTrue(
            RomaCustomCloudModelPolicy.hasRequiredFields(
                RomaCustomCloudModelPolicy.normalizedDraft(
                    displayName: "Custom",
                    apiEndpoint: "not a url",
                    apiKey: "key",
                    modelName: "whisper-1"
                )
            )
        )
    }

    func testMacOSFormControlPresentationOwnsSubmitState() {
        let draft = RomaCustomCloudModelPolicy.normalizedDraft(
            displayName: "Custom",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "key",
            modelName: "whisper-1"
        )
        let ready = RomaCustomCloudModelPolicy.formControlPresentation(
            for: draft,
            isSaving: false
        )

        XCTAssertEqual(
            ready,
            RomaCustomCloudModelFormControlPresentation(
                isSubmitProgressVisible: false,
                isSubmitButtonDisabled: false,
                usesEnabledSubmitStyle: true
            )
        )

        XCTAssertEqual(
            RomaCustomCloudModelPolicy.formControlPresentation(
                for: draft,
                isSaving: true
            ),
            RomaCustomCloudModelFormControlPresentation(
                isSubmitProgressVisible: true,
                isSubmitButtonDisabled: true,
                usesEnabledSubmitStyle: true
            )
        )

        XCTAssertEqual(
            RomaCustomCloudModelPolicy.formControlPresentation(
                for: RomaCustomCloudModelPolicy.normalizedDraft(
                    displayName: "",
                    apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                    apiKey: "key",
                    modelName: "whisper-1"
                ),
                isSaving: false
            ),
            RomaCustomCloudModelFormControlPresentation(
                isSubmitProgressVisible: false,
                isSubmitButtonDisabled: true,
                usesEnabledSubmitStyle: false
            )
        )
    }

    func testValidationReturnsExistingMacOSErrorsInOrder() {
        let errors = RomaCustomCloudModelPolicy.validationErrors(
            for: RomaCustomCloudModelDraft(
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
        let draft = RomaCustomCloudModelDraft(
            name: "custom",
            displayName: "Custom",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            apiKey: "key",
            modelName: "whisper-1"
        )

        XCTAssertEqual(
            RomaCustomCloudModelPolicy.validationErrors(
                for: draft,
                existingModels: [RomaCustomCloudModelIdentity(id: id, name: "custom")]
            ),
            ["A model with this name already exists"]
        )

        XCTAssertEqual(
            RomaCustomCloudModelPolicy.validationErrors(
                for: draft,
                existingModels: [RomaCustomCloudModelIdentity(id: id, name: "custom")],
                excludingId: id
            ),
            []
        )
    }

    func testMacOSFormPresentationBuildsValidationAlertMessage() {
        XCTAssertEqual(
            RomaCustomCloudModelFormPresentation.macOS.validationAlertMessage(
                for: [
                    "Name cannot be empty",
                    "API key cannot be empty"
                ]
            ),
            "Name cannot be empty\nAPI key cannot be empty"
        )
    }

    func testMacOSFormPresentationSelectsAddAndEditLabelsAndIcons() {
        let presentation = RomaCustomCloudModelFormPresentation.macOS

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
        let backup = RomaCustomCloudModelBackup(
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
        let decoded = try JSONDecoder().decode(RomaCustomCloudModelBackup.self, from: data)
        XCTAssertEqual(decoded, backup)
    }

    func testBackupRecordBuildsSharedImportPlanForMacOSAdapter() {
        let id = UUID(uuidString: "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE")!
        let backup = RomaCustomCloudModelBackup(
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
            RomaCustomCloudModelImportPlan(
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
        let plan = RomaCustomCloudModelImportPlan(
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
                RomaCustomCloudModelImportPlan(
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
            RomaCustomCloudModelImportPlan(
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
        let firstBackup = RomaCustomCloudModelBackup(
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
        let secondBackup = RomaCustomCloudModelBackup(
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
        let plan = RomaCustomCloudModelBackupImportPlan(backups: [firstBackup, secondBackup])
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
        let plan = RomaCustomCloudModelBackupImportPlan(backups: nil)
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
        XCTAssertNil(RomaCustomCloudModelBackup(
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

        XCTAssertNil(RomaCustomCloudModelBackup(
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

        let record = try JSONDecoder().decode(RomaCustomCloudModelStoredRecord.self, from: data)

        XCTAssertEqual(record.legacyAPIKeyForKeychainMigration, " legacy-key ")
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(record)
        ) as? [String: Any]
        XCTAssertNil(encoded?["apiKey"])
    }

    func testStoredRecordSkipsOnlyMissingOrEmptyLegacyAPIKeyMigration() throws {
        XCTAssertNil(RomaCustomCloudModelStoredRecord(
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

        XCTAssertNil(RomaCustomCloudModelStoredRecord(
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

        XCTAssertEqual(RomaCustomCloudModelStoredRecord(
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
        let suiteName = "RomaCore.CustomCloudModelPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let record = RomaCustomCloudModelStoredRecord(
            id: UUID(uuidString: "E31E4D7A-437B-4BD3-A4B5-9624F38F3BBE")!,
            name: "custom",
            displayName: "Custom",
            description: "Transcribes audio",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "whisper-1",
            isMultilingualModel: true,
            supportedLanguages: ["en": "English"]
        )

        XCTAssertEqual(RomaCustomCloudModelStorage.userDefaultsKey, "customCloudModels")
        let missingRecords: [RomaCustomCloudModelStoredRecord]? = try RomaCustomCloudModelStorage.loadModels(
            from: defaults
        )
        XCTAssertNil(missingRecords)

        try RomaCustomCloudModelStorage.saveModels([record], to: defaults)

        XCTAssertTrue(defaults.data(forKey: RomaCustomCloudModelStorage.userDefaultsKey) != nil)
        let loadedRecords: [RomaCustomCloudModelStoredRecord]? = try RomaCustomCloudModelStorage.loadModels(
            from: defaults
        )
        XCTAssertEqual(loadedRecords, [record])
    }

    func testCustomCloudModelStorageCanClearSharedDefaultsKey() throws {
        let suiteName = "RomaCore.CustomCloudModelPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try RomaCustomCloudModelStorage.saveModels([
            RomaCustomCloudModelStoredRecord(
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

        RomaCustomCloudModelStorage.clear(from: defaults)

        XCTAssertNil(defaults.data(forKey: RomaCustomCloudModelStorage.userDefaultsKey))
    }

    func testCustomCloudTranscriptionPolicyPreservesOpenAICompatibleRequestDefaults() {
        let options = RomaCustomCloudTranscriptionPolicy.openAICompatibleOptions

        XCTAssertEqual(RomaCustomCloudTranscriptionPolicy.apiErrorDomain, "CustomWhisperTranscriptionService")
        XCTAssertEqual(RomaCustomCloudTranscriptionPolicy.invalidEndpointDescription, "Invalid API endpoint URL")
        XCTAssertEqual(options.openAICompatibleResponseFormat, "json")
        XCTAssertEqual(options.openAICompatibleTemperature, "0")
        XCTAssertEqual(options.openAICompatibleErrorDomain, RomaCustomCloudTranscriptionPolicy.apiErrorDomain)
        XCTAssertFalse(options.openAICompatibleAllowsPlainTextFallback)
    }

    func testCustomCloudTranscriptionPolicyClassifiesEndpointAndText() throws {
        XCTAssertEqual(
            RomaCustomCloudTranscriptionPolicy.endpointURL(
                from: "https://api.example.com/v1/audio/transcriptions"
            )?.absoluteString,
            "https://api.example.com/v1/audio/transcriptions"
        )
        XCTAssertNil(RomaCustomCloudTranscriptionPolicy.endpointURL(from: "http://["))
        XCTAssertNil(RomaCustomCloudTranscriptionPolicy.endpointURL(from: ""))

        XCTAssertTrue(RomaCustomCloudTranscriptionPolicy.acceptsTranscriptionText("transcript"))
        XCTAssertFalse(RomaCustomCloudTranscriptionPolicy.acceptsTranscriptionText(""))
    }

    func testCustomCloudTranscriptionPolicyBuildsSharedTransportRequest() async throws {
        let requestCapture = CustomCloudTranscriptionRequestCapture()

        let text = try await RomaCustomCloudTranscriptionPolicy.transcribeAudioData(
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
        XCTAssertEqual(request.options, RomaCustomCloudTranscriptionPolicy.openAICompatibleOptions)
    }

    func testCustomCloudTranscriptionPolicyRejectsEmptyTransportText() async {
        do {
            _ = try await RomaCustomCloudTranscriptionPolicy.transcribeAudioData(
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
        } catch RomaCloudTranscriptionError.noTranscriptionReturned {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomCloudTranscriptionPolicyMapsHTTPNSError() async {
        do {
            _ = try await RomaCustomCloudTranscriptionPolicy.transcribeAudioData(
                apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
                apiKey: "custom-key",
                model: "custom-stt",
                audioData: Data(),
                fileName: "clip.wav",
                language: nil,
                prompt: nil
            ) { _ in
                throw NSError(
                    domain: RomaCustomCloudTranscriptionPolicy.apiErrorDomain,
                    code: 429,
                    userInfo: [NSLocalizedDescriptionKey: "rate limited"]
                )
            }
            XCTFail("Expected API request failure")
        } catch RomaCloudTranscriptionError.apiRequestFailed(let statusCode, let message) {
            XCTAssertEqual(statusCode, 429)
            XCTAssertEqual(message, "rate limited")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomCloudTranscriptionPolicyMapsUnknownErrorsToNetworkError() async {
        do {
            _ = try await RomaCustomCloudTranscriptionPolicy.transcribeAudioData(
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
        } catch RomaCloudTranscriptionError.networkError(let error) {
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
            _ = try await RomaCustomCloudTranscriptionPolicy.transcribeAudioData(
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
        } catch RomaCloudTranscriptionError.networkError(let error) {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, RomaCustomCloudTranscriptionPolicy.apiErrorDomain)
            XCTAssertEqual(nsError.code, -1)
            XCTAssertEqual(nsError.localizedDescription, RomaCustomCloudTranscriptionPolicy.invalidEndpointDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor CustomCloudTranscriptionRequestCapture {
    private var storedValue: RomaCustomCloudTranscriptionRequest?

    var value: RomaCustomCloudTranscriptionRequest? {
        storedValue
    }

    func store(_ request: RomaCustomCloudTranscriptionRequest) {
        storedValue = request
    }
}
