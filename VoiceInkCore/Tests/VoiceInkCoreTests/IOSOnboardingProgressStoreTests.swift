import Foundation
@testable import VoiceInkCore

final class IOSOnboardingProgressStoreTests: XCTestCase {
    func testPersistedRawValuesStayStable() {
        XCTAssertEqual(VoiceInkIOSOnboardingStep.welcome.rawValue, "welcome")
        XCTAssertEqual(VoiceInkIOSOnboardingStep.microphoneSetup.rawValue, "microphoneSetup")
        XCTAssertEqual(VoiceInkIOSOnboardingStep.modelDownload.rawValue, "modelDownload")
        XCTAssertEqual(VoiceInkIOSOnboardingStep.keyboardSetup.rawValue, "keyboardSetup")
        XCTAssertEqual(VoiceInkIOSOnboardingStep.tutorial.rawValue, "tutorial")
        XCTAssertEqual(VoiceInkIOSOnboardingStep.ready.rawValue, "ready")
    }

    func testDefaultsAndIgnoresMalformedValues() {
        withDefaults { defaults in
            XCTAssertEqual(VoiceInkIOSOnboardingProgressStore.step(in: defaults), .welcome)

            defaults.set("unknown", forKey: "iOSOnboardingStep")

            XCTAssertEqual(VoiceInkIOSOnboardingProgressStore.step(in: defaults), .welcome)
        }
    }

    func testRoundTripsCurrentStep() {
        withDefaults { defaults in
            VoiceInkIOSOnboardingProgressStore.save(.keyboardSetup, in: defaults)

            XCTAssertEqual(defaults.string(forKey: "iOSOnboardingStep"), "keyboardSetup")
            XCTAssertEqual(VoiceInkIOSOnboardingProgressStore.step(in: defaults), .keyboardSetup)
        }
    }

    func testResetReturnsToWelcome() {
        withDefaults { defaults in
            VoiceInkIOSOnboardingProgressStore.save(.ready, in: defaults)
            VoiceInkIOSOnboardingProgressStore.reset(in: defaults)

            XCTAssertNil(defaults.string(forKey: "iOSOnboardingStep"))
            XCTAssertEqual(VoiceInkIOSOnboardingProgressStore.step(in: defaults), .welcome)
        }
    }

    private func withDefaults(_ assertions: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.IOSOnboardingProgressStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        assertions(defaults)
    }
}
