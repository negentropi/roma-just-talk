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
            VoiceInkIOSOnboardingStep.ready.rawValue,
            "-\(VoiceInkAnnouncementPreference.isEnabledKey)",
            "NO"
        ]
        app.launch()

        let finishOnboardingButton = app.buttons[
            VoiceInkIOSOnboardingPresentation.ready.primaryButtonTitle
        ]
        XCTAssertTrue(finishOnboardingButton.waitForExistence(timeout: 8))
        finishOnboardingButton.tap()
        XCTAssertTrue(
            app.navigationBars[VoiceInkAppIdentity.displayName]
                .waitForExistence(timeout: 8)
        )

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 8))
        settingsButton.tap()

        let timeoutSlider = app.sliders.firstMatch
        scrollToHittable(timeoutSlider, in: app)
        let defaultSeconds = VoiceInkPreferenceDefault.audioSessionTimeoutSeconds
        let defaultTimeoutText = VoiceInkAudioSessionTimeoutPreference.displayText(for: defaultSeconds)
        let validSeconds = Set(stride(
            from: VoiceInkAudioSessionTimeoutPreference.minimumSeconds,
            through: VoiceInkAudioSessionTimeoutPreference.maximumSeconds,
            by: VoiceInkAudioSessionTimeoutPreference.stepSeconds
        ))
        let timeoutLabels = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+s$")
        )
        let initialLabels = timeoutLabels.allElementsBoundByIndex.map(\.label)
        let initialSeconds = uniqueTimeoutSeconds(in: initialLabels, validSeconds: validSeconds)
        attachTimeoutObservation("Before drag", labels: initialLabels, seconds: initialSeconds, slider: timeoutSlider)
        XCTAssertEqual(initialSeconds, defaultSeconds)
        XCTAssertTrue(app.staticTexts[defaultTimeoutText].isHittable)

        // A synthesized drag may stop short of the endpoint; reset needs a proven changed setting.
        timeoutSlider.adjust(toNormalizedSliderPosition: 1)
        let changedLabelAppeared = timeoutLabels.matching(
            NSPredicate(format: "label != %@", defaultTimeoutText)
        ).firstMatch.waitForExistence(timeout: 5)
        let changedLabels = timeoutLabels.allElementsBoundByIndex.map(\.label)
        let observedChangedSeconds = uniqueTimeoutSeconds(in: changedLabels, validSeconds: validSeconds)
        attachTimeoutObservation("After drag", labels: changedLabels, seconds: observedChangedSeconds, slider: timeoutSlider)
        XCTAssertTrue(changedLabelAppeared)
        let changedSeconds = try XCTUnwrap(observedChangedSeconds)
        let changedTimeoutText = try XCTUnwrap(changedLabels.first)
        XCTAssertNotEqual(changedSeconds, defaultSeconds)
        XCTAssertTrue(app.staticTexts[changedTimeoutText].isHittable)

        let resetButton = app.buttons[VoiceInkIOSAppDataResetPresentation.buttonTitle]
        scrollToHittable(resetButton, in: app)
        resetButton.tap()

        let confirmationTitle = app.staticTexts[
            VoiceInkIOSAppDataResetPresentation.confirmationTitle
        ]
        let confirmationMessage = app.staticTexts.matching(
            NSPredicate(
                format: "label == %@",
                VoiceInkIOSAppDataResetPresentation.confirmationMessage
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
        scrollToHittable(timeoutSlider, in: app, swipeUp: false)
        XCTAssertEqual(
            uniqueTimeoutSeconds(in: timeoutLabels.allElementsBoundByIndex.map(\.label), validSeconds: validSeconds),
            changedSeconds
        )
        XCTAssertTrue(app.staticTexts[changedTimeoutText].exists)
        XCTAssertTrue(app.staticTexts[changedTimeoutText].isHittable)

        scrollToHittable(resetButton, in: app)
        resetButton.tap()
        let confirmButton = app.buttons[VoiceInkIOSAppDataResetPresentation.confirmButtonTitle]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()
        XCTAssertTrue(confirmButton.waitForNonExistence(timeout: 5))
        scrollToHittable(timeoutSlider, in: app, swipeUp: false)
        XCTAssertTrue(app.staticTexts[defaultTimeoutText].waitForExistence(timeout: 5))
        XCTAssertEqual(
            uniqueTimeoutSeconds(in: timeoutLabels.allElementsBoundByIndex.map(\.label), validSeconds: validSeconds),
            defaultSeconds
        )
        XCTAssertTrue(app.staticTexts[defaultTimeoutText].isHittable)

        app.terminate()
        app.launchArguments = [
            "-\(VoiceInkAnnouncementPreference.isEnabledKey)",
            "NO"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts[VoiceInkIOSOnboardingPresentation.welcome.title]
                .waitForExistence(timeout: 8)
        )
        attachScreenshot(named: "Onboarding after app data reset")
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

    private func uniqueTimeoutSeconds(in labels: [String], validSeconds: Set<Int>) -> Int? {
        guard labels.count == 1, let label = labels.first, label.hasSuffix("s"),
              let seconds = Int(label.dropLast()), "\(seconds)s" == label,
              validSeconds.contains(seconds) else { return nil }
        return seconds
    }

    @MainActor
    private func attachTimeoutObservation(_ stage: String, labels: [String], seconds: Int?, slider: XCUIElement) {
        let attachment = XCTAttachment(string:
            "labels=\(labels)\nseconds=\(String(describing: seconds))\nsliderLabel=\(slider.label)\nsliderValue=\(String(describing: slider.value))\nsliderFrame=\(slider.frame)\nsliderHittable=\(slider.isHittable)"
        )
        attachment.name = "Reset timeout: \(stage)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        swipeUp: Bool = true,
        maxSwipes: Int = 12
    ) {
        var remainingSwipes = maxSwipes
        while !element.isHittable && remainingSwipes > 0 {
            if swipeUp { app.swipeUp() } else { app.swipeDown() }
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
