#if canImport(XCTest)
import XCTest
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
}
#endif
