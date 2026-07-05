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

    func testAudioTranscriptionServiceFactoryRemoteProvidersUseRemoteFactory() async throws {
        var capturedProviders: [VoiceInkProviderKind] = []
        let factory = VoiceInkAudioTranscriptionServiceFactory(
            localWhisperServiceFactory: { StoredAudioTranscriptionService(text: "local") },
            remoteServiceFactory: { provider in
                capturedProviders.append(provider)
                return StoredAudioTranscriptionService(text: "remote-\(provider.rawValue)")
            }
        )

        let service = factory.service(for: .groq)
        let transcript = try await service.transcribeAudioFile(
            apiKey: "key",
            model: "model",
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            language: nil,
            prompt: nil,
            customVocabulary: []
        )

        XCTAssertEqual(capturedProviders, [.groq])
        XCTAssertEqual(transcript, "remote-groq")
    }

    func testAudioTranscriptionServiceFactoryLocalWhisperProviderUsesLocalFactory() async throws {
        var localFactoryCallCount = 0
        var capturedRemoteProviders: [VoiceInkProviderKind] = []
        let factory = VoiceInkAudioTranscriptionServiceFactory(
            localWhisperServiceFactory: {
                localFactoryCallCount += 1
                return StoredAudioTranscriptionService(text: "local")
            },
            remoteServiceFactory: { provider in
                capturedRemoteProviders.append(provider)
                return StoredAudioTranscriptionService(text: "remote")
            }
        )

        let service = factory.service(for: .localWhisper)
        let transcript = try await service.transcribeAudioFile(
            apiKey: "key",
            model: "model",
            fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            language: nil,
            prompt: nil,
            customVocabulary: []
        )

        XCTAssertEqual(localFactoryCallCount, 1)
        XCTAssertEqual(capturedRemoteProviders, [])
        XCTAssertEqual(transcript, "local")
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

    func testStoredAudioRetranscriptionFacadeOutcomeReturnsTextAndAppliesCompletedRecord() async throws {
        let recordingsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.TranscriptionRecordTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }

        let audioURL = recordingsDirectory.appendingPathComponent("recording.wav")
        try Data("audio".utf8).write(to: audioURL)

        let remoteService = StoredAudioTranscriptionService(text: "outcome transcript")
        let record = StubStoredTranscriptionRecord(
            audioFileURL: audioURL.lastPathComponent,
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        let outcome = await VoiceInkStoredAudioRetranscription.retranscribeWithOutcome(
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
            apiKeyProvider: { _ in "groq-key" },
            localWhisperServiceFactory: {
                StoredAudioTranscriptionService(text: "local transcript")
            },
            remoteServiceFactory: { _ in remoteService }
        )

        XCTAssertEqual(outcome, .succeeded("outcome transcript"))
        XCTAssertEqual(record.text, "outcome transcript")
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertNil(record.transcriptionError)
    }

    func testStoredAudioRetranscriptionFacadeOutcomeReturnsFailureAfterMissingAudioState() async {
        var didLoadSettings = false
        var didBuildLocalService = false
        var didBuildRemoteService = false
        let record = StubStoredTranscriptionRecord(
            audioFileURL: "missing.wav",
            storedAudioRecordingsDirectory: URL(fileURLWithPath: "/tmp/VoiceInkCore/missing-outcome-recording", isDirectory: true)
        )

        let outcome = await VoiceInkStoredAudioRetranscription.retranscribeWithOutcome(
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

        XCTAssertEqual(outcome, .failed(reason: "Audio file not found"))
        XCTAssertFalse(didLoadSettings)
        XCTAssertFalse(didBuildLocalService)
        XCTAssertFalse(didBuildRemoteService)
        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertEqual(record.transcriptionError, "Audio file not found")
    }

    func testStoredAudioRetranscriptionFacadeBuildsIOSAppSettingsSnapshotInCoreLazily() async throws {
        let suiteName = "VoiceInkCore.TranscriptionRecordTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mode = Mode(
            name: "Remote",
            transcriptionProvider: .assemblyAI,
            transcriptionModel: "slam-1",
            isPostProcessingEnabled: false,
            postProcessingProvider: .openAI,
            postProcessingModel: "gpt-4o-mini"
        )
        VoiceInkLocalWhisperPromptCatalog.saveCustomPrompts(["fr": "French retry prompt"], to: defaults)

        var snapshotLoadCount = 0
        let snapshotProvider: VoiceInkStoredAudioRetranscription.IOSAppSettingsRunSnapshotProvider = {
            snapshotLoadCount += 1
            return VoiceInkIOSAppSettingsRunSnapshot(
                modes: [mode],
                selectedModeId: mode.id,
                selectedTranscriptionLanguage: "fr",
                wordReplacementRules: [],
                customVocabulary: [" Roma ", "Felix", "roma", ""]
            )
        }

        var didBuildLocalService = false
        var didBuildRemoteServiceForMissingAudio = false
        let missingRecord = StubStoredTranscriptionRecord(
            audioFileURL: "missing.wav",
            storedAudioRecordingsDirectory: URL(fileURLWithPath: "/tmp/VoiceInkCore/missing-ios-snapshot-recording", isDirectory: true)
        )

        let missingOutcome = await VoiceInkStoredAudioRetranscription.retranscribeWithOutcome(
            missingRecord,
            defaults: defaults,
            iOSAppSettingsRunSnapshotProvider: snapshotProvider,
            apiKeyProvider: { _ in "key" },
            localWhisperServiceFactory: {
                didBuildLocalService = true
                return StoredAudioTranscriptionService(text: "local")
            },
            remoteServiceFactory: { _ in
                didBuildRemoteServiceForMissingAudio = true
                return StoredAudioTranscriptionService(text: "remote")
            }
        )

        XCTAssertEqual(missingOutcome, .failed(reason: "Audio file not found"))
        XCTAssertEqual(snapshotLoadCount, 0)
        XCTAssertFalse(didBuildLocalService)
        XCTAssertFalse(didBuildRemoteServiceForMissingAudio)

        let recordingsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInkCore.TranscriptionRecordTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }

        let audioURL = recordingsDirectory.appendingPathComponent("recording.wav")
        try Data("audio".utf8).write(to: audioURL)

        var remoteProviders: [VoiceInkProviderKind] = []
        let remoteService = StoredAudioTranscriptionService(text: "ios snapshot transcript")
        let record = StubStoredTranscriptionRecord(
            audioFileURL: audioURL.lastPathComponent,
            storedAudioRecordingsDirectory: recordingsDirectory
        )

        let outcome = await VoiceInkStoredAudioRetranscription.retranscribeWithOutcome(
            record,
            defaults: defaults,
            iOSAppSettingsRunSnapshotProvider: snapshotProvider,
            apiKeyProvider: { provider in
                XCTAssertEqual(provider, .assemblyAI)
                return "assembly-key"
            },
            localWhisperServiceFactory: {
                XCTFail("Remote retry should not build the local Whisper service")
                return StoredAudioTranscriptionService(text: "local")
            },
            remoteServiceFactory: { provider in
                remoteProviders.append(provider)
                return remoteService
            }
        )

        XCTAssertEqual(outcome, .succeeded("ios snapshot transcript"))
        XCTAssertEqual(snapshotLoadCount, 1)
        XCTAssertEqual(remoteProviders, [.assemblyAI])
        XCTAssertEqual(remoteService.capturedAPIKey, "assembly-key")
        XCTAssertEqual(remoteService.capturedModel, mode.runtimeConfiguration.transcriptionModel)
        XCTAssertEqual(remoteService.capturedFileURL, audioURL)
        XCTAssertEqual(remoteService.capturedLanguage, "fr")
        XCTAssertEqual(remoteService.capturedPrompt, "French retry prompt")
        XCTAssertEqual(remoteService.capturedCustomVocabulary, ["Roma", "Felix"])
        XCTAssertEqual(record.text, "ios snapshot transcript")
        XCTAssertEqual(record.transcriptionStatus, .completed)
    }

    func testStoredAudioRetranscriptionFacadeOutcomeReturnsFailureAfterTranscriptionErrorState() async throws {
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

        let outcome = await VoiceInkStoredAudioRetranscription.retranscribeWithOutcome(
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
            apiKeyProvider: { _ in "groq-key" },
            localWhisperServiceFactory: {
                StoredAudioTranscriptionService(text: "local transcript")
            },
            remoteServiceFactory: { _ in ThrowingStoredAudioTranscriptionService() }
        )

        XCTAssertEqual(outcome, .failed(reason: VoiceInkErrorDescription.text(for: VoiceInkEngineError.transcriptionFailed)))
        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertEqual(record.transcriptionError, VoiceInkErrorDescription.text(for: VoiceInkEngineError.transcriptionFailed))
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

    func testDraftStoresSuccessfulEnhancementMetadata() {
        let result = VoiceInkAIEnhancementResult(
            text: "enhanced text",
            duration: 1.25,
            modelName: "gpt-5",
            promptName: "Assistant",
            requestSystemMessage: "system",
            requestUserMessage: "user"
        )

        let draft = VoiceInkCompletedTranscriptionDraft(
            cleanedText: "clean text",
            duration: 3.5,
            audioFileURL: "file:///recording.wav",
            transcriptionModelName: "Parakeet",
            transcriptionDuration: 0.75,
            powerModeName: "Focus",
            powerModeEmoji: "F",
            enhancementResult: result
        )

        XCTAssertEqual(draft.text, "clean text")
        XCTAssertEqual(draft.duration, 3.5)
        XCTAssertEqual(draft.enhancedText, "enhanced text")
        XCTAssertEqual(draft.audioFileURL, "file:///recording.wav")
        XCTAssertEqual(draft.transcriptionModelName, "Parakeet")
        XCTAssertEqual(draft.aiEnhancementModelName, "gpt-5")
        XCTAssertEqual(draft.promptName, "Assistant")
        XCTAssertEqual(draft.transcriptionDuration, 0.75)
        XCTAssertEqual(draft.enhancementDuration, 1.25)
        XCTAssertEqual(draft.aiRequestSystemMessage, "system")
        XCTAssertEqual(draft.aiRequestUserMessage, "user")
        XCTAssertEqual(draft.powerModeName, "Focus")
        XCTAssertEqual(draft.powerModeEmoji, "F")
        XCTAssertEqual(draft.transcriptionStatus, .completed)
    }

    func testFailurePolicyCanStoreSharedFailureTextAndClearEnhancementMetadata() {
        let draft = VoiceInkCompletedTranscriptionDraft(
            cleanedText: "clean text",
            duration: 3.5,
            audioFileURL: "file:///recording.wav",
            transcriptionModelName: "Parakeet",
            transcriptionDuration: 0.75,
            enhancementFailureReason: "timeout",
            enhancementFailurePolicy: .storeFailureText
        )

        XCTAssertEqual(draft.enhancedText, "Enhancement failed: timeout")
        XCTAssertNil(draft.aiEnhancementModelName)
        XCTAssertNil(draft.promptName)
        XCTAssertNil(draft.enhancementDuration)
        XCTAssertNil(draft.aiRequestSystemMessage)
        XCTAssertNil(draft.aiRequestUserMessage)
        XCTAssertEqual(draft.transcriptionStatus, .completed)
    }

    func testFailurePolicyCanOmitEnhancedText() {
        let draft = VoiceInkCompletedTranscriptionDraft(
            cleanedText: "clean text",
            duration: 3.5,
            audioFileURL: "file:///recording.wav",
            transcriptionModelName: "Parakeet",
            transcriptionDuration: 0.75,
            enhancementFailureReason: "timeout",
            enhancementFailurePolicy: .omitEnhancedText
        )

        XCTAssertNil(draft.enhancedText)
        XCTAssertNil(draft.aiEnhancementModelName)
        XCTAssertNil(draft.promptName)
        XCTAssertNil(draft.enhancementDuration)
        XCTAssertNil(draft.aiRequestSystemMessage)
        XCTAssertNil(draft.aiRequestUserMessage)
        XCTAssertEqual(draft.transcriptionStatus, .completed)
    }

    func testAudioFileTranscriptionDraftBuildsCompletedDraftWithoutEnhancement() {
        let draft = VoiceInkAudioFileTranscriptionDraft.completed(context: audioFileDraftContext)

        XCTAssertEqual(draft.text, "clean text")
        XCTAssertEqual(draft.duration, 3.5)
        XCTAssertEqual(draft.audioFileURL, "file:///recording.wav")
        XCTAssertEqual(draft.transcriptionModelName, "Parakeet")
        XCTAssertEqual(draft.transcriptionDuration, 0.75)
        XCTAssertEqual(draft.powerModeName, "Focus")
        XCTAssertEqual(draft.powerModeEmoji, "F")
        XCTAssertNil(draft.enhancedText)
        XCTAssertNil(draft.aiEnhancementModelName)
        XCTAssertEqual(draft.transcriptionStatus, .completed)
    }

    func testAudioFileTranscriptionDraftStoresSuccessfulEnhancement() {
        let result = VoiceInkAIEnhancementResult(
            text: "enhanced text",
            duration: 1.25,
            modelName: "gpt-5",
            promptName: "Assistant",
            requestSystemMessage: "system",
            requestUserMessage: "user"
        )

        let draft = VoiceInkAudioFileTranscriptionDraft.completed(
            context: audioFileDraftContext,
            enhancementOutcome: .succeeded(result)
        )

        XCTAssertEqual(draft.enhancedText, "enhanced text")
        XCTAssertEqual(draft.aiEnhancementModelName, "gpt-5")
        XCTAssertEqual(draft.promptName, "Assistant")
        XCTAssertEqual(draft.enhancementDuration, 1.25)
        XCTAssertEqual(draft.aiRequestSystemMessage, "system")
        XCTAssertEqual(draft.aiRequestUserMessage, "user")
        XCTAssertEqual(draft.transcriptionStatus, .completed)
    }

    func testAudioFileTranscriptionDraftAppliesFailurePolicy() {
        let storedFailureDraft = VoiceInkAudioFileTranscriptionDraft.completed(
            context: audioFileDraftContext,
            enhancementOutcome: .failed(reason: "timeout", policy: .storeFailureText)
        )
        let omittedFailureDraft = VoiceInkAudioFileTranscriptionDraft.completed(
            context: audioFileDraftContext,
            enhancementOutcome: .failed(reason: "timeout", policy: .omitEnhancedText)
        )

        XCTAssertEqual(storedFailureDraft.enhancedText, "Enhancement failed: timeout")
        XCTAssertNil(storedFailureDraft.aiEnhancementModelName)
        XCTAssertNil(storedFailureDraft.promptName)
        XCTAssertNil(storedFailureDraft.enhancementDuration)
        XCTAssertNil(storedFailureDraft.aiRequestSystemMessage)
        XCTAssertNil(storedFailureDraft.aiRequestUserMessage)
        XCTAssertNil(omittedFailureDraft.enhancedText)
        XCTAssertEqual(omittedFailureDraft.transcriptionStatus, .completed)
    }

    func testAudioFileTranscriptionCompletionSkipsMissingEnhancementRequest() async {
        var didCallEnhancer = false

        let result = await VoiceInkAudioFileTranscriptionDraft.completionResult(
            context: audioFileDraftContext,
            enhancementRequest: nil,
            enhancementFailurePolicy: .storeFailureText
        ) { _ in
            didCallEnhancer = true
            return VoiceInkAIEnhancementResult(
                text: "unexpected",
                duration: 1,
                modelName: "gpt-5",
                promptName: nil,
                requestSystemMessage: nil,
                requestUserMessage: nil
            )
        }

        XCTAssertFalse(didCallEnhancer)
        XCTAssertEqual(result.draft.text, "clean text")
        XCTAssertNil(result.draft.enhancedText)
        XCTAssertNil(result.enhancementFailureReason)
    }

    func testAudioFileTranscriptionCompletionStoresSuccessfulEnhancement() async {
        let request = VoiceInkTranscriptionEnhancementRequest(text: "text for enhancement")
        let enhancement = VoiceInkAIEnhancementResult(
            text: "enhanced text",
            duration: 1.25,
            modelName: "gpt-5",
            promptName: "Assistant",
            requestSystemMessage: "system",
            requestUserMessage: "user"
        )

        let result = await VoiceInkAudioFileTranscriptionDraft.completionResult(
            context: audioFileDraftContext,
            enhancementRequest: request,
            enhancementFailurePolicy: .storeFailureText
        ) { receivedRequest in
            XCTAssertEqual(receivedRequest, request)
            return enhancement
        }

        XCTAssertEqual(result.draft.enhancedText, "enhanced text")
        XCTAssertEqual(result.draft.aiEnhancementModelName, "gpt-5")
        XCTAssertEqual(result.draft.promptName, "Assistant")
        XCTAssertEqual(result.draft.enhancementDuration, 1.25)
        XCTAssertEqual(result.draft.aiRequestSystemMessage, "system")
        XCTAssertEqual(result.draft.aiRequestUserMessage, "user")
        XCTAssertNil(result.enhancementFailureReason)
    }

    func testAudioFileTranscriptionCompletionMapsEnhancementFailureToDraftAndReason() async {
        let error = NSError(
            domain: "VoiceInkCoreTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "timeout"]
        )

        let result = await VoiceInkAudioFileTranscriptionDraft.completionResult(
            context: audioFileDraftContext,
            enhancementRequest: VoiceInkTranscriptionEnhancementRequest(text: "text for enhancement"),
            enhancementFailurePolicy: .storeFailureText
        ) { _ in
            throw error
        }

        XCTAssertEqual(result.draft.enhancedText, "Enhancement failed: timeout")
        XCTAssertNil(result.draft.aiEnhancementModelName)
        XCTAssertNil(result.draft.promptName)
        XCTAssertNil(result.draft.enhancementDuration)
        XCTAssertEqual(result.enhancementFailureReason, "timeout")
        XCTAssertEqual(result.draft.transcriptionStatus, .completed)
    }

    func testAudioFileTranscriptionDiagnosticsPreserveMacOSRetryLogCopy() {
        XCTAssertEqual(
            VoiceInkAudioFileTranscriptionDiagnostics.wordReplacementsAppliedMessage,
            "✅ Word replacements applied"
        )
        XCTAssertEqual(
            VoiceInkAudioFileTranscriptionDiagnostics.permanentCopyFailedMessage(localizedDescription: "permission denied"),
            "❌ Failed to create permanent copy of audio: permission denied"
        )
        XCTAssertEqual(
            VoiceInkAudioFileTranscriptionDiagnostics.transcriptionFailedMessage(localizedDescription: "No model"),
            "❌ Transcription failed: No model"
        )
        XCTAssertEqual(
            VoiceInkAudioFileTranscriptionDiagnostics.saveFailedMessage(localizedDescription: "disk full"),
            "❌ Failed to save transcription: disk full"
        )
    }

    func testRecordingPendingDraftBuildsSharedPendingRow() {
        let draft = VoiceInkRecordingTranscriptionDraft.pending(
            duration: 4.25,
            audioFileURL: "recording.wav",
            transcriptionModelName: "Base",
            powerModeName: "Focus",
            powerModeEmoji: "F"
        )

        XCTAssertEqual(draft.text, "")
        XCTAssertEqual(draft.duration, 4.25)
        XCTAssertEqual(draft.audioFileURL, "recording.wav")
        XCTAssertEqual(draft.transcriptionModelName, "Base")
        XCTAssertEqual(draft.powerModeName, "Focus")
        XCTAssertEqual(draft.powerModeEmoji, "F")
        XCTAssertEqual(draft.transcriptionStatus, .pending)
    }

    func testRecordingCanceledDraftUsesSharedCanceledText() {
        let draft = VoiceInkRecordingTranscriptionDraft.canceled(
            duration: 1.5,
            audioFileURL: "file:///recording.wav",
            transcriptionModelName: "Parakeet"
        )

        XCTAssertEqual(draft.text, VoiceInkTranscriptPresentation.canceledTranscriptionText)
        XCTAssertEqual(draft.duration, 1.5)
        XCTAssertEqual(draft.audioFileURL, "file:///recording.wav")
        XCTAssertEqual(draft.transcriptionModelName, "Parakeet")
        XCTAssertNil(draft.powerModeName)
        XCTAssertNil(draft.powerModeEmoji)
        XCTAssertEqual(draft.transcriptionStatus, .canceled)
    }

    private var audioFileDraftContext: VoiceInkAudioFileTranscriptionDraftContext {
        VoiceInkAudioFileTranscriptionDraftContext(
            cleanedText: "clean text",
            duration: 3.5,
            audioFileURL: "file:///recording.wav",
            transcriptionModelName: "Parakeet",
            transcriptionDuration: 0.75,
            powerModeName: "Focus",
            powerModeEmoji: "F"
        )
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
    private(set) var capturedLanguage: String?
    private(set) var capturedPrompt: String?
    private(set) var capturedCustomVocabulary: [String] = []

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
        capturedLanguage = language
        capturedPrompt = prompt
        capturedCustomVocabulary = customVocabulary
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
