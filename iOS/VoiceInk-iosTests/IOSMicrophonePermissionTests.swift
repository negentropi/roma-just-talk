import XCTest
import VoiceInkCore
@testable import roma_just_talk

@MainActor
final class IOSMicrophonePermissionTests: XCTestCase {
    func testModelRequestsRefreshesAndOpensSettingsFromCurrentStatus() {
        var currentStatus = VoiceInkRecordingPermissionStatus.undetermined
        var events: [String] = []
        let model = IOSMicrophonePermissionModel(
            statusProvider: { currentStatus },
            requestAccess: { completion in
                events.append("request")
                currentStatus = .granted
                completion(true)
            },
            openSettings: {
                events.append("settings")
            }
        )

        XCTAssertEqual(model.status, .undetermined)
        model.performRecoveryAction()
        XCTAssertEqual(events, ["request"])
        XCTAssertEqual(model.status, .granted)

        currentStatus = .denied
        model.refresh()
        model.performRecoveryAction()
        XCTAssertEqual(events, ["request", "settings"])
        XCTAssertEqual(model.status, .denied)
    }

    func testGrantedModelHasNoRecoverySideEffect() {
        var events: [String] = []
        let model = IOSMicrophonePermissionModel(
            statusProvider: { .granted },
            requestAccess: { _ in events.append("request") },
            openSettings: { events.append("settings") }
        )

        model.performRecoveryAction()

        XCTAssertEqual(events, [])
    }
}
