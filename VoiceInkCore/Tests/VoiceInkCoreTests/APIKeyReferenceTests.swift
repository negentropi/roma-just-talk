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
            "WHITESPACE_KEY": " \n\t ",
            "VALID_KEY": "test-key"
        ]

        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue(" \n\t ", environment: environment))
        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue("$MISSING", environment: environment))
        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue("$EMPTY_KEY", environment: environment))
        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue("$WHITESPACE_KEY", environment: environment))
        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue("$1INVALID", environment: environment))
        XCTAssertNil(VoiceInkAPIKeyReference.resolvedValue("${}", environment: environment))
    }

    func testProviderAPIKeyLookupUsesResolvedStoredKeyFirst() {
        let environment = [
            "ELEVENLABS_API_KEY": "fallback-key",
            "STORED_KEY": "stored-env-key"
        ]

        XCTAssertEqual(
            VoiceInkProviderAPIKeyLookup.usableAPIKey(
                storedKey: " literal-key ",
                providerName: "ElevenLabs",
                environment: environment
            ),
            "literal-key"
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyLookup.usableAPIKey(
                storedKey: "$STORED_KEY",
                providerName: "ElevenLabs",
                environment: environment
            ),
            "stored-env-key"
        )
    }

    func testProviderAPIKeyLookupUsesProviderEnvironmentFallbackWhenStoredKeyIsMissingOrInvalid() {
        let environment = [
            "ELEVENLABS_API_KEY": "fallback-key"
        ]

        XCTAssertEqual(
            VoiceInkProviderAPIKeyLookup.usableAPIKey(
                storedKey: nil,
                providerName: "ElevenLabs",
                environment: environment
            ),
            "fallback-key"
        )
        XCTAssertEqual(
            VoiceInkProviderAPIKeyLookup.usableAPIKey(
                storedKey: "$MISSING",
                providerName: "elevenlabs",
                environment: environment
            ),
            "fallback-key"
        )
    }

    func testProviderAPIKeyLookupRejectsBlankAndProvidersWithoutEnvironmentFallback() {
        let environment = [
            "ELEVENLABS_API_KEY": "fallback-key"
        ]

        XCTAssertNil(
            VoiceInkProviderAPIKeyLookup.usableAPIKey(
                storedKey: " \n\t ",
                providerName: "Groq",
                environment: environment
            )
        )
        XCTAssertNil(
            VoiceInkProviderAPIKeyLookup.usableAPIKey(
                storedKey: nil,
                providerName: "Groq",
                environment: environment
            )
        )
    }
}
