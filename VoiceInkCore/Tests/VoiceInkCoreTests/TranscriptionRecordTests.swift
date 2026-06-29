import Foundation
@testable import VoiceInkCore

final class TranscriptionRecordTests: XCTestCase {
    func testFailurePlanBuildsSharedFailedStatusAndMacOSStoredText() {
        let plan = VoiceInkTranscriptionRecordFailurePlan(errorDescription: "No model selected")

        XCTAssertEqual(plan.status, .failed)
        XCTAssertEqual(plan.errorDescription, "No model selected")
        XCTAssertEqual(plan.failedTranscriptText, "Transcription Failed: No model selected")
    }

    func testCancellationPlanBuildsSharedCanceledStateAndMetadataClears() {
        let plan = VoiceInkTranscriptionRecordCancellationPlan(
            duration: 1.25,
            modelName: "Parakeet"
        )

        XCTAssertEqual(plan.text, VoiceInkTranscriptPresentation.canceledTranscriptionText)
        XCTAssertNil(plan.enhancedText)
        XCTAssertEqual(plan.status, .canceled)
        XCTAssertEqual(plan.duration, 1.25)
        XCTAssertEqual(plan.transcriptionModelName, "Parakeet")
        XCTAssertNil(plan.aiEnhancementModelName)
        XCTAssertNil(plan.promptName)
        XCTAssertNil(plan.transcriptionDuration)
        XCTAssertNil(plan.enhancementDuration)
        XCTAssertNil(plan.aiRequestSystemMessage)
        XCTAssertNil(plan.aiRequestUserMessage)
        XCTAssertNil(plan.transcriptionError)
    }

    func testApplyCompletedRunResultStoresCompletedRecordState() {
        let record = StubMutableTranscriptionRecord()
        let result = VoiceInkTranscriptionRunResult(
            cleanedText: "clean",
            finalText: "enhanced",
            transcriptionModelName: "whisper-large-v3",
            aiEnhancementModelName: "gemini-2.5-flash",
            transcriptionDuration: 3,
            postProcessingResult: VoiceInkAIEnhancementResult(
                text: "enhanced",
                duration: 2,
                modelName: "gemini-2.5-flash",
                promptName: nil,
                requestSystemMessage: nil,
                requestUserMessage: nil
            ),
            postProcessingError: "Post-processing failed: timeout"
        )

        record.applyCompletedRunResult(result)

        XCTAssertEqual(record.text, "clean")
        XCTAssertEqual(record.enhancedText, "enhanced")
        XCTAssertEqual(record.transcriptionModelName, "whisper-large-v3")
        XCTAssertEqual(record.aiEnhancementModelName, "gemini-2.5-flash")
        XCTAssertEqual(record.transcriptionDuration, 3)
        XCTAssertEqual(record.enhancementDuration, 2)
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(record.transcriptionError, "Post-processing failed: timeout")
    }

    func testApplyCompletedRunResultClearsOldEnhancementAndErrorWhenAbsent() {
        let record = StubMutableTranscriptionRecord(
            enhancedText: "old enhancement",
            aiEnhancementModelName: "old model",
            transcriptionError: "old error"
        )
        let result = VoiceInkTranscriptionRunResult(
            cleanedText: "clean",
            finalText: "clean",
            transcriptionModelName: "whisper-large-v3",
            aiEnhancementModelName: nil,
            transcriptionDuration: nil,
            postProcessingError: nil
        )

        record.applyCompletedRunResult(result)

        XCTAssertEqual(record.text, "clean")
        XCTAssertNil(record.enhancedText)
        XCTAssertEqual(record.transcriptionModelName, "whisper-large-v3")
        XCTAssertNil(record.aiEnhancementModelName)
        XCTAssertNil(record.transcriptionDuration)
        XCTAssertNil(record.enhancementDuration)
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertNil(record.transcriptionError)
    }

    func testMarkTranscriptionFailedOnlyStoresFailureState() {
        let record = StubMutableTranscriptionRecord(
            text: "draft",
            enhancedText: "enhanced",
            transcriptionModelName: "whisper-large-v3",
            aiEnhancementModelName: "gemini-2.5-flash"
        )

        record.markTranscriptionFailed("Audio file not found")

        XCTAssertEqual(record.text, "draft")
        XCTAssertEqual(record.enhancedText, "enhanced")
        XCTAssertEqual(record.transcriptionModelName, "whisper-large-v3")
        XCTAssertEqual(record.aiEnhancementModelName, "gemini-2.5-flash")
        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertEqual(record.transcriptionError, "Audio file not found")
    }

    func testMarkTranscriptionCanceledClearsMutableRecordEnhancementState() {
        let record = StubMutableTranscriptionRecord(
            text: "draft",
            enhancedText: "enhanced",
            duration: 5,
            transcriptionModelName: "old model",
            aiEnhancementModelName: "gemini-2.5-flash",
            transcriptionDuration: 3,
            enhancementDuration: 2,
            transcriptionStatus: .completed,
            transcriptionError: "old error"
        )

        record.markTranscriptionCanceled(duration: 1.25, modelName: "Parakeet")

        XCTAssertEqual(record.text, VoiceInkTranscriptPresentation.canceledTranscriptionText)
        XCTAssertNil(record.enhancedText)
        XCTAssertEqual(record.duration, 1.25)
        XCTAssertEqual(record.transcriptionModelName, "Parakeet")
        XCTAssertNil(record.aiEnhancementModelName)
        XCTAssertNil(record.transcriptionDuration)
        XCTAssertNil(record.enhancementDuration)
        XCTAssertEqual(record.transcriptionStatus, .canceled)
        XCTAssertNil(record.transcriptionError)
    }

    func testMarkTranscriptionCanceledPreservesDurationAndModelWhenNotProvided() {
        let record = StubMutableTranscriptionRecord(
            duration: 5,
            transcriptionModelName: "old model"
        )

        record.markTranscriptionCanceled()

        XCTAssertEqual(record.duration, 5)
        XCTAssertEqual(record.transcriptionModelName, "old model")
        XCTAssertEqual(record.transcriptionStatus, .canceled)
    }

    func testRetranscribeStoredAudioAppliesCompletedResult() async throws {
        let recordingsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.TranscriptionRecordTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }

        let audioURL = recordingsDirectory.appendingPathComponent("recording.wav")
        try Data("audio".utf8).write(to: audioURL)

        let record = StubStoredTranscriptionRecord(
            audioFileURL: audioURL.lastPathComponent,
            storedAudioRecordingsDirectory: recordingsDirectory
        )
        let returnedText = try await record.retranscribeStoredAudio { fileURL in
            XCTAssertEqual(fileURL, audioURL)
            return VoiceInkTranscriptionRunResult(
                cleanedText: "clean",
                finalText: "enhanced",
                transcriptionModelName: "whisper-large-v3",
                aiEnhancementModelName: "gemini-2.5-flash",
                transcriptionDuration: 3,
                postProcessingResult: VoiceInkAIEnhancementResult(
                    text: "enhanced",
                    duration: 2,
                    modelName: "gemini-2.5-flash",
                    promptName: nil,
                    requestSystemMessage: nil,
                    requestUserMessage: nil
                ),
                postProcessingError: nil
            )
        }

        XCTAssertEqual(returnedText, "enhanced")
        XCTAssertEqual(record.text, "clean")
        XCTAssertEqual(record.enhancedText, "enhanced")
        XCTAssertEqual(record.transcriptionModelName, "whisper-large-v3")
        XCTAssertEqual(record.aiEnhancementModelName, "gemini-2.5-flash")
        XCTAssertEqual(record.transcriptionDuration, 3)
        XCTAssertEqual(record.enhancementDuration, 2)
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertNil(record.transcriptionError)
    }

    func testRetranscribeStoredAudioMarksMissingAudioFailure() async throws {
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/VoiceInkCore/missing-recording", isDirectory: true)
        let record = StubStoredTranscriptionRecord(
            audioFileURL: "missing.wav",
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        do {
            _ = try await record.retranscribeStoredAudio { _ in
                XCTFail("Missing audio should not run transcription")
                return VoiceInkTranscriptionRunResult(
                    cleanedText: "",
                    finalText: "",
                    transcriptionModelName: "",
                    aiEnhancementModelName: nil,
                    postProcessingError: nil
                )
            }
            XCTFail("Expected missing audio to throw")
        } catch VoiceInkEngineError.audioFileNotFound {
            XCTAssertEqual(record.transcriptionStatus, .failed)
            XCTAssertEqual(record.transcriptionError, "Audio file not found")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRetranscribeStoredAudioMarksTranscriptionFailure() async throws {
        let recordingsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.TranscriptionRecordTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }

        let audioURL = recordingsDirectory.appendingPathComponent("recording.wav")
        try Data("audio".utf8).write(to: audioURL)

        let record = StubStoredTranscriptionRecord(
            audioFileURL: audioURL.lastPathComponent,
            storedAudioRecordingsDirectory: recordingsDirectory
        )
        record.text = "old text"
        record.transcriptionStatus = .pending

        do {
            _ = try await record.retranscribeStoredAudio { fileURL in
                XCTAssertEqual(fileURL, audioURL)
                throw VoiceInkEngineError.transcriptionFailed
            }
            XCTFail("Expected transcription failure to throw")
        } catch VoiceInkEngineError.transcriptionFailed {
            XCTAssertEqual(record.text, "old text")
            XCTAssertEqual(record.transcriptionStatus, .failed)
            XCTAssertEqual(record.transcriptionError, VoiceInkEngineError.transcriptionFailed.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStoredAudioRetranscriptionRunnerLoadsSettingsAndAppliesCompletedRecord() async throws {
        let recordingsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.TranscriptionRecordTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }

        let audioURL = recordingsDirectory.appendingPathComponent("recording.wav")
        try Data("audio".utf8).write(to: audioURL)

        let capture = StoredAudioRetranscriptionCapture(text: "runner transcript")
        let runner = VoiceInkStoredAudioRetranscriptionRunner(
            runSettingsProvider: {
                capture.didLoadSettings = true
                return VoiceInkTranscriptionRunSettings(
                    configuration: Mode(
                        name: "Runner",
                        transcriptionProvider: .groq,
                        transcriptionModel: "whisper-large-v3-turbo",
                        isPostProcessingEnabled: false,
                        postProcessingProvider: .groq,
                        postProcessingModel: VoiceInkAIModelCatalog.defaultModel(for: .groq)
                    ).runtimeConfiguration
                )
            },
            apiKeyProvider: { provider in
                capture.apiKeyProviders.append(provider)
                return "groq-key"
            },
            transcriptionServiceProvider: { provider in
                capture.serviceProviders.append(provider)
                return capture.service
            }
        )
        let record = StubStoredTranscriptionRecord(
            audioFileURL: audioURL.lastPathComponent,
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        let returnedText = try await runner.retranscribe(record)

        XCTAssertEqual(returnedText, "runner transcript")
        XCTAssertTrue(capture.didLoadSettings)
        XCTAssertEqual(capture.apiKeyProviders, [.groq])
        XCTAssertEqual(capture.serviceProviders, [.groq])
        XCTAssertEqual(capture.service.capturedAPIKey, "groq-key")
        XCTAssertEqual(capture.service.capturedModel, "whisper-large-v3-turbo")
        XCTAssertEqual(capture.service.capturedFileURL, audioURL)
        XCTAssertEqual(record.text, "runner transcript")
        XCTAssertEqual(record.transcriptionModelName, "whisper-large-v3-turbo")
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertNil(record.transcriptionError)
    }

    func testStoredAudioRetranscriptionRunnerMarksMissingAudioFailureBeforeLoadingSettings() async throws {
        var didLoadSettings = false
        let runner = VoiceInkStoredAudioRetranscriptionRunner(
            runSettingsProvider: {
                didLoadSettings = true
                return VoiceInkTranscriptionRunSettings(configuration: .fallback)
            },
            apiKeyProvider: { _ in "key" },
            transcriptionServiceProvider: { _ in StoredAudioTranscriptionService(text: "") }
        )
        let record = StubStoredTranscriptionRecord(
            audioFileURL: "missing.wav",
            storedAudioRecordingsDirectory: URL(fileURLWithPath: "/tmp/VoiceInkCore/missing-runner-recording", isDirectory: true)
        )

        do {
            _ = try await runner.retranscribe(record)
            XCTFail("Expected missing audio to throw")
        } catch VoiceInkEngineError.audioFileNotFound {
            XCTAssertFalse(didLoadSettings)
            XCTAssertEqual(record.transcriptionStatus, .failed)
            XCTAssertEqual(record.transcriptionError, "Audio file not found")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStoredAudioRetranscriptionRunnerMarksTranscriptionFailure() async throws {
        let recordingsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.TranscriptionRecordTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }

        let audioURL = recordingsDirectory.appendingPathComponent("recording.wav")
        try Data("audio".utf8).write(to: audioURL)

        let runner = VoiceInkStoredAudioRetranscriptionRunner(
            runSettingsProvider: {
                VoiceInkTranscriptionRunSettings(
                    configuration: Mode(
                        name: "Runner",
                        transcriptionProvider: .groq,
                        transcriptionModel: "whisper-large-v3-turbo",
                        isPostProcessingEnabled: false,
                        postProcessingProvider: .groq,
                        postProcessingModel: VoiceInkAIModelCatalog.defaultModel(for: .groq)
                    ).runtimeConfiguration
                )
            },
            apiKeyProvider: { _ in "groq-key" },
            transcriptionServiceProvider: { _ in ThrowingStoredAudioTranscriptionService() }
        )
        let record = StubStoredTranscriptionRecord(
            audioFileURL: audioURL.lastPathComponent,
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        do {
            _ = try await runner.retranscribe(record)
            XCTFail("Expected transcription failure to throw")
        } catch VoiceInkEngineError.transcriptionFailed {
            XCTAssertEqual(record.transcriptionStatus, .failed)
            XCTAssertEqual(record.transcriptionError, VoiceInkEngineError.transcriptionFailed.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStoredAudioRetranscriptionFacadeRoutesRemoteProviderThroughSharedFactory() async throws {
        let recordingsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.TranscriptionRecordTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }

        let audioURL = recordingsDirectory.appendingPathComponent("recording.wav")
        try Data("audio".utf8).write(to: audioURL)

        var localFactoryCallCount = 0
        var remoteProviders: [VoiceInkProviderKind] = []
        let remoteService = StoredAudioTranscriptionService(text: "remote transcript")
        let record = StubStoredTranscriptionRecord(
            audioFileURL: audioURL.lastPathComponent,
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        let returnedText = try await VoiceInkStoredAudioRetranscription.retranscribe(
            record,
            runSettingsProvider: {
                VoiceInkTranscriptionRunSettings(
                    configuration: Mode(
                        name: "Remote",
                        transcriptionProvider: .groq,
                        transcriptionModel: "whisper-large-v3-turbo",
                        isPostProcessingEnabled: false,
                        postProcessingProvider: .groq,
                        postProcessingModel: VoiceInkAIModelCatalog.defaultModel(for: .groq)
                    ).runtimeConfiguration
                )
            },
            apiKeyProvider: { provider in
                XCTAssertEqual(provider, .groq)
                return "groq-key"
            },
            localWhisperServiceFactory: {
                localFactoryCallCount += 1
                return StoredAudioTranscriptionService(text: "local transcript")
            },
            remoteServiceFactory: { provider in
                remoteProviders.append(provider)
                return remoteService
            }
        )

        XCTAssertEqual(returnedText, "remote transcript")
        XCTAssertEqual(localFactoryCallCount, 0)
        XCTAssertEqual(remoteProviders, [.groq])
        XCTAssertEqual(remoteService.capturedAPIKey, "groq-key")
        XCTAssertEqual(remoteService.capturedModel, "whisper-large-v3-turbo")
        XCTAssertEqual(remoteService.capturedFileURL, audioURL)
        XCTAssertEqual(record.text, "remote transcript")
        XCTAssertEqual(record.transcriptionStatus, .completed)
    }

    func testStoredAudioRetranscriptionFacadeRoutesLocalWhisperProviderThroughSuppliedFactory() async throws {
        let recordingsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.TranscriptionRecordTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }

        let audioURL = recordingsDirectory.appendingPathComponent("recording.wav")
        try Data("audio".utf8).write(to: audioURL)

        var localFactoryCallCount = 0
        var remoteProviders: [VoiceInkProviderKind] = []
        let localService = StoredAudioTranscriptionService(text: "local transcript")
        let record = StubStoredTranscriptionRecord(
            audioFileURL: audioURL.lastPathComponent,
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        let returnedText = try await VoiceInkStoredAudioRetranscription.retranscribe(
            record,
            runSettingsProvider: {
                VoiceInkTranscriptionRunSettings(
                    configuration: Mode.defaultLocalWhisper(name: "Local").runtimeConfiguration
                )
            },
            apiKeyProvider: { provider in
                XCTAssertEqual(provider, .localWhisper)
                return "local-key"
            },
            localWhisperServiceFactory: {
                localFactoryCallCount += 1
                return localService
            },
            remoteServiceFactory: { provider in
                remoteProviders.append(provider)
                return StoredAudioTranscriptionService(text: "remote transcript")
            }
        )

        XCTAssertEqual(returnedText, "local transcript")
        XCTAssertEqual(localFactoryCallCount, 1)
        XCTAssertEqual(remoteProviders, [])
        XCTAssertEqual(localService.capturedAPIKey, "local-key")
        XCTAssertEqual(localService.capturedModel, VoiceInkTranscriptionModelCatalog.localBaseModel)
        XCTAssertEqual(localService.capturedFileURL, audioURL)
        XCTAssertEqual(record.text, "local transcript")
        XCTAssertEqual(record.transcriptionStatus, .completed)
    }

    func testStoredAudioRetranscriptionFacadeMarksMissingAudioBeforeBuildingServices() async throws {
        var didLoadSettings = false
        var didBuildLocalService = false
        var didBuildRemoteService = false
        let record = StubStoredTranscriptionRecord(
            audioFileURL: "missing.wav",
            storedAudioRecordingsDirectory: URL(fileURLWithPath: "/tmp/VoiceInkCore/missing-facade-recording", isDirectory: true)
        )

        do {
            _ = try await VoiceInkStoredAudioRetranscription.retranscribe(
                record,
                runSettingsProvider: {
                    didLoadSettings = true
                    return VoiceInkTranscriptionRunSettings(configuration: .fallback)
                },
                apiKeyProvider: { _ in "key" },
                localWhisperServiceFactory: {
                    didBuildLocalService = true
                    return StoredAudioTranscriptionService(text: "local")
                },
                remoteServiceFactory: { _ in
                    didBuildRemoteService = true
                    return StoredAudioTranscriptionService(text: "remote")
                }
            )
            XCTFail("Expected missing audio to throw")
        } catch VoiceInkEngineError.audioFileNotFound {
            XCTAssertFalse(didLoadSettings)
            XCTAssertFalse(didBuildLocalService)
            XCTAssertFalse(didBuildRemoteService)
            XCTAssertEqual(record.transcriptionStatus, .failed)
            XCTAssertEqual(record.transcriptionError, "Audio file not found")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testApplyEnhancementResultStoresTextAndMetadata() {
        let record = StubMutableTranscriptionEnhancementMetadataRecord()
        let result = VoiceInkAIEnhancementResult(
            text: "Enhanced transcript",
            duration: 1.25,
            modelName: "gpt-5",
            promptName: "Assistant",
            requestSystemMessage: "system",
            requestUserMessage: "user"
        )

        record.applyEnhancementResult(result)

        XCTAssertEqual(record.enhancedText, "Enhanced transcript")
        XCTAssertEqual(record.aiEnhancementModelName, "gpt-5")
        XCTAssertEqual(record.promptName, "Assistant")
        XCTAssertEqual(record.enhancementDuration, 1.25)
        XCTAssertEqual(record.aiRequestSystemMessage, "system")
        XCTAssertEqual(record.aiRequestUserMessage, "user")
    }

    func testApplyEnhancementFailureStoresFailureTextAndClearsMetadata() {
        let record = StubMutableTranscriptionEnhancementMetadataRecord(
            enhancedText: "old",
            aiEnhancementModelName: "old-model",
            enhancementDuration: 2,
            promptName: "old-prompt",
            aiRequestSystemMessage: "old-system",
            aiRequestUserMessage: "old-user"
        )

        record.applyEnhancementFailure(reason: "timeout", policy: .storeFailureText)

        XCTAssertEqual(record.enhancedText, "Enhancement failed: timeout")
        XCTAssertNil(record.aiEnhancementModelName)
        XCTAssertNil(record.promptName)
        XCTAssertNil(record.enhancementDuration)
        XCTAssertNil(record.aiRequestSystemMessage)
        XCTAssertNil(record.aiRequestUserMessage)
    }

    func testApplyEnhancementFailureCanOmitEnhancedText() {
        let record = StubMutableTranscriptionEnhancementMetadataRecord(
            enhancedText: "old",
            aiEnhancementModelName: "old-model",
            enhancementDuration: 2,
            promptName: "old-prompt",
            aiRequestSystemMessage: "old-system",
            aiRequestUserMessage: "old-user"
        )

        record.applyEnhancementFailure(reason: "timeout", policy: .omitEnhancedText)

        XCTAssertNil(record.enhancedText)
        XCTAssertNil(record.aiEnhancementModelName)
        XCTAssertNil(record.promptName)
        XCTAssertNil(record.enhancementDuration)
        XCTAssertNil(record.aiRequestSystemMessage)
        XCTAssertNil(record.aiRequestUserMessage)
    }
}

private class StubMutableTranscriptionRecord: VoiceInkMutableTranscriptionRecord {
    var text: String
    var enhancedText: String?
    var duration: TimeInterval
    var transcriptionModelName: String?
    var aiEnhancementModelName: String?
    var transcriptionDuration: TimeInterval?
    var enhancementDuration: TimeInterval?
    var transcriptionStatus: VoiceInkTranscriptionStatus
    var transcriptionError: String?

    init(
        text: String = "",
        enhancedText: String? = nil,
        duration: TimeInterval = 0,
        transcriptionModelName: String? = nil,
        aiEnhancementModelName: String? = nil,
        transcriptionDuration: TimeInterval? = nil,
        enhancementDuration: TimeInterval? = nil,
        transcriptionStatus: VoiceInkTranscriptionStatus = .pending,
        transcriptionError: String? = nil
    ) {
        self.text = text
        self.enhancedText = enhancedText
        self.duration = duration
        self.transcriptionModelName = transcriptionModelName
        self.aiEnhancementModelName = aiEnhancementModelName
        self.transcriptionDuration = transcriptionDuration
        self.enhancementDuration = enhancementDuration
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionError = transcriptionError
    }
}

private final class StubStoredTranscriptionRecord: StubMutableTranscriptionRecord, VoiceInkStoredAudioRecord {
    var audioFileURL: String?
    let storedAudioRecordingsDirectory: URL?

    init(
        audioFileURL: String?,
        storedAudioRecordingsDirectory: URL?
    ) {
        self.audioFileURL = audioFileURL
        self.storedAudioRecordingsDirectory = storedAudioRecordingsDirectory
        super.init()
    }
}

private final class StoredAudioRetranscriptionCapture {
    var didLoadSettings = false
    var apiKeyProviders: [VoiceInkProviderKind] = []
    var serviceProviders: [VoiceInkProviderKind] = []
    let service: StoredAudioTranscriptionService

    init(text: String) {
        self.service = StoredAudioTranscriptionService(text: text)
    }
}

private final class StoredAudioTranscriptionService: VoiceInkAudioTranscriptionService {
    let text: String
    private(set) var capturedAPIKey: String?
    private(set) var capturedModel: String?
    private(set) var capturedFileURL: URL?

    init(text: String) {
        self.text = text
    }

    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        capturedAPIKey = apiKey
        capturedModel = model
        capturedFileURL = fileURL
        return text
    }
}

private struct ThrowingStoredAudioTranscriptionService: VoiceInkAudioTranscriptionService {
    func transcribeAudioFile(
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String?,
        prompt: String?,
        customVocabulary: [String]
    ) async throws -> String {
        throw VoiceInkEngineError.transcriptionFailed
    }
}

private final class StubMutableTranscriptionEnhancementMetadataRecord: VoiceInkMutableTranscriptionEnhancementMetadataRecord {
    var enhancedText: String?
    var aiEnhancementModelName: String?
    var enhancementDuration: TimeInterval?
    var promptName: String?
    var aiRequestSystemMessage: String?
    var aiRequestUserMessage: String?

    init(
        enhancedText: String? = nil,
        aiEnhancementModelName: String? = nil,
        enhancementDuration: TimeInterval? = nil,
        promptName: String? = nil,
        aiRequestSystemMessage: String? = nil,
        aiRequestUserMessage: String? = nil
    ) {
        self.enhancedText = enhancedText
        self.aiEnhancementModelName = aiEnhancementModelName
        self.enhancementDuration = enhancementDuration
        self.promptName = promptName
        self.aiRequestSystemMessage = aiRequestSystemMessage
        self.aiRequestUserMessage = aiRequestUserMessage
    }
}
