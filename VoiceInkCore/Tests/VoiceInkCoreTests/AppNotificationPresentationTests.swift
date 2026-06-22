import Foundation
@testable import VoiceInkCore

final class AppNotificationPresentationTests: XCTestCase {
    func testAppNotificationKindsPreserveCasesAndDefaultDuration() {
        XCTAssertEqual(
            VoiceInkAppNotificationKind.allCases.map(\.rawValue),
            ["error", "warning", "info", "success"]
        )
        XCTAssertEqual(VoiceInkAppNotificationKind.defaultDisplayDuration, 3.0, accuracy: 0.0001)
    }

    func testAppNotificationKindsPreserveSystemImages() {
        XCTAssertEqual(VoiceInkAppNotificationKind.error.systemImageName, "xmark.octagon.fill")
        XCTAssertEqual(VoiceInkAppNotificationKind.warning.systemImageName, "exclamationmark.triangle.fill")
        XCTAssertEqual(VoiceInkAppNotificationKind.info.systemImageName, "info.circle.fill")
        XCTAssertEqual(VoiceInkAppNotificationKind.success.systemImageName, "checkmark.circle.fill")
    }

    func testOnlyErrorNotificationsPlayFailureSound() {
        XCTAssertTrue(VoiceInkAppNotificationKind.error.playsFailureSound)
        XCTAssertFalse(VoiceInkAppNotificationKind.warning.playsFailureSound)
        XCTAssertFalse(VoiceInkAppNotificationKind.info.playsFailureSound)
        XCTAssertFalse(VoiceInkAppNotificationKind.success.playsFailureSound)
    }
}
