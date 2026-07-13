//
//  VoiceInkUITests.swift
//  VoiceInkUITests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import XCTest

final class VoiceInkUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstRunShowsOnboarding() throws {
        let app = configuredApp(hasCompletedOnboarding: false)
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Welcome to the Future of Typing"]
                .waitForExistence(timeout: 15)
        )
        XCTAssertTrue(app.buttons["Get Started"].exists)
        attachScreenshot(of: app, named: "macOS onboarding")
    }

    @MainActor
    func testCompletedSetupCanOpenSettings() throws {
        let app = configuredApp(hasCompletedOnboarding: true)
        app.launch()

        XCTAssertTrue(app.staticTexts["roma-just-talk"].firstMatch.waitForExistence(timeout: 15))

        let settings = app.staticTexts["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()

        XCTAssertTrue(app.buttons["Reset Onboarding"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "macOS settings")
    }

    private func configuredApp(hasCompletedOnboarding: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding",
            hasCompletedOnboarding ? "YES" : "NO",
            "-macOSOnboardingStage",
            "welcome",
            "-enableAnnouncements",
            "NO",
            "-ShowMenuBarIcon",
            "NO"
        ]
        return app
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
