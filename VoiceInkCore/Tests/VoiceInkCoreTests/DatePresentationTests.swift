import Foundation
@testable import VoiceInkCore

final class DatePresentationTests: XCTestCase {
    func testAbbreviatedTimestampPreservesMacOSDetailFormat() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = testDate(timeZone: timeZone)

        XCTAssertEqual(
            VoiceInkDatePresentation.abbreviatedTimestamp(
                date,
                locale: Locale(identifier: "en_GB"),
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            ),
            "18 Jun 2026 at 12:34"
        )
    }

    func testCompactTimestampPreservesMacOSHistoryListFormat() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let date = testDate(timeZone: timeZone)

        XCTAssertEqual(
            VoiceInkDatePresentation.compactTimestamp(
                date,
                locale: Locale(identifier: "en_GB"),
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            ),
            "18 Jun at 12:34"
        )
    }

    func testRelativeTimestampUsesShortRelativeStyle() {
        let referenceDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            VoiceInkDatePresentation.relativeTimestamp(
                referenceDate.addingTimeInterval(-60),
                relativeTo: referenceDate,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "1 min. ago"
        )
        XCTAssertEqual(
            VoiceInkDatePresentation.relativeTimestamp(
                referenceDate.addingTimeInterval(60),
                relativeTo: referenceDate,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "in 1 min."
        )
    }

    private func testDate(timeZone: TimeZone) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone,
            year: 2026,
            month: 6,
            day: 18,
            hour: 12,
            minute: 34
        ).date!
    }
}
