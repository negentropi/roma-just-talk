import Foundation
import VoiceInkCore

final class AppIntentPresentationTests: XCTestCase {
    func testMiniRecorderIntentPresentationPreservesMacOSShortcutCopy() {
        XCTAssertEqual(
            VoiceInkMiniRecorderAppIntentPresentation.toggle,
            VoiceInkAppIntentPresentation(
                title: "Toggle VoiceInk Recorder",
                description: "Start or stop the VoiceInk mini recorder for voice transcription.",
                successDialog: "VoiceInk recorder toggled"
            )
        )

        XCTAssertEqual(
            VoiceInkMiniRecorderAppIntentPresentation.dismiss,
            VoiceInkAppIntentPresentation(
                title: "Dismiss VoiceInk Recorder",
                description: "Dismiss the VoiceInk mini recorder and cancel any active recording.",
                successDialog: "VoiceInk recorder dismissed"
            )
        )
    }

    func testMiniRecorderRequestPreservesMacOSNotificationNames() {
        XCTAssertEqual(VoiceInkMiniRecorderRequest.toggleNotificationName.rawValue, "toggleMiniRecorder")
        XCTAssertEqual(VoiceInkMiniRecorderRequest.dismissNotificationName.rawValue, "dismissMiniRecorder")
    }
}
