import Foundation
@testable import RomaCore

final class IOSOnboardingProgressStoreTests: XCTestCase {
    func testPersistedRawValuesStayStable() {
        XCTAssertEqual(RomaIOSOnboardingStep.welcome.rawValue, "welcome")
        XCTAssertEqual(RomaIOSOnboardingStep.microphoneSetup.rawValue, "microphoneSetup")
        XCTAssertEqual(RomaIOSOnboardingStep.modelDownload.rawValue, "modelDownload")
        XCTAssertEqual(RomaIOSOnboardingStep.keyboardSetup.rawValue, "keyboardSetup")
        XCTAssertEqual(RomaIOSOnboardingStep.tutorial.rawValue, "tutorial")
        XCTAssertEqual(RomaIOSOnboardingStep.ready.rawValue, "ready")
    }

    func testDefaultsAndIgnoresMalformedValues() {
        withDefaults { defaults in
            XCTAssertEqual(RomaIOSOnboardingProgressStore.step(in: defaults), .welcome)

            defaults.set("unknown", forKey: "iOSOnboardingStep")

            XCTAssertEqual(RomaIOSOnboardingProgressStore.step(in: defaults), .welcome)
        }
    }

    func testRoundTripsCurrentStep() {
        withDefaults { defaults in
            RomaIOSOnboardingProgressStore.save(.keyboardSetup, in: defaults)

            XCTAssertEqual(defaults.string(forKey: "iOSOnboardingStep"), "keyboardSetup")
            XCTAssertEqual(RomaIOSOnboardingProgressStore.step(in: defaults), .keyboardSetup)
        }
    }

    func testResetReturnsToWelcome() {
        withDefaults { defaults in
            RomaIOSOnboardingProgressStore.save(.ready, in: defaults)
            RomaIOSOnboardingProgressStore.reset(in: defaults)

            XCTAssertNil(defaults.string(forKey: "iOSOnboardingStep"))
            XCTAssertEqual(RomaIOSOnboardingProgressStore.step(in: defaults), .welcome)
        }
    }

    private func withDefaults(_ assertions: (UserDefaults) -> Void) {
        let suiteName = "RomaCore.IOSOnboardingProgressStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        assertions(defaults)
    }
}
