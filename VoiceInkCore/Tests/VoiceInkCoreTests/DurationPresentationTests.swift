import Foundation
@testable import VoiceInkCore

final class DurationPresentationTests: XCTestCase {
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
