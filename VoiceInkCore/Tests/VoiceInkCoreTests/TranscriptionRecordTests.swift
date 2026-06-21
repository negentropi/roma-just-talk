import Foundation
import VoiceInkCore

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
