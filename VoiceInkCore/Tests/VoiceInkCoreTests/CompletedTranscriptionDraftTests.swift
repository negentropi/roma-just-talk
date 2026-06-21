@testable import VoiceInkCore

final class CompletedTranscriptionDraftTests: XCTestCase {
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
