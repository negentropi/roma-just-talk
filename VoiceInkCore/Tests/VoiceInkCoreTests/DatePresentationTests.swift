import Foundation
@testable import VoiceInkCore

final class DatePresentationTests: XCTestCase {
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
}
