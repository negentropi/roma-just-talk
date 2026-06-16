#if canImport(XCTest)
import XCTest
@testable import VoiceInkCore

final class ProviderEndpointTests: XCTestCase {
    func testConsoleURLsMatchMacOSProviderSettings() {
        XCTAssertEqual(VoiceInkProviderEndpoint.groq.consoleURL.absoluteString, "https://console.groq.com/keys")
        XCTAssertEqual(VoiceInkProviderEndpoint.openAI.consoleURL.absoluteString, "https://platform.openai.com/api-keys")
        XCTAssertEqual(VoiceInkProviderEndpoint.gemini.consoleURL.absoluteString, "https://makersuite.google.com/app/apikey")
        XCTAssertEqual(VoiceInkProviderEndpoint.deepgram.consoleURL.absoluteString, "https://console.deepgram.com/api-keys")
        XCTAssertEqual(VoiceInkProviderEndpoint.cerebras.consoleURL.absoluteString, "https://cloud.cerebras.ai/")
    }
}
#endif
