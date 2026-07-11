import XCTest
import VoiceInkCore

final class IOSHistoryReprocessingTests: XCTestCase {
    func testReEnhancementAppliesOnlySuccessfulEnhancementMetadata() async {
        let record = EnhancementRecord(
            enhancedText: "Previous",
            aiEnhancementModelName: "old-model",
            enhancementDuration: 1,
            promptName: "Old prompt"
        )
        let prompt = VoiceInkCustomPrompt(
            title: "Email",
            promptText: "Write a concise email",
            useSystemInstructions: false
        )
        let settings = runSettings(prompt: prompt)
        let processor = VoiceInkTranscriptionRunProcessor(
            currentDate: {
                Date(timeIntervalSince1970: 10)
            },
            postProcessor: { job in
                XCTAssertEqual(job.transcript, "Raw transcript")
                XCTAssertTrue(job.prompt.contains("Write a concise email"))
                return "Enhanced transcript"
            }
        )

        let outcome = await VoiceInkStoredTranscriptionReEnhancement.run(
            record,
            rawText: "Raw transcript",
            runSettings: settings,
            processor: processor,
            apiKeyProvider: { _ in "key" }
        )

        XCTAssertEqual(outcome, .succeeded("Enhanced transcript"))
        XCTAssertEqual(record.enhancedText, "Enhanced transcript")
        XCTAssertEqual(record.aiEnhancementModelName, "llama-3.3-70b-versatile")
        XCTAssertEqual(record.promptName, "Email")
    }

    func testReEnhancementFailurePreservesPreviousEnhancement() async {
        let record = EnhancementRecord(
            enhancedText: "Previous",
            aiEnhancementModelName: "old-model",
            enhancementDuration: 1,
            promptName: "Old prompt"
        )
        let settings = runSettings(
            prompt: VoiceInkCustomPrompt(
                title: "Email",
                promptText: "Write a concise email",
                useSystemInstructions: false
            )
        )
        let processor = VoiceInkTranscriptionRunProcessor { _ in
            throw TestError.failed
        }

        let outcome = await VoiceInkStoredTranscriptionReEnhancement.run(
            record,
            rawText: "Raw transcript",
            runSettings: settings,
            processor: processor,
            apiKeyProvider: { _ in "key" }
        )

        guard case .failed = outcome else {
            return XCTFail("Expected failed outcome")
        }
        XCTAssertEqual(record.enhancedText, "Previous")
        XCTAssertEqual(record.aiEnhancementModelName, "old-model")
        XCTAssertEqual(record.enhancementDuration, 1)
        XCTAssertEqual(record.promptName, "Old prompt")
    }

    private func runSettings(
        prompt: VoiceInkCustomPrompt
    ) -> VoiceInkTranscriptionRunSettings {
        VoiceInkTranscriptionRunSettings(
            configuration: VoiceInkModeRuntimeConfiguration(
                transcriptionProvider: .localWhisper,
                transcriptionModel: "ggml-small.bin",
                postProcessingProvider: .groq,
                postProcessingModel: "llama-3.3-70b-versatile",
                prompt: prompt.finalPromptText,
                promptName: prompt.title,
                isPostProcessingEnabled: true
            ),
            postProcessingSkipConfiguration: VoiceInkPostProcessingSkipConfiguration(
                isEnabled: true,
                wordThreshold: 100
            ),
            promptLibrary: [prompt],
            selectedPromptId: prompt.id
        )
    }
}

private final class EnhancementRecord: VoiceInkMutableTranscriptionEnhancementMetadataRecord {
    var enhancedText: String?
    var aiEnhancementModelName: String?
    var enhancementDuration: TimeInterval?
    var promptName: String?
    var aiRequestSystemMessage: String?
    var aiRequestUserMessage: String?

    init(
        enhancedText: String?,
        aiEnhancementModelName: String?,
        enhancementDuration: TimeInterval?,
        promptName: String?
    ) {
        self.enhancedText = enhancedText
        self.aiEnhancementModelName = aiEnhancementModelName
        self.enhancementDuration = enhancementDuration
        self.promptName = promptName
    }
}

private enum TestError: Error {
    case failed
}
