import Foundation
@testable import VoiceInkCore

final class TranscriptionPromptUseTests: XCTestCase {
    func testNonBlankRequestPromptDropsBlankAndPreservesOriginalText() {
        XCTAssertNil(VoiceInkTranscriptionPromptUse.nonBlankRequestPrompt(nil))
        XCTAssertNil(VoiceInkTranscriptionPromptUse.nonBlankRequestPrompt(" \n\t "))
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.nonBlankRequestPrompt(" spell Roma correctly "),
            " spell Roma correctly "
        )
    }

    func testRecordedFilePromptUseKeepsSupportedProviderPrompts() {
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.groq)
                .requestPrompt("spell Roma correctly"),
            "spell Roma correctly"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.openAI)
                .requestPrompt("spell Roma correctly"),
            "spell Roma correctly"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.assemblyAI)
                .requestPrompt("spell Roma correctly"),
            "spell Roma correctly"
        )
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.localWhisper)
                .requestPrompt("Use custom language prompt."),
            "Use custom language prompt."
        )
    }

    func testRecordedFilePromptUseDropsUnsupportedProviderPrompts() {
        XCTAssertNil(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.deepgram)
                .requestPrompt("ignored")
        )
        XCTAssertNil(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.gemini)
                .requestPrompt("ignored")
        )
        XCTAssertNil(
            VoiceInkTranscriptionPromptUse.recordedFileTranscription(.soniox)
                .requestPrompt("ignored")
        )
    }

    func testStreamingPromptUseKeepsOnlyAssemblyAIPrompts() {
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.streamingTranscription(.assemblyAI)
                .requestPrompt("spell project names"),
            "spell project names"
        )
        XCTAssertNil(
            VoiceInkTranscriptionPromptUse.streamingTranscription(.deepgram)
                .requestPrompt("ignored")
        )
    }

    func testDirectTranscriptionPromptUseKeepsPrompt() {
        XCTAssertEqual(
            VoiceInkTranscriptionPromptUse.directTranscription.requestPrompt("custom endpoint prompt"),
            "custom endpoint prompt"
        )
    }
}
