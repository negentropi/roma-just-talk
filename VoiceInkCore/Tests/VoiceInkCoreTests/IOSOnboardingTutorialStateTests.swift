@testable import VoiceInkCore

final class IOSOnboardingTutorialStateTests: XCTestCase {
    func testCompletionRequiresNonEmptySuccessfulTranscript() {
        XCTAssertFalse(VoiceInkIOSOnboardingTutorialState.ready.canComplete)
        XCTAssertFalse(VoiceInkIOSOnboardingTutorialState.processing.canComplete)
        XCTAssertFalse(VoiceInkIOSOnboardingTutorialState.succeeded("  \n").canComplete)
        XCTAssertTrue(VoiceInkIOSOnboardingTutorialState.succeeded("hello").canComplete)
        XCTAssertFalse(VoiceInkIOSOnboardingTutorialState.failed("failed").canComplete)
    }

    func testOutcomeMapsToVisibleTutorialState() {
        XCTAssertEqual(
            VoiceInkIOSOnboardingTutorialState.completed(with: .succeeded("hello")),
            .succeeded("hello")
        )
        XCTAssertEqual(
            VoiceInkIOSOnboardingTutorialState.completed(with: .succeeded("  \n")),
            .failed(VoiceInkIOSOnboardingTutorialPresentation.emptyTranscriptMessage)
        )
        XCTAssertEqual(
            VoiceInkIOSOnboardingTutorialState.completed(with: .failed(reason: "offline")),
            .failed("offline")
        )
        XCTAssertEqual(
            VoiceInkIOSOnboardingTutorialState.completed(with: .canceled),
            .failed(VoiceInkTranscriptPresentation.canceledTranscriptionText)
        )
    }
}
