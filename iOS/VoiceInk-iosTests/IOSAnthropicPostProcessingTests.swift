import XCTest
import VoiceInkCore

final class IOSAnthropicPostProcessingTests: XCTestCase {
    func testVerifiedAnthropicCredentialUnlocksPostProcessingModels() {
        let state = VoiceInkProviderAPIKeyState(
            storedKeysByProvider: [.anthropic: "anthropic-key"],
            verifiedProviders: [.anthropic]
        )

        XCTAssertEqual(
            state.availableProviders(
                for: .postProcessing,
                localWhisperModelAvailable: false
            ),
            [.anthropic]
        )
        XCTAssertEqual(
            VoiceInkProviderKind.anthropic.postProcessingModels,
            VoiceInkAIModelCatalog.availableModels(for: .anthropic)
        )
    }

    func testAnthropicRequestUsesMessagesHeadersAndSeparatesSystemPrompt() throws {
        let model = try XCTUnwrap(VoiceInkProviderKind.anthropic.postProcessingDefaultModel)
        let request = try VoiceInkAnthropicRequestBuilder.makeMessagesRequest(
            baseURL: VoiceInkProviderKind.anthropic.apiBaseURL,
            apiKey: "anthropic-key",
            model: model,
            messages: [
                VoiceInkOpenAICompatibleChatMessage(role: "system", content: "Polish speech"),
                VoiceInkOpenAICompatibleChatMessage(role: "user", content: "raw transcript")
            ],
            maxTokens: 512
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "anthropic-version"),
            VoiceInkAnthropicRequestBuilder.apiVersion
        )
        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(VoiceInkAnthropicMessagesRequest.self, from: body)
        XCTAssertEqual(payload.model, model)
        XCTAssertEqual(payload.maxTokens, 512)
        XCTAssertEqual(payload.system, "Polish speech")
        XCTAssertEqual(payload.messages, [
            VoiceInkAnthropicMessage(role: "user", content: "raw transcript")
        ])
    }

    func testAnthropicResponseSelectsFirstTextBlock() throws {
        let data = try JSONEncoder().encode(VoiceInkAnthropicMessagesResponse(content: [
            VoiceInkAnthropicContentBlock(type: "thinking", text: nil),
            VoiceInkAnthropicContentBlock(type: "text", text: "Polished transcript")
        ]))

        XCTAssertEqual(
            try VoiceInkAnthropicMessagesCodec.firstText(from: data),
            "Polished transcript"
        )
    }
}
