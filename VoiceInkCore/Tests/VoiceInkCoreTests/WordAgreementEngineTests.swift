import Foundation
@testable import VoiceInkCore

final class WordAgreementEngineTests: XCTestCase {
    func testTimedWordNormalizesCaseHyphenAndPunctuationForAgreement() {
        XCTAssertEqual(
            TimedWord(text: "Follow-up!", startTime: 0, endTime: 1).normalizedText,
            "follow up"
        )
    }

    func testFirstPassReturnsHypothesisWithoutConfirmation() {
        let engine = WordAgreementEngine(config: fastConfirmationConfig())
        let words = sentenceWords(["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."])

        let result = engine.processTranscriptionResult(words: words)

        XCTAssertEqual(result.fullText, "One two three. Four five six. Seven eight nine.")
        XCTAssertEqual(result.hypothesisText, "One two three. Four five six. Seven eight nine.")
        XCTAssertEqual(result.newlyConfirmedText, "")
        XCTAssertEqual(engine.confirmedText, "")
    }

    func testStableAgreementConfirmsThroughThirdLatestSentenceBoundary() {
        let engine = WordAgreementEngine(config: fastConfirmationConfig())
        let words = sentenceWords(["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."])

        _ = engine.processTranscriptionResult(words: words)
        let result = engine.processTranscriptionResult(words: words)

        XCTAssertEqual(result.newlyConfirmedText, "One two three.")
        XCTAssertEqual(result.hypothesisText, "Four five six. Seven eight nine.")
        XCTAssertEqual(result.fullText, "One two three. Four five six. Seven eight nine.")
        XCTAssertEqual(engine.confirmedText, "One two three.")
        XCTAssertEqual(engine.confirmedEndTime, 3)
        XCTAssertEqual(engine.hypothesisStartTime, 3)
    }

    func testLowConfidencePassDoesNotCountTowardConfirmation() {
        let engine = WordAgreementEngine(config: AgreementConfig(
            tokenConfirmationsNeeded: 2,
            minWordsToConfirm: 3
        ))
        let words = sentenceWords(["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."])

        _ = engine.processTranscriptionResult(words: words)
        _ = engine.processTranscriptionResult(words: words, resultConfidence: 0.01)
        let result = engine.processTranscriptionResult(words: words)

        XCTAssertEqual(result.newlyConfirmedText, "")
        XCTAssertEqual(engine.confirmedText, "")
    }

    func testLowBoundaryWordConfidencePreventsConfirmation() {
        let engine = WordAgreementEngine(config: fastConfirmationConfig())
        let words = sentenceWords(
            ["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."],
            lowConfidenceIndices: [1]
        )

        _ = engine.processTranscriptionResult(words: words)
        let result = engine.processTranscriptionResult(words: words)

        XCTAssertEqual(result.newlyConfirmedText, "")
        XCTAssertEqual(engine.confirmedText, "")
    }

    func testResetClearsAgreementState() {
        let engine = WordAgreementEngine(config: fastConfirmationConfig())
        let words = sentenceWords(["One", "two", "three.", "Four", "five", "six.", "Seven", "eight", "nine."])
        _ = engine.processTranscriptionResult(words: words)
        _ = engine.processTranscriptionResult(words: words)

        engine.reset()

        XCTAssertEqual(engine.confirmedText, "")
        XCTAssertEqual(engine.confirmedEndTime, 0)
        XCTAssertEqual(engine.hypothesisStartTime, 0)
        XCTAssertEqual(engine.processTranscriptionResult(words: words).newlyConfirmedText, "")
    }

    func testRollingPreloadConfigPreservesExistingStreamingValues() {
        let config = AgreementConfig.rollingPreload

        XCTAssertEqual(config.transcribeIntervalSeconds, 0.35)
        XCTAssertEqual(config.tokenConfirmationsNeeded, 3)
        XCTAssertEqual(config.minWordsToConfirm, 5)
        XCTAssertEqual(config.minPassConfidence, 0.15, accuracy: 0.0001)
        XCTAssertEqual(config.minWordConfidence, 0.6, accuracy: 0.0001)
        XCTAssertEqual(config.cachedFinalizationMaxLagSeconds, 0.25)
        XCTAssertTrue(config.runsImmediatePassOnBufferedAudio)
    }

    private func fastConfirmationConfig() -> AgreementConfig {
        AgreementConfig(
            transcribeIntervalSeconds: 1,
            tokenConfirmationsNeeded: 1,
            minWordsToConfirm: 3,
            minPassConfidence: 0.15,
            minWordConfidence: 0.6,
            cachedFinalizationMaxLagSeconds: 0.35,
            runsImmediatePassOnBufferedAudio: false
        )
    }

    private func sentenceWords(_ texts: [String], lowConfidenceIndices: Set<Int> = []) -> [TimedWord] {
        texts.enumerated().map { index, text in
            TimedWord(
                text: text,
                startTime: Double(index),
                endTime: Double(index + 1),
                confidence: lowConfidenceIndices.contains(index) ? 0.2 : 0.95
            )
        }
    }
}
