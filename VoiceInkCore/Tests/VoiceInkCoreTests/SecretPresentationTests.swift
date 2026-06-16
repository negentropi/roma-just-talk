#if canImport(XCTest)
import XCTest
@testable import VoiceInkCore

final class SecretPresentationTests: XCTestCase {
    func testObfuscatedAPIKeyReturnsNilForEmptyOrWhitespaceOnlyKeys() {
        XCTAssertNil(VoiceInkSecretPresentation.obfuscatedAPIKey(""))
        XCTAssertNil(VoiceInkSecretPresentation.obfuscatedAPIKey("   \n"))
    }

    func testObfuscatedAPIKeyMasksShortKeysCompletely() {
        XCTAssertEqual(VoiceInkSecretPresentation.obfuscatedAPIKey("abc123"), "••••••")
    }

    func testObfuscatedAPIKeyShowsPrefixAndSuffixForLongKeys() {
        XCTAssertEqual(
            VoiceInkSecretPresentation.obfuscatedAPIKey("sk-1234567890"),
            "sk-1•••••7890"
        )
    }

    func testObfuscatedAPIKeyTrimsWhitespaceBeforeMasking() {
        XCTAssertEqual(
            VoiceInkSecretPresentation.obfuscatedAPIKey("  abc123  "),
            "••••••"
        )
    }

    func testObfuscatedAPIKeyPreservesCurrentSevenCharacterEdgeCase() {
        XCTAssertEqual(
            VoiceInkSecretPresentation.obfuscatedAPIKey("abcdefg"),
            "abcd••••efg"
        )
    }
}
#endif
