import XCTest

final class VoiceInkIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPrimaryIOSExperience() throws {
        let app = XCUIApplication()
        app.launch()

        let notesTitle = app.navigationBars["roma just talk"]
        let onboardingTitle = app.staticTexts["Welcome to roma just talk"]

        XCTAssertTrue(
            notesTitle.waitForExistence(timeout: 5) || onboardingTitle.waitForExistence(timeout: 5),
            "Expected either the notes list or first-run onboarding to be visible after launch."
        )
    }
}
