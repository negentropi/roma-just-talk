import Foundation
@testable import VoiceInkCore

final class APIKeyReferenceTests: XCTestCase {
    func testResolvedValueReturnsTrimmedLiteralKeys() {
        XCTAssertEqual(
            VoiceInkAPIKeyReference.resolvedValue(" literal-key "),
            "literal-key"
        )
    }

    func testResolvedValueResolvesDollarEnvironmentReference() {
        XCTAssertEqual(
            VoiceInkAPIKeyReference.resolvedValue(
                "$ELEVENLABS_API_KEY",
                environment: ["ELEVENLABS_API_KEY": "test-key"]
            ),
            "test-key"
        )
    }

    func testResolvedValueResolvesBracedEnvironmentReference() {
        XCTAssertEqual(
            VoiceInkAPIKeyReference.resolvedValue(
                "${ELEVENLABS_API_KEY}",
                environment: ["ELEVENLABS_API_KEY": "test-key"]
            ),
            "test-key"
        )
    }

    func testResolvedValueRejectsMissingBlankAndInvalidReferences() {
        let environment = [
            "EMPTY_KEY": "",
            "VALID_KEY": "test-key"
        ]

        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue(" \n\t ", environment: environment))
        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue("$MISSING", environment: environment))
        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue("$EMPTY_KEY", environment: environment))
        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue("$1INVALID", environment: environment))
        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue("${}", environment: environment))
    }
}
