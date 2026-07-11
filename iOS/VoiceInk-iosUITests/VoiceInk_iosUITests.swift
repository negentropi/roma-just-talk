import XCTest
import VoiceInkCore

final class VoiceInkIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPrimaryIOSExperience() throws {
        let app = configuredApp(hasCompletedOnboarding: true)
        app.launch()

        let notesTitle = app.navigationBars[VoiceInkAppIdentity.displayName]
        XCTAssertTrue(notesTitle.waitForExistence(timeout: 8))
        attachScreenshot(named: "Primary iOS experience")
    }

    @MainActor
    func testFirstRunShowsRomaJustTalkOnboarding() throws {
        let app = configuredApp(hasCompletedOnboarding: false)
        app.launch()

        XCTAssertTrue(
            app.staticTexts[VoiceInkIOSOnboardingPresentation.welcome.title]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.buttons[VoiceInkIOSOnboardingPresentation.welcome.primaryButtonTitle].exists)
        attachScreenshot(named: "Roma Just Talk onboarding")
    }

    @MainActor
    func testSettingsExposeParityControls() throws {
        let app = configuredApp(hasCompletedOnboarding: true)
        app.launch()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 8))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[VoiceInkIOSMicrophonePermissionPresentation.settingsRowTitle].exists)
        XCTAssertTrue(app.staticTexts[VoiceInkIOSKeyboardSetupPresentation.settingsRowTitle].exists)
        XCTAssertTrue(app.staticTexts["AI Enhancement"].exists)
        XCTAssertTrue(app.staticTexts["Recording Feedback"].exists)
        attachScreenshot(named: "iOS parity settings")

        app.staticTexts["AI Enhancement"].tap()
        XCTAssertTrue(app.navigationBars["AI Enhancement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Use keyboard text context"].exists)
        attachScreenshot(named: "AI enhancement behavior")

        app.navigationBars["AI Enhancement"].buttons["Settings"].tap()
        app.staticTexts["Recording Feedback"].tap()
        XCTAssertTrue(app.navigationBars["Recording Feedback"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Haptic Feedback"].exists)
        XCTAssertTrue(app.switches["Sound Feedback"].exists)
        attachScreenshot(named: "Recording feedback behavior")
    }

    private func configuredApp(hasCompletedOnboarding: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-\(VoiceInkUserDefaultsKey.hasCompletedOnboarding)",
            hasCompletedOnboarding ? "YES" : "NO",
            "-\(VoiceInkAnnouncementPreference.isEnabledKey)",
            "NO"
        ]
        return app
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
