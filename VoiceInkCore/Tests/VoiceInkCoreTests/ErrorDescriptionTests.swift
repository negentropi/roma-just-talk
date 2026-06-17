import Foundation
@testable import VoiceInkCore

final class ErrorDescriptionTests: XCTestCase {
    func testPrefersLocalizedErrorDescription() {
        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: StubDescribedError(message: "provider down")),
            "provider down"
        )
    }

    func testFallsBackToLocalizedDescription() {
        let error = StubUndescribedError()

        XCTAssertEqual(
            VoiceInkErrorDescription.text(for: error),
            error.localizedDescription
        )
    }
}

private struct StubDescribedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct StubUndescribedError: LocalizedError {
    var errorDescription: String? {
        nil
    }
}
