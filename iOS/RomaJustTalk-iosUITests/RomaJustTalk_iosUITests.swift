import XCTest
import RomaCore

final class RomaIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsPrimaryIOSExperience() throws {
        let app = configuredApp(hasCompletedOnboarding: true)
        app.launch()

        let notesTitle = app.navigationBars[RomaAppIdentity.displayName]
        XCTAssertTrue(notesTitle.waitForExistence(timeout: 8))
        attachScreenshot(named: "Primary iOS experience")
    }

    @MainActor
    func testFirstRunShowsRomaJustTalkOnboarding() throws {
        let app = configuredApp(hasCompletedOnboarding: false)
        app.launch()

        XCTAssertTrue(
            app.staticTexts[RomaIOSOnboardingPresentation.welcome.title]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.buttons[RomaIOSOnboardingPresentation.welcome.primaryButtonTitle].exists)
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
        XCTAssertTrue(app.staticTexts[RomaIOSMicrophonePermissionPresentation.settingsRowTitle].exists)
        XCTAssertTrue(app.staticTexts[RomaIOSKeyboardSetupPresentation.settingsRowTitle].exists)
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

    @MainActor
    func testAudioRoutingSettingsDefaultToSystemManagedAndRevealPreferredMicrophoneControls() throws {
        let app = configuredApp(hasCompletedOnboarding: true)
        app.launch()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 8))
        settingsButton.tap()

        let audioRoutingRow = app.staticTexts["Audio Routing"]
        XCTAssertTrue(audioRoutingRow.waitForExistence(timeout: 5))
        audioRoutingRow.tap()

        XCTAssertTrue(app.navigationBars["Audio Routing"].waitForExistence(timeout: 5))
        let systemRoutingSwitch = app.switches["Follow System Audio Routing"]
        XCTAssertTrue(systemRoutingSwitch.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSwitchValue("1", in: systemRoutingSwitch))
        let preferredMicrophoneSection = app.staticTexts["Preferred Microphone"]
        XCTAssertTrue(preferredMicrophoneSection.waitForNonExistence(timeout: 2))
        addTeardownBlock { [weak self] in
            guard let self, systemRoutingSwitch.exists else { return }

            let switchValue = systemRoutingSwitch.value as? String
            if switchValue == "0"
                || (switchValue == nil && preferredMicrophoneSection.exists) {
                self.tapTrailingControl(of: systemRoutingSwitch)
                XCTAssertTrue(self.waitForSwitchValue("1", in: systemRoutingSwitch))
            }
            XCTAssertTrue(preferredMicrophoneSection.waitForNonExistence(timeout: 5))
        }
        attachScreenshot(named: "System-managed audio routing")

        tapTrailingControl(of: systemRoutingSwitch)

        XCTAssertTrue(preferredMicrophoneSection.waitForExistence(timeout: 5))
        attachScreenshot(named: "Preferred microphone controls")

        tapTrailingControl(of: systemRoutingSwitch)
        XCTAssertTrue(preferredMicrophoneSection.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForSwitchValue("1", in: systemRoutingSwitch))
    }

    @MainActor
    func testResetAllAppDataCancelPreservesSettingsAndConfirmedResetRestartsOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-iOSOnboardingStep",
            RomaIOSOnboardingStep.ready.rawValue
        ]
        app.launch()

        let finishOnboardingButton = app.buttons[
            RomaIOSOnboardingPresentation.ready.primaryButtonTitle
        ]
        XCTAssertTrue(finishOnboardingButton.waitForExistence(timeout: 8))
        finishOnboardingButton.tap()
        XCTAssertTrue(
            app.navigationBars[RomaAppIdentity.displayName]
                .waitForExistence(timeout: 8)
        )

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 8))
        settingsButton.tap()

        let timeoutSlider = app.sliders.firstMatch
        scrollToHittable(timeoutSlider, in: app)
        let changedTimeoutText = RomaAudioSessionTimeoutPreference.displayText(
            for: RomaAudioSessionTimeoutPreference.maximumSeconds
        )
        timeoutSlider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue(app.staticTexts[changedTimeoutText].waitForExistence(timeout: 5))

        let resetButton = app.buttons[RomaIOSAppDataResetPresentation.buttonTitle]
        scrollToHittable(resetButton, in: app)
        resetButton.tap()

        let confirmationTitle = app.staticTexts[
            RomaIOSAppDataResetPresentation.confirmationTitle
        ]
        let confirmationMessage = app.staticTexts.matching(
            NSPredicate(
                format: "label == %@",
                RomaIOSAppDataResetPresentation.confirmationMessage
            )
        ).firstMatch
        let dismissPopup = app.otherElements["dismiss popup"]
        XCTAssertTrue(confirmationTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmationMessage.exists)
        XCTAssertTrue(dismissPopup.exists)
        attachScreenshot(named: "Reset app data confirmation")

        // iOS 26 exposes cancellation as a backdrop control without a Cancel button.
        dismissPopup.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)
        ).tap()
        XCTAssertTrue(confirmationTitle.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        XCTAssertTrue(app.staticTexts[changedTimeoutText].exists)

        resetButton.tap()
        let confirmButton = app.buttons[RomaIOSAppDataResetPresentation.confirmButtonTitle]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()
        XCTAssertTrue(confirmButton.waitForNonExistence(timeout: 5))
        let defaultTimeoutText = RomaAudioSessionTimeoutPreference.displayText(
            for: RomaPreferenceDefault.audioSessionTimeoutSeconds
        )
        XCTAssertTrue(app.staticTexts[defaultTimeoutText].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(
            app.staticTexts[RomaIOSOnboardingPresentation.welcome.title]
                .waitForExistence(timeout: 8)
        )
        attachScreenshot(named: "Onboarding after app data reset")
    }

    private func configuredApp(hasCompletedOnboarding: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-\(RomaUserDefaultsKey.hasCompletedOnboarding)",
            hasCompletedOnboarding ? "YES" : "NO"
        ]
        return app
    }

    private func waitForSwitchValue(
        _ value: String,
        in element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func tapTrailingControl(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 12
    ) {
        var remainingSwipes = maxSwipes
        while !element.isHittable && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
