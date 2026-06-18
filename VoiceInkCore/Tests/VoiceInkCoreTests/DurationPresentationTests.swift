import Foundation
@testable import VoiceInkCore

final class DurationPresentationTests: XCTestCase {
    func testPositiveDurationVisibilityOnlyAllowsPositiveDurations() {
        XCTAssertFalse(VoiceInkDurationPresentation.shouldShowPositiveDuration(-1))
        XCTAssertFalse(VoiceInkDurationPresentation.shouldShowPositiveDuration(0))
        XCTAssertTrue(VoiceInkDurationPresentation.shouldShowPositiveDuration(0.1))
    }

    func testMinutesSecondsUsesUnpaddedMinutesByDefault() {
        XCTAssertEqual(VoiceInkDurationPresentation.minutesSeconds(5), "0:05")
        XCTAssertEqual(VoiceInkDurationPresentation.minutesSeconds(65), "1:05")
    }

    func testMinutesSecondsCanPadMinutesToTwoDigits() {
        XCTAssertEqual(
            VoiceInkDurationPresentation.minutesSeconds(5, padMinutesToTwoDigits: true),
            "00:05"
        )
        XCTAssertEqual(
            VoiceInkDurationPresentation.minutesSeconds(65, padMinutesToTwoDigits: true),
            "01:05"
        )
    }

    func testMinutesSecondsTruncatesFractionalSeconds() {
        XCTAssertEqual(VoiceInkDurationPresentation.minutesSeconds(65.9), "1:05")
    }

    func testAbbreviatedMinutesSecondsMatchesMetricsFormatting() {
        XCTAssertEqual(VoiceInkDurationPresentation.abbreviatedMinutesSeconds(0), "0s")
        XCTAssertEqual(VoiceInkDurationPresentation.abbreviatedMinutesSeconds(65), "1m 5s")
        XCTAssertEqual(VoiceInkDurationPresentation.abbreviatedMinutesSeconds(125.6), "2m 5s")
    }

    func testPositiveDurationReturnsFallbackForZeroOrNegativeDurations() {
        XCTAssertEqual(
            VoiceInkDurationPresentation.positiveDuration(0, style: .full, fallback: "Time savings coming soon"),
            "Time savings coming soon"
        )
        XCTAssertEqual(VoiceInkDurationPresentation.positiveDuration(-1, style: .abbreviated), "–")
    }

    func testPositiveDurationUsesMinuteSecondUnitsBelowOneHour() {
        XCTAssertEqual(VoiceInkDurationPresentation.positiveDuration(65, style: .abbreviated), "1m 5s")
    }

    func testPositiveDurationUsesHourMinuteUnitsFromOneHour() {
        XCTAssertEqual(VoiceInkDurationPresentation.positiveDuration(3665, style: .abbreviated), "1h 1m")
    }

    func testCompactElapsedUsesMillisecondsForSubsecondDurations() {
        XCTAssertEqual(VoiceInkDurationPresentation.compactElapsed(0.125), "125ms")
    }

    func testCompactElapsedUsesOneDecimalSecondsUnderOneMinute() {
        XCTAssertEqual(VoiceInkDurationPresentation.compactElapsed(12.34), "12.3s")
    }

    func testCompactElapsedUsesMinutesAndRoundedSecondsFromOneMinute() {
        XCTAssertEqual(VoiceInkDurationPresentation.compactElapsed(125.6), "2m 6s")
    }
}
