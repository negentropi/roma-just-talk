import Foundation
@testable import VoiceInkCore

final class SessionMetricPolicyTests: XCTestCase {
    func testValuesUseEnhancedTextForWordCountWhenEnhancementWasAttempted() {
        let values = VoiceInkSessionMetricPolicy.values(for: Source(
            text: "raw words",
            enhancedText: "enhanced words count here",
            duration: 12,
            transcriptionDuration: 3,
            enhancementDuration: 2
        ))

        XCTAssertEqual(values.wordCount, 4)
        XCTAssertEqual(values.audioDuration, 12)
        XCTAssertEqual(values.transcriptionDuration, 3)
        XCTAssertEqual(values.speedFactor, 4)
        XCTAssertEqual(values.enhancementDuration, 2)
    }

    func testValuesUseRawTextWhenEnhancementDurationIsMissing() {
        let values = VoiceInkSessionMetricPolicy.values(for: Source(
            text: "raw words",
            enhancedText: "enhanced words count here",
            duration: 12,
            transcriptionDuration: 3,
            enhancementDuration: nil
        ))

        XCTAssertEqual(values.wordCount, 2)
    }

    func testValuesClampNonPositiveDurationsAndSkipSpeedFactor() {
        let values = VoiceInkSessionMetricPolicy.values(for: Source(
            text: "raw words",
            enhancedText: "enhanced words",
            duration: -4,
            transcriptionDuration: 0,
            enhancementDuration: -1
        ))

        XCTAssertEqual(values.audioDuration, 0)
        XCTAssertNil(values.transcriptionDuration)
        XCTAssertNil(values.speedFactor)
        XCTAssertNil(values.enhancementDuration)
    }
}

private struct Source: VoiceInkSessionMetricSource {
    let text: String
    let enhancedText: String?
    let duration: TimeInterval
    let transcriptionDuration: TimeInterval?
    let enhancementDuration: TimeInterval?
}
