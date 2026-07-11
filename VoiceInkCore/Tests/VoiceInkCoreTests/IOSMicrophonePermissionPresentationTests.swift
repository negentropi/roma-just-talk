@testable import VoiceInkCore

final class IOSMicrophonePermissionPresentationTests: XCTestCase {
    func testMicrophonePermissionPresentationMapsRecoveryActions() {
        let granted = VoiceInkIOSMicrophonePermissionPresentation.status(.granted)
        XCTAssertEqual(granted.recoveryAction, .none)
        XCTAssertNil(granted.recoveryButtonTitle)

        let denied = VoiceInkIOSMicrophonePermissionPresentation.status(.denied)
        XCTAssertEqual(denied.recoveryAction, .openSettings)
        XCTAssertEqual(denied.recoveryButtonTitle, "Open Settings")

        let undetermined = VoiceInkIOSMicrophonePermissionPresentation.status(.undetermined)
        XCTAssertEqual(undetermined.recoveryAction, .requestAccess)
        XCTAssertEqual(undetermined.recoveryButtonTitle, "Allow Microphone Access")
    }
}
