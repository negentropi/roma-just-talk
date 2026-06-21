import Foundation
@testable import VoiceInkCore

final class LicensePolicyTests: XCTestCase {
    func testLicensePreferenceKeysPreserveExistingStorageNames() {
        XCTAssertEqual(VoiceInkLicensePreference.requiresActivationKey, "VoiceInkLicenseRequiresActivation")
        XCTAssertEqual(VoiceInkLicensePreference.hasLaunchedBeforeKey, "VoiceInkHasLaunchedBefore")
        XCTAssertEqual(VoiceInkLicensePreference.activationsLimitKey, "VoiceInkActivationsLimit")
    }

    func testLicensePreferenceStorageRoundTripsNonSensitiveFlags() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkLicensePreference.requiresActivation(from: defaults))
            XCTAssertFalse(VoiceInkLicensePreference.hasLaunchedBefore(from: defaults))
            XCTAssertEqual(VoiceInkLicensePreference.activationsLimit(from: defaults), 0)

            VoiceInkLicensePreference.saveRequiresActivation(true, to: defaults)
            VoiceInkLicensePreference.saveHasLaunchedBefore(true, to: defaults)
            VoiceInkLicensePreference.saveActivationsLimit(3, to: defaults)

            XCTAssertTrue(VoiceInkLicensePreference.requiresActivation(from: defaults))
            XCTAssertTrue(VoiceInkLicensePreference.hasLaunchedBefore(from: defaults))
            XCTAssertEqual(VoiceInkLicensePreference.activationsLimit(from: defaults), 3)
        }
    }

    func testStoredLicenseAccessPreservesExistingActivationRequirementPolicy() {
        withIsolatedDefaults { defaults in
            XCTAssertFalse(VoiceInkLicensePreference.hasUsableStoredLicense(
                licenseKey: nil,
                activationId: "activation-id",
                from: defaults
            ))

            XCTAssertTrue(VoiceInkLicensePreference.hasUsableStoredLicense(
                licenseKey: "license-key",
                activationId: nil,
                from: defaults
            ))

            VoiceInkLicensePreference.saveRequiresActivation(true, to: defaults)

            XCTAssertFalse(VoiceInkLicensePreference.hasUsableStoredLicense(
                licenseKey: "license-key",
                activationId: nil,
                from: defaults
            ))
            XCTAssertTrue(VoiceInkLicensePreference.hasUsableStoredLicense(
                licenseKey: "license-key",
                activationId: "activation-id",
                from: defaults
            ))
        }
    }

    private func withIsolatedDefaults(_ run: (UserDefaults) -> Void) {
        let suiteName = "VoiceInkCore.LicensePolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        run(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
