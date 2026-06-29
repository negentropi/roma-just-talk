import Foundation
@testable import VoiceInkCore

final class ProviderEndpointTests: XCTestCase {
    func testConsoleURLsMatchMacOSProviderSettings() {
        XCTAssertEqual(VoiceInkProviderEndpoint.groq.consoleURL.absoluteString, "https://console.groq.com/keys")
        XCTAssertEqual(VoiceInkProviderEndpoint.openAI.consoleURL.absoluteString, "https://platform.openai.com/api-keys")
        XCTAssertEqual(VoiceInkProviderEndpoint.gemini.consoleURL.absoluteString, "https://makersuite.google.com/app/apikey")
        XCTAssertEqual(VoiceInkProviderEndpoint.deepgram.consoleURL.absoluteString, "https://console.deepgram.com/api-keys")
        XCTAssertEqual(VoiceInkProviderEndpoint.cerebras.consoleURL.absoluteString, "https://cloud.cerebras.ai/")
        XCTAssertEqual(VoiceInkProviderKind.mistral.consoleURL.absoluteString, "https://console.mistral.ai/api-keys")
        XCTAssertEqual(VoiceInkProviderKind.elevenLabs.consoleURL.absoluteString, "https://elevenlabs.io/speech-synthesis")
        XCTAssertEqual(VoiceInkProviderKind.soniox.consoleURL.absoluteString, "https://console.soniox.com/")
        XCTAssertEqual(VoiceInkProviderKind.speechmatics.consoleURL.absoluteString, "https://portal.speechmatics.com/manage-access/")
        XCTAssertEqual(VoiceInkProviderKind.assemblyAI.consoleURL.absoluteString, "https://www.assemblyai.com/dashboard/api-keys")
        XCTAssertEqual(VoiceInkProviderKind.xai.consoleURL.absoluteString, "https://console.x.ai/")
    }

    func testPostProcessingChatCompletionsURLsOnlyExistForPostProcessingProviders() {
        XCTAssertEqual(
            VoiceInkProviderKind.groq.postProcessingChatCompletionsURL?.absoluteString,
            "https://api.groq.com/openai/v1/chat/completions"
        )
        XCTAssertEqual(
            VoiceInkProviderKind.openAI.postProcessingChatCompletionsURL?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            VoiceInkProviderKind.cerebras.postProcessingChatCompletionsURL?.absoluteString,
            "https://api.cerebras.ai/v1/chat/completions"
        )
        XCTAssertEqual(
            VoiceInkProviderKind.gemini.postProcessingChatCompletionsURL?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/openai/v1/chat/completions"
        )
        XCTAssertNil(VoiceInkProviderKind.deepgram.postProcessingChatCompletionsURL)
        XCTAssertNil(VoiceInkProviderKind.mistral.postProcessingChatCompletionsURL)
        XCTAssertNil(VoiceInkProviderKind.elevenLabs.postProcessingChatCompletionsURL)
        XCTAssertNil(VoiceInkProviderKind.soniox.postProcessingChatCompletionsURL)
        XCTAssertNil(VoiceInkProviderKind.speechmatics.postProcessingChatCompletionsURL)
        XCTAssertNil(VoiceInkProviderKind.assemblyAI.postProcessingChatCompletionsURL)
        XCTAssertNil(VoiceInkProviderKind.xai.postProcessingChatCompletionsURL)
        XCTAssertNil(VoiceInkProviderKind.localWhisper.postProcessingChatCompletionsURL)
    }
}
