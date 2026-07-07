import Foundation
import VoiceInkCore

final class TranscriptionRunPreparationPublicAPITests: XCTestCase {
    func testMovedTranscriptionRunPreparationSymbolsExposePublicAPI() {
        let skipConfiguration = VoiceInkPostProcessingSkipConfiguration(
            isEnabled: true,
            wordThreshold: 2
        )

        XCTAssertTrue(VoiceInkPostProcessingSkipPolicy.shouldSkipPostProcessing(
            transcript: "Roma works",
            configuration: skipConfiguration,
            promptTriggerForcesPostProcessing: false
        ))
        XCTAssertEqual(VoiceInkWordCounter.count(in: "Roma works"), 2)
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.directTranscription.requestPrompt(" spell Roma "),
            " spell Roma "
        )
        XCTAssertNil(VoiceInkTranscriptionPromptUse.recordedFileTranscription(.deepgram).requestPrompt("ignored"))

        let preparedText = VoiceInkTranscriptionRunPreparation.prepareRawText(
            "Hello.",
            cleanupConfiguration: .disabled
        )
        XCTAssertEqual(preparedText.filteredText, "Hello.")
        XCTAssertEqual(preparedText.transcript(for: .cleanedText), "Hello.")
        XCTAssertTrue(preparedText.shouldSkipPostProcessing(configuration: skipConfiguration))

        let enhancementPlan = VoiceInkTranscriptionRunPreparation.prepareAudioFileText(
            "Hello.",
            cleanupConfiguration: .disabled
        )
        XCTAssertEqual(
            enhancementPlan.enhancementRequest(
                isEnhancementEnabled: true,
                isEnhancementConfigured: true
            )?.text,
            "Hello."
        )
        XCTAssertEqual(VoiceInkTranscriptionEnhancementRequest(text: "raw").text, "raw")
    }
}
