import Foundation
@testable import VoiceInkCore

final class StreamingTranscriptionErrorTests: XCTestCase {
    func testErrorDescriptionsPreserveExistingMacOSStreamingMessages() {
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.missingAPIKey.errorDescription,
            "API key not configured for streaming transcription"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.connectionFailed("socket closed").errorDescription,
            "Streaming connection failed: socket closed"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.timeout.errorDescription,
            "Streaming transcription timed out waiting for final result"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.serverError("bad request").errorDescription,
            "Streaming server error: bad request"
        )
        XCTAssertEqual(
            VoiceInkStreamingTranscriptionError.notConnected.errorDescription,
            "Not connected to streaming transcription service"
        )
    }

    func testUnknownServerErrorFallbackPreservesExistingText() {
        XCTAssertEqual(VoiceInkStreamingTranscriptionError.unknownServerErrorMessage, "Unknown error")
    }
}
