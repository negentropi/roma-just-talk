import Foundation
@testable import VoiceInkCore

final class PostProcessingRequestTests: XCTestCase {
    func testBlankPromptReturnsNilRequest() {
        XCTAssertNil(VoiceInkPostProcessingRequest(prompt: " \n\t ", transcript: "raw text"))
    }

    func testRequestBuildsLegacyIOSPostProcessingMessages() async throws {
        let request = try XCTUnwrap(
            VoiceInkPostProcessingRequest(
                prompt: "Clean this",
                transcript: "raw text"
            )
        )

        let summary = try await request.applyRuntimeState { messages, temperature in
            (messages, temperature)
        }

        XCTAssertEqual(summary.1, 0.2)
        XCTAssertEqual(
            summary.0,
            [
                VoiceInkOpenAICompatibleChatMessage(
                    role: "system",
                    content: "You are a helpful assistant that rewrites raw speech-to-text transcripts to be concise, well-punctuated, and readable notes, preserving meaning."
                ),
                VoiceInkOpenAICompatibleChatMessage(
                    role: "user",
                    content: "Prompt: Clean this\n\nTranscript:\nraw text"
                )
            ]
        )
    }

    func testFinalizedTranscriptFallsBackWhenResponseIsEmptyAfterFiltering() {
        let fallbackTranscript = "raw text"

        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: "",
                fallbackTranscript: fallbackTranscript
            ),
            fallbackTranscript
        )
        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: "   \n ",
                fallbackTranscript: fallbackTranscript
            ),
            fallbackTranscript
        )
        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: "<think>hidden reasoning</think>",
                fallbackTranscript: fallbackTranscript
            ),
            fallbackTranscript
        )
    }

    func testFinalizedTranscriptStripsReasoningTags() {
        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: "<thinking>draft</thinking>\nClean text\n<reasoning>notes</reasoning>",
                fallbackTranscript: "raw text"
            ),
            "Clean text"
        )
    }

    func testFinalizedTranscriptStripsCodexFollowUpPayload() {
        let response = """
        Regards.

        ```json
        {
          "codex_follow_up": true,
          "title": "Follow-up",
          "items": [
            {
              "prompt": "Clean up another short transcript"
            }
          ]
        }
        ```
        """

        XCTAssertEqual(
            VoiceInkPostProcessingRequest.finalizedTranscript(
                from: response,
                fallbackTranscript: "raw text"
            ),
            "Regards."
        )
    }
}
