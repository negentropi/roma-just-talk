@testable import RomaCore

final class IOSOnboardingTutorialStateTests: XCTestCase {
    func testCompletionRequiresNonEmptySuccessfulTranscript() {
        XCTAssertFalse(RomaIOSOnboardingTutorialState.ready.canComplete)
        XCTAssertFalse(RomaIOSOnboardingTutorialState.processing.canComplete)
        XCTAssertFalse(RomaIOSOnboardingTutorialState.succeeded("  \n").canComplete)
        XCTAssertTrue(RomaIOSOnboardingTutorialState.succeeded("hello").canComplete)
        XCTAssertFalse(RomaIOSOnboardingTutorialState.failed("failed").canComplete)
    }

    func testOutcomeMapsToVisibleTutorialState() {
        XCTAssertEqual(
            RomaIOSOnboardingTutorialState.completed(with: .succeeded("hello")),
            .succeeded("hello")
        )
        XCTAssertEqual(
            RomaIOSOnboardingTutorialState.completed(with: .succeeded("  \n")),
            .failed(RomaIOSOnboardingTutorialPresentation.emptyTranscriptMessage)
        )
        XCTAssertEqual(
            RomaIOSOnboardingTutorialState.completed(with: .failed(reason: "offline")),
            .failed("offline")
        )
        XCTAssertEqual(
            RomaIOSOnboardingTutorialState.completed(with: .canceled),
            .failed(RomaTranscriptPresentation.canceledTranscriptionText)
        )
    }
}
