import XCTest
import RomaCore

final class IOSAnthropicPostProcessingTests: XCTestCase {
    func testVerifiedAnthropicCredentialUnlocksPostProcessingModels() {
        let state = RomaProviderAPIKeyState(
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
            RomaProviderKind.anthropic.postProcessingModels,
            RomaAIModelCatalog.availableModels(for: .anthropic)
        )
    }

    func testAnthropicRequestUsesMessagesHeadersAndSeparatesSystemPrompt() throws {
        let model = try XCTUnwrap(RomaProviderKind.anthropic.postProcessingDefaultModel)
        let request = try RomaAnthropicRequestBuilder.makeMessagesRequest(
            baseURL: RomaProviderKind.anthropic.apiBaseURL,
            apiKey: "anthropic-key",
            model: model,
            messages: [
                RomaOpenAICompatibleChatMessage(role: "system", content: "Polish speech"),
                RomaOpenAICompatibleChatMessage(role: "user", content: "raw transcript")
            ],
            maxTokens: 512
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "anthropic-version"),
            RomaAnthropicRequestBuilder.apiVersion
        )
        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(RomaAnthropicMessagesRequest.self, from: body)
        XCTAssertEqual(payload.model, model)
        XCTAssertEqual(payload.maxTokens, 512)
        XCTAssertEqual(payload.system, "Polish speech")
        XCTAssertEqual(payload.messages, [
            RomaAnthropicMessage(role: "user", content: "raw transcript")
        ])
    }

    func testAnthropicResponseSelectsFirstTextBlock() throws {
        let data = try JSONEncoder().encode(RomaAnthropicMessagesResponse(content: [
            RomaAnthropicContentBlock(type: "thinking", text: nil),
            RomaAnthropicContentBlock(type: "text", text: "Polished transcript")
        ]))

        XCTAssertEqual(
            try RomaAnthropicMessagesCodec.firstText(from: data),
            "Polished transcript"
        )
    }
}
