import Foundation
import NaturalLanguage
@testable import VoiceInkCore

final class WordCounterTests: XCTestCase {
    func testCountsNaturalLanguageWords() {
        XCTAssertEqual(VoiceInkWordCounter.count(in: "quick release wins"), 3)
    }

    func testIgnoresWhitespaceOnlyText() {
        XCTAssertEqual(VoiceInkWordCounter.count(in: " \n\t "), 0)
    }

    func testCountsWordsAcrossPunctuation() {
        XCTAssertEqual(VoiceInkWordCounter.count(in: "Yes, Roma works."), 3)
    }

    func testCountsWordsWithExplicitLanguageAcrossPunctuation() {
        XCTAssertEqual(
            VoiceInkWordCounter.count(in: "Yes, Roma works.", language: .english),
            3
        )
    }
}
