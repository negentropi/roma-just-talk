import Foundation
@testable import VoiceInkCore

final class CustomVocabularyTermsTests: XCTestCase {
    func testNormalizedTermsTrimDropBlankAndDeduplicateCaseInsensitively() {
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized([
                "  Roma  ",
                "",
                "roma",
                "VoiceInk",
                " voiceink ",
                "Cursor"
            ]),
            ["Roma", "VoiceInk", "Cursor"]
        )
    }

    func testNormalizedTermsApplyOptionalLimitAfterFiltering() {
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(
                ["", " Roma ", "roma", "Cursor", "SwiftData"],
                limit: 2
            ),
            ["Roma", "Cursor"]
        )
    }
}
