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

    func testNormalizedTermsApplyDeepgramStreamingLimitFromSharedUsePolicy() {
        let terms = (1...55).map { "term-\($0)" }

        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .streamingTranscription(.deepgram)),
            Array(terms.prefix(50))
        )
    }

    func testNormalizedTermsLeaveOtherUsesUnlimited() {
        let terms = (1...55).map { "term-\($0)" }

        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .batchTranscription(.deepgram)),
            terms
        )
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .streamingTranscription(.soniox)),
            terms
        )
        XCTAssertEqual(
            VoiceInkCustomVocabularyTerms.normalized(terms, for: .postProcessingContext),
            terms
        )
    }
}
