@testable import RomaCore

final class IOSMicrophonePermissionPresentationTests: XCTestCase {
    func testMicrophonePermissionPresentationMapsRecoveryActions() {
        let granted = RomaIOSMicrophonePermissionPresentation.status(.granted)
        XCTAssertEqual(granted.recoveryAction, .none)
        XCTAssertNil(granted.recoveryButtonTitle)

        let denied = RomaIOSMicrophonePermissionPresentation.status(.denied)
        XCTAssertEqual(denied.recoveryAction, .openSettings)
        XCTAssertEqual(denied.recoveryButtonTitle, "Open Settings")

        let undetermined = RomaIOSMicrophonePermissionPresentation.status(.undetermined)
        XCTAssertEqual(undetermined.recoveryAction, .requestAccess)
        XCTAssertEqual(undetermined.recoveryButtonTitle, "Allow Microphone Access")
    }
}
