import Foundation
@testable import VoiceInkCore

final class StreamingTranscriptionEventTests: XCTestCase {
    func testStreamingEventsCarrySessionAndTextUpdates() {
        assertSessionStarted(.sessionStarted)
        assertText(.partial(text: "draft"), expectedText: "draft")
        assertText(.committed(text: "final"), expectedText: "final")
    }

    func testStreamingErrorEventCarriesOriginalError() {
        let error = VoiceInkStreamingTranscriptionError.serverError("closed")
        guard case .error(let carriedError) = VoiceInkStreamingTranscriptionEvent.error(error) else {
            XCTFail("Expected error event")
            return
        }

        XCTAssertEqual(
            carriedError.localizedDescription,
            "Streaming server error: closed"
        )
    }

    private func assertSessionStarted(_ event: VoiceInkStreamingTranscriptionEvent) {
        guard case .sessionStarted = event else {
            XCTFail("Expected sessionStarted event")
            return
        }
    }

    private func assertText(
        _ event: VoiceInkStreamingTranscriptionEvent,
        expectedText: String
    ) {
        switch event {
        case .partial(let text), .committed(let text):
            XCTAssertEqual(text, expectedText)
        default:
            XCTFail("Expected text event")
        }
    }
}
